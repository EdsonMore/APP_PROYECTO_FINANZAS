import 'dart:convert';
import 'dart:developer' as developer;

import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/services/ai_service.dart';

/// Insight calculado por el motor de análisis.
class Insight {
  const Insight({
    required this.type,
    required this.title,
    required this.message,
    this.categoryName,
    this.amount,
    this.icon,
  });

  final String type; // 'ant' | 'projection' | 'couple'
  final String title;
  final String message;
  final String? categoryName;
  final double? amount;
  final String? icon;

  String get iconName => icon ?? _defaultIconFor(type);

  static String _defaultIconFor(String type) => switch (type) {
        'ant' => 'bug_report',
        'projection' => 'insights',
        'couple' => 'favorite',
        'ai' => 'auto_awesome',
        _ => 'lightbulb',
      };
}

/// Proyección de gasto.
class SpendingProjection {
  const SpendingProjection({
    required this.weeklyProjected,
    required this.monthlyProjected,
    required this.thisWeek,
    required this.thisMonth,
    required this.growthRate,
  });

  final double weeklyProjected;
  final double monthlyProjected;
  final double thisWeek;
  final double thisMonth;

  /// Tasa de variación vs. semana anterior (0 si no hay datos).
  final double growthRate;
}

/// Motor de análisis y predicción (local + IA opcional).
class InsightsEngine {
  InsightsEngine({AIService? ai}) : _ai = ai;

  /// Orquestador de IA (Gemini -> Groq -> local). Si es null (o no disponible),
  /// los insights funcionan 100% con reglas locales sin llamar a la API.
  final AIService? _ai;

  /// Cache de TTL para el insight de IA: evita gastar cuota en cada recarga
  /// del dashboard cuando los datos no cambiaron.
  static _AiInsightCacheEntry? _aiInsightCache;

  /// Genera (o reutiliza) un insight de IA único y coherente con el mes actual.
  ///
  /// Reglas de uso responsable de la IA:
  ///  - Solo si hay un proveedor configurado ([AIService.available]).
  ///  - Solo si hay suficientes movimientos del mes (mínimo configurable).
  ///  - Se reutiliza el resultado durante [AppConfig.aiInsightCacheDuration].
  ///  - Ante cualquier error se devuelve null (los insights locales siguen).
  Future<Insight?> generateAiInsight(List<Transaction> transactions) async {
    final ai = _ai;
    if (ai == null || !ai.available) return null;

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final monthTx =
        transactions.where((t) => !t.createdAt.isBefore(monthStart)).toList();
    if (monthTx.length < AppConfig.aiInsightMinTransactions) return null;

    final fingerprint = _insightFingerprint(monthTx);

    final cached = _aiInsightCache;
    if (cached != null &&
        cached.fingerprint == fingerprint &&
        now.difference(cached.cachedAt) < AppConfig.aiInsightCacheDuration) {
      return cached.insight;
    }

    try {
      final result = await ai.generateJson<Map<String, dynamic>>(
        prompt: _aiInsightPrompt(monthTx),
        fromJson: (json) => json,
      );
      if (result == null) return null;

      final title = (result['title'] as String?)?.trim();
      final message = (result['message'] as String?)?.trim();
      if (title == null || title.isEmpty || message == null || message.isEmpty) {
        return null;
      }

      final insight = Insight(
        type: 'ai',
        title: title,
        message: message,
        icon: 'auto_awesome',
      );
      _aiInsightCache = _AiInsightCacheEntry(
        insight: insight,
        fingerprint: fingerprint,
        cachedAt: DateTime.now(),
      );
      return insight;
    } catch (e, st) {
      developer.log(
        '[SaldoClaro] Insight de IA falló, usando solo reglas locales',
        name: 'SaldoClaro.Insights',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Huella de datos del mes: si no cambia, el insight cacheado sigue vigente.
  static String _insightFingerprint(List<Transaction> monthTx) {
    final total = monthTx.fold<double>(
        0, (sum, t) => sum + (t.isIncome ? t.amount : -t.amount));
    return '${monthTx.length}|${total.toStringAsFixed(2)}';
  }

  /// Prompt con contexto anónimo y compacto (solo cifras agregadas del mes).
  static String _aiInsightPrompt(List<Transaction> monthTx) {
    var income = 0.0;
    var expense = 0.0;
    final byCategory = <String, double>{};
    final byMerchant = <String, double>{};

    for (final t in monthTx) {
      if (t.isIncome) {
        income += t.amount;
      } else {
        expense += t.amount;
        byMerchant[t.merchantOrPerson ?? 'Sin nombre'] =
            (byMerchant[t.merchantOrPerson ?? 'Sin nombre'] ?? 0) + t.amount;
      }
      final key = t.categoryName ?? 'Sin categoría';
      byCategory[key] = (byCategory[key] ?? 0) + t.amount;
    }

    final topMerchants = byMerchant.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topCategories = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final context = <String, dynamic>{
      'movimientos_del_mes': monthTx.length,
      'ingresos_del_mes': income,
      'gastos_del_mes': expense,
      'saldo_neto_del_mes': income - expense,
      'top_comercios': topMerchants
          .take(5)
          .map((e) => {'nombre': e.key, 'total': e.value})
          .toList(),
      'top_categorias': topCategories
          .take(5)
          .map((e) => {'nombre': e.key, 'total': e.value})
          .toList(),
    };

    return '''
Eres el analista financiero de SaldoClaro (finanzas personales del Perú, soles S/).
Este es el resumen anónimo del mes del usuario (JSON):
${jsonEncode(context)}

Identifica UNA observación valiosa y accionable a partir de estas cifras.
Devuelve SOLO un objeto JSON con:
{"title": "título corto de máximo 6 palabras",
 "message": "2-3 líneas en español con una recomendación concreta"}

Reglas:
- No inventes cifras que no estén en el JSON.
- Usa montos en soles (S/).
- Si no hay nada realmente valioso que decir, devuelve {"title": "", "message": ""}.
''';
  }

  /// Alerta semanal de "gasto hormiga" (para el banner del dashboard).
  WeeklyAntAlert detectWeeklyAnt(List<Transaction> transactions) {
    const threshold = AppConfig.antRecordExpenseThreshold; // S/ 15

    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    final ants = transactions
        .where((t) =>
            t.isIncome == false &&
            t.amount <= threshold &&
            !t.createdAt.isBefore(weekStart))
        .toList();

    if (ants.isEmpty) return WeeklyAntAlert(count: 0, total: 0, recurring: const []);

    final total = ants.fold(0.0, (sum, t) => sum + t.amount);

    final byMerchant = <String, int>{};
    for (final a in ants) {
      final k = (a.merchantOrPerson ?? 'sin nombre').toLowerCase();
      byMerchant[k] = (byMerchant[k] ?? 0) + 1;
    }
    final recurring = byMerchant.entries
        .where((e) => e.value >= 2)
        .map((e) => e.key)
        .take(3)
        .toList();

    return WeeklyAntAlert(count: ants.length, total: total, recurring: recurring);
  }

  /// Detección global de "gastos hormiga" (para insights/resúmenes).
  List<Insight> detectAntExpenses(List<Transaction> transactions) {
    const threshold = AppConfig.antRecordExpenseThreshold; // p. ej. S/15

    final ants = transactions
        .where((t) => t.isIncome == false && t.amount <= threshold)
        .toList();

    if (ants.isEmpty) return const [];

    final total = ants.fold(0.0, (sum, t) => sum + t.amount);
    final count = ants.length;

    // Detecta si es recurrente (mismo comercio >= 3 veces).
    final byMerchant = <String, int>{};
    for (final a in ants) {
      final k = (a.merchantOrPerson ?? 'sin nombre').toLowerCase();
      byMerchant[k] = (byMerchant[k] ?? 0) + 1;
    }
    final recurring = byMerchant.entries
        .where((e) => e.value >= 3)
        .map((e) => e.key)
        .take(3)
        .toList();

    final msg = StringBuffer()
      ..write('Tienes $count gastos de S/ $threshold o menos (total S/ '
          '${total.toStringAsFixed(2)}). ');
    if (recurring.isNotEmpty) {
      msg.write('Repetidos: ${recurring.join(', ')}.');
    } else {
      msg.write('¡Cuidado con los antojos imperceptibles!');
    }

    return [
      Insight(
        type: 'ant',
        title: '🐜 Gasto hormiga detectado',
        message: msg.toString(),
        amount: total,
        icon: 'bug_report',
      ),
    ];
  }

  /// Alerta de ritmo de gasto: si ya se gastó más del 70% del presupuesto
  /// antes de la mitad del mes, se advierte al usuario.
  Insight? paceAlert(List<Transaction> transactions, double? monthlyBudget) {
    if (monthlyBudget == null || monthlyBudget <= 0) return null;

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);

    final spent = transactions
        .where((t) => t.isIncome == false && !t.createdAt.isBefore(monthStart))
        .fold(0.0, (sum, t) => sum + t.amount);

    final ratio = spent / monthlyBudget;
    final pastHalf = now.day > 15;

    if (pastHalf && ratio < 0.7) return null; // vas bien
    if (!pastHalf && ratio > 0.7) {
      return Insight(
        type: 'pace',
        title: '🚦 Alerta de ritmo de gasto',
        message:
            'Llevas gastado S/ ${spent.toStringAsFixed(0)} (${(ratio * 100).round()}% '
            'de tu presupuesto) y aún no llega la mitad del mes. '
            'Si sigues así superarás tu meta de S/ ${monthlyBudget.toStringAsFixed(0)}.',
        amount: spent,
        icon: 'speed',
      );
    }
    return null;
  }

  /// Movimientos de la semana actual (para el banner de gasto hormiga).
  List<Transaction> thisWeekExpenses(List<Transaction> transactions) {
    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    return transactions
        .where((t) => t.isIncome == false && !t.createdAt.isBefore(weekStart))
        .toList();
  }

  /// Proyección de gasto semanal/mensual basada en el histórico.
  SpendingProjection projectSpending(List<Transaction> transactions) {
    final expenses =
        transactions.where((t) => t.isIncome == false).toList();
    if (expenses.isEmpty) {
      return SpendingProjection(
        weeklyProjected: 0,
        monthlyProjected: 0,
        thisWeek: 0,
        thisMonth: 0,
        growthRate: 0,
      );
    }

    final now = DateTime.now();
    final weekStart = now.subtract(Duration(days: now.weekday - 1));
    final monthStart = DateTime(now.year, now.month, 1);

    final thisWeek =
        expenses.where((t) => !t.createdAt.isBefore(weekStart)).fold(0.0, (s, t) => s + t.amount);
    final thisMonth =
        expenses.where((t) => !t.createdAt.isBefore(monthStart)).fold(0.0, (s, t) => s + t.amount);

    // Gasto promedio diario en el mes -> proyección del mes.
    final daysElapsed = DateTime(now.year, now.month, now.day)
        .difference(monthStart)
        .inDays + 1;
    final dailyAvg = daysElapsed > 0 ? thisMonth / daysElapsed : 0.0;
    final daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    final monthlyProjected = dailyAvg * daysInMonth;

    // Proyección semanal: promedio por día transcurrido de la semana * 7.
    final daysInWeek = ((now.difference(weekStart).inDays) + 1).toDouble();
    final weeklyProjected = daysInWeek > 0 ? (thisWeek / daysInWeek) * 7 : 0.0;

    // Crecimiento vs. semana anterior.
    final prevWeekStart = weekStart.subtract(const Duration(days: 7));
    final prevWeek = expenses
        .where((t) =>
            !t.createdAt.isBefore(prevWeekStart) && t.createdAt.isBefore(weekStart))
        .fold(0.0, (s, t) => s + t.amount);
    final growthRate =
        prevWeek > 0 ? ((thisWeek - prevWeek) / prevWeek) : 0.0;

    return SpendingProjection(
      weeklyProjected: weeklyProjected,
      monthlyProjected: monthlyProjected,
      thisWeek: thisWeek,
      thisMonth: thisMonth,
      growthRate: growthRate,
    );
  }

  /// Módulo estadístico "Especial Pareja": total gastado en la categoría
  /// que contenga 'enamorada' o 'pareja' (configurable por nombre).
  (double total, int count, String categoryName) coupleModule(
    List<Transaction> transactions,
    List<String> categoryNames,
  ) {
    const coupleKeywords = ['enamorad', 'pareja'];

    String? targetName;
    for (final kw in coupleKeywords) {
      for (final name in categoryNames) {
        if (name.toLowerCase().contains(kw)) {
          targetName = name;
          break;
        }
      }
      if (targetName != null) break;
    }

    if (targetName == null) {
      return (0, 0, '');
    }

    double total = 0;
    var count = 0;
    for (final t in transactions) {
      if (t.isIncome) continue;
      if (_matchesCategory(t, categoryNames, targetName)) {
        total += t.amount;
        count++;
      }
    }
    return (total, count, targetName);
  }

  bool _matchesCategory(
      Transaction t, List<String> categoryNames, String targetName) {
    // Nota: aquí se asume que el categorizador ya asignó categoryName en el
    // transaction. Para simplificar, usamos el merchant si coincide con
    // keywords de la categoría objetivo.
    final merchant = (t.merchantOrPerson ?? '').toLowerCase();
    final target = targetName.toLowerCase();
    for (final kw in ['cine', 'cinemark', 'cineplanet', 'restaurante', 'flores', 'regalo', 'gift']) {
      if (merchant.contains(kw)) return true;
    }
    return merchant.contains(target.split(' ').first);
  }

  /// Compone todos los insights para el dashboard.
  List<Insight> buildInsights(
    List<Transaction> transactions,
    List<String> categoryNames, {
    double? monthlyBudget,
  }) {
    final insights = <Insight>[];

    // --- Banner semanal de gasto hormiga (F4) ---
    final weekly = detectWeeklyAnt(transactions);
    if (weekly.hasAnts) {
      final msg = StringBuffer()
        ..write(
            'Llevas ${weekly.count} yapes/gastos pequeños esta semana '
            '(S/ ${weekly.total.toStringAsFixed(2)}).');
      if (weekly.recurring.isNotEmpty) {
        msg.write(' Repetidos: ${weekly.recurring.join(', ')}.');
      } else {
        msg.write(' ¡Atención al gasto hormiga!');
      }
      insights.add(Insight(
        type: 'ant',
        title: '🐜 Atención al gasto hormiga',
        message: msg.toString(),
        amount: weekly.total,
        icon: 'bug_report',
      ));
    }

    // --- Alerta de ritmo de gasto (F4) ---
    final pace = paceAlert(transactions, monthlyBudget);
    if (pace != null) insights.add(pace);

    // --- Proyección de gasto ---
    final projection = projectSpending(transactions);
    if (projection.thisMonth > 0) {
      final growth = projection.growthRate;
      final growthMsg = growth > 0.1
          ? '⚠️ Un ${(growth * 100).toStringAsFixed(0)}% más que la semana pasada.'
          : growth < -0.1
              ? '✅ Bajaste ${((growth.abs()) * 100).toStringAsFixed(0)}% vs. la semana pasada.'
              : 'Estable respecto a la semana pasada.';
      insights.add(Insight(
        type: 'projection',
        title: '📈 Proyección de gasto',
        message:
            'Si sigues así, gastarás ~S/ ${projection.monthlyProjected.toStringAsFixed(0)} '
            'este mes (S/ ${projection.weeklyProjected.toStringAsFixed(0)} esta semana). $growthMsg',
        amount: projection.monthlyProjected,
        icon: 'insights',
      ));
    }

    // --- Módulo "Especial Pareja" ---
    final (total, count, name) = coupleModule(transactions, categoryNames);
    if (name.isNotEmpty && count > 0) {
      insights.add(Insight(
        type: 'couple',
        title: '💕 Especial Pareja',
        message:
            'Has gastado S/ ${total.toStringAsFixed(2)} en "$name" en $count movimiento(s). ¡Qué detalle!',
        amount: total,
        categoryName: name,
        icon: 'favorite',
      ));
    }

    return insights;
  }
}

/// Alerta semanal de gastos hormiga (para el banner del dashboard).
class WeeklyAntAlert {
  const WeeklyAntAlert({
    required this.count,
    required this.total,
    required this.recurring,
  });

  final int count;
  final double total;
  final List<String> recurring;

  bool get hasAnts => count > 0;
}

/// Entrada del cache de insights de IA (resultado + vigencia).
class _AiInsightCacheEntry {
  const _AiInsightCacheEntry({
    required this.insight,
    required this.fingerprint,
    required this.cachedAt,
  });

  final Insight insight;
  final String fingerprint;
  final DateTime cachedAt;
}
