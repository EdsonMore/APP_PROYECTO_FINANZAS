import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saldo_claro/core/models/achievement.dart';
import 'package:saldo_claro/core/models/split.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/services/achievements_service.dart';
import 'package:saldo_claro/features/couple/providers/couple_providers.dart';
import 'package:saldo_claro/features/dashboard/providers/dashboard_providers.dart';

/// Calcula los logros desbloqueados según los datos actuales del usuario.
final achievementsProvider = FutureProvider<List<Achievement>>((ref) async {
  final transactions =
      ref.watch(allTransactionsProvider).value ?? const <Transaction>[];
  final budget = ref.watch(monthlyBudgetProvider).value;
  final couple = ref.watch(coupleStatsProvider).value;
  final splits = ref.watch(splitsProvider).value ?? const <Split>[];

  return AchievementsService().compute(
    transactions: transactions,
    monthlyBudget: budget,
    coupleMonthCount: couple?.monthCount ?? 0,
    paidSplits: splits.where((s) => s.isPaid).length,
  );
});