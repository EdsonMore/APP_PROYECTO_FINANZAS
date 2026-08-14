import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/models/achievement.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/services/insights_engine.dart';

/// Motor de gamificación: calcula qué medallas ha desbloqueado el usuario
/// según su comportamiento financiero real.
class AchievementsService {
  AchievementsService();

  static const int _antThreshold = AppConfig.antRecordExpenseThreshold;

  /// Devuelve todos los logros definidos con su estado desbloqueado/fijado.
  List<Achievement> compute({
    required List<Transaction> transactions,
    double? monthlyBudget,
    required int coupleMonthCount,
    required int paidSplits,
  }) {
    final now = DateTime.now();
    final projection = InsightsEngine().projectSpending(transactions);

    // 1) Superviviente de Fin de Mes: hay gasto este mes y no se superó el
    //    presupuesto mensual (o se mantuvo dentro de la proyección).
    final survivors = projection.thisMonth > 0;
    final survivorOk =
        monthlyBudget == null || projection.monthlyProjected <= monthlyBudget;

    // 2) Escudo Anti-Antojos: sin gastos hormiga (<= S/15) en los últimos 3 días.
    final last3Days = now.subtract(const Duration(days: 3));
    final hasRecentAnt = transactions.any((t) =>
        t.isIncome == false &&
        t.amount <= _antThreshold &&
        !t.createdAt.isBefore(last3Days));
    final shieldOk = transactions.isNotEmpty && !hasRecentAnt;

    // 3) Pareja Responsable: 3+ movimientos de pareja este mes o cobró un split.
    final coupleOk = coupleMonthCount >= 3 || paidSplits >= 1;

    return [
      Achievement(
        id: AchievementId.survivor,
        title: 'Superviviente de Fin de Mes',
        description: 'Cerraste el mes sin superar tu presupuesto.',
        icon: 'military_tech',
        unlocked: survivors && survivorOk,
      ),
      Achievement(
        id: AchievementId.antShield,
        title: 'Escudo Anti-Antojos',
        description: '3 días sin gastos hormiga (S/ $_antThreshold o menos).',
        icon: 'shield',
        unlocked: shieldOk,
      ),
      Achievement(
        id: AchievementId.responsibleCouple,
        title: 'Pareja Responsable',
        description: 'Llevas el control de los gastos de tu pareja.',
        icon: 'favorite',
        unlocked: coupleOk,
      ),
    ];
  }
}