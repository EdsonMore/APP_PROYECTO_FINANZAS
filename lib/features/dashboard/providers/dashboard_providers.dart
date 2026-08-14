import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saldo_claro/core/models/account.dart';
import 'package:saldo_claro/core/models/category.dart';
import 'package:saldo_claro/core/models/split.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/providers/service_providers.dart';
import 'package:saldo_claro/core/services/insights_engine.dart';
import 'package:saldo_claro/features/billing_cycles/providers/billing_cycles_provider.dart';
import 'package:saldo_claro/features/dashboard/providers/repository_providers.dart';

/// Lista de cuentas del usuario.
final accountsProvider = FutureProvider<List<Account>>((ref) {
  return ref.watch(accountRepositoryProvider).fetchAll();
});

/// Transacciones recientes del usuario.
final recentTransactionsProvider = FutureProvider<List<Transaction>>((ref) {
  return ref.watch(transactionRepositoryProvider).fetchRecent();
});

/// Todas las transacciones (para el motor de insights/proyecciones).
final allTransactionsProvider = FutureProvider<List<Transaction>>((ref) {
  return ref.watch(transactionRepositoryProvider).fetchAll();
});

/// Gastos agrupados por categoría (para el gráfico).
final expensesByCategoryProvider = FutureProvider<Map<String, double>>((ref) {
  return ref.watch(transactionRepositoryProvider).expensesByCategory();
});

/// Nombre de las categorías (para el módulo "Especial Pareja").
final allCategoriesProvider = FutureProvider<List<Category>>((ref) {
  return ref.watch(categoryRepositoryProvider).fetchAll();
});

/// Presupuesto mensual global del usuario (para la alerta de ritmo).
final monthlyBudgetProvider = FutureProvider<double?>((ref) {
  return ref.watch(settingsRepositoryProvider).fetchMonthlyBudget();
});

/// Splits (cuentas por cobrar) del usuario.
final splitsProvider = FutureProvider<List<Split>>((ref) {
  return ref.watch(splitRepositoryProvider).fetchAll();
});

/// Insights de IA calculados a partir del histórico de transacciones.
final insightsProvider = FutureProvider<List<Insight>>((ref) async {
  final transactions =
      ref.watch(allTransactionsProvider).value ?? const <Transaction>[];
  final categories = ref.watch(allCategoriesProvider).value ?? const <Category>[];
  final names = categories.map((c) => c.name).toList();
  final budget = ref.watch(monthlyBudgetProvider).value;
  return InsightsEngine().buildInsights(transactions, names, monthlyBudget: budget);
});

/// Insight único generado por IA sobre el mes actual (progresivo: los
/// [insightsProvider] locales se muestran al instante y este llega después).
///
/// Es seguro para la cuota: solo se llama con datos suficientes, con TTL y se
/// degrada a null ante cualquier error.
final aiInsightProvider = FutureProvider<Insight?>((ref) async {
  final transactions =
      ref.watch(allTransactionsProvider).value ?? const <Transaction>[];
  if (transactions.isEmpty) return null;
  return InsightsEngine(ai: ref.watch(aiServiceProvider))
      .generateAiInsight(transactions);
});

/// Invalida los providers del dashboard para forzar una recarga.
void refreshDashboard(WidgetRef ref) {
  ref.invalidate(accountsProvider);
  ref.invalidate(recentTransactionsProvider);
  ref.invalidate(allTransactionsProvider);
  ref.invalidate(expensesByCategoryProvider);
  ref.invalidate(allCategoriesProvider);
  ref.invalidate(insightsProvider);
  ref.invalidate(aiInsightProvider);
  ref.invalidate(monthlyBudgetProvider);
  ref.invalidate(splitsProvider);
  refreshBillingCycles(ref);
}
