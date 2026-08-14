import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saldo_claro/core/models/category.dart';
import 'package:saldo_claro/core/models/couple.dart';
import 'package:saldo_claro/core/models/split.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/features/dashboard/providers/dashboard_providers.dart';

/// Estadísticas del módulo "Especial Pareja" calculadas en tiempo real.
final coupleStatsProvider = FutureProvider<CoupleStats>((ref) async {
  final transactions =
      ref.watch(allTransactionsProvider).value ?? const <Transaction>[];
  final categories = ref.watch(allCategoriesProvider).value ?? const <Category>[];
  final splits = ref.watch(splitsProvider).value ?? const <Split>[];

  // Localiza la categoría del usuario cuyo nombre remita a la pareja.
  const keywords = ['enamorad', 'pareja'];
  Category? target;
  for (final c in categories) {
    final lower = c.name.toLowerCase();
    if (keywords.any((k) => lower.contains(k))) {
      target = c;
      break;
    }
  }

  final empty = CoupleStats(
    categoryName: '',
    monthTotal: 0,
    monthCount: 0,
    pendingSplits: 0,
    breakdown: const {},
    transactions: const [],
  );
  if (target == null) return empty;

  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);

  final coupleTxs = transactions.where((t) {
    if (t.isIncome) return false;
    if (t.categoryId != null && t.categoryId == target!.id) return true;
    final merchant = (t.merchantOrPerson ?? '').toLowerCase();
    return target!.keywords.any((kw) => merchant.contains(kw.toLowerCase()));
  }).toList();

  final monthTxs =
      coupleTxs.where((t) => !t.createdAt.isBefore(monthStart)).toList();

  final monthTotal = monthTxs.fold(0.0, (s, t) => s + t.amount);

  final breakdown = <CoupleSubcategory, double>{};
  for (final t in monthTxs) {
    final sub = CoupleSubcategory.classify(t);
    breakdown[sub] = (breakdown[sub] ?? 0) + t.amount;
  }

  final pendingSplits =
      splits.where((s) => !s.isPaid).fold(0.0, (s, x) => s + x.amount);

  return CoupleStats(
    categoryName: target.name,
    budget: target.budget,
    monthTotal: monthTotal,
    monthCount: monthTxs.length,
    pendingSplits: pendingSplits,
    breakdown: breakdown,
    transactions: monthTxs,
  );
});

/// Invalida los providers del módulo pareja.
void refreshCouple(WidgetRef ref) {
  ref.invalidate(coupleStatsProvider);
  ref.invalidate(splitsProvider);
}