import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';
import '../home/providers.dart';

/// Todo lo que pinta Presupuesto, ya calculado. La UI no hace cuentas.
final budgetSummaryProvider = Provider<AsyncValue<BudgetSummary>>((ref) {
  final parts = <AsyncValue<Object?>>[
    ref.watch(settingsProvider),
    ref.watch(entriesStreamProvider),
    ref.watch(categoriesStreamProvider),
    ref.watch(budgetsStreamProvider),
  ];
  for (final p in parts) {
    if (p.hasError) return AsyncError(p.error!, p.stackTrace ?? StackTrace.current);
  }
  if (parts.any((p) => !p.hasValue)) return const AsyncLoading();
  return AsyncData(buildBudgetSummary(
    settings: ref.watch(settingsProvider).value,
    entries: ref.watch(entriesStreamProvider).value!,
    categories: ref.watch(categoriesStreamProvider).value!,
    budgets: ref.watch(budgetsStreamProvider).value!,
    today: ref.watch(todayProvider),
  ));
});

class BudgetRow {
  const BudgetRow({
    required this.categoryId,
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.spentCents,
    this.capCents,
    this.suggestedCents,
  });

  final String categoryId;
  final String name;
  final String icon;
  final String colorHex;

  /// Gastado en el mes calendario.
  final int spentCents;

  /// null = sin techo.
  final int? capCents;

  /// Techo sugerido por el historial de 90 días; null si no hay historial.
  final int? suggestedCents;

  int get percent => capCents == null ? 0 : spentCents * 100 ~/ capCents!;
  bool get over => capCents != null && spentCents > capCents!;
}

class BudgetSummary {
  const BudgetSummary({
    required this.month,
    required this.total,
    required this.uncappedSpentCents,
    required this.capped,
    required this.uncapped,
    required this.firstToDefine,
  });

  /// "Octubre".
  final String month;

  /// Σ techos de categorías activas vs todo el gasto del mes (D1, D2). null = sin techos.
  final BudgetStatus? total;

  /// Gasto del mes en categorías sin techo (o archivadas): la línea "Incluye…".
  final int uncappedSpentCents;

  /// Con techo, por % usado desc; empate por nombre.
  final List<BudgetRow> capped;

  /// Sin techo y con gasto en 90 días, por gasto del mes desc; empate por nombre.
  final List<BudgetRow> uncapped;

  /// Categoría que abre "Definir presupuestos": la de más gasto del mes, si no
  /// la de más gasto en 90 días, si no la primera activa. null sin categorías activas.
  final BudgetRow? firstToDefine;

  bool get isEmpty => capped.isEmpty;
}

BudgetSummary buildBudgetSummary({
  required Setting? settings,
  required List<Entry> entries,
  required List<Category> categories,
  required List<Budget> budgets,
  required DateTime today,
}) {
  final movements = [for (final e in entries) e.toMovement()];
  final spent = spentByCategoryInMonth(movements, today: today);
  final suggested = suggestedCaps(movements, today: today, opening: settings?.opening);
  final caps = {for (final b in budgets) b.categoryId: b.capCents};
  final active = [...categories.where((c) => !c.archived)]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  BudgetRow row(Category c) => BudgetRow(
        categoryId: c.id,
        name: c.name,
        icon: c.icon,
        colorHex: c.colorHex,
        spentCents: spent[c.id] ?? 0,
        capCents: caps[c.id],
        suggestedCents: suggested[c.id],
      );

  final capped = [for (final c in active) if (caps.containsKey(c.id)) row(c)]
    ..sort((a, b) => b.percent != a.percent ? b.percent.compareTo(a.percent) : a.name.compareTo(b.name));
  final uncapped = [for (final c in active) if (!caps.containsKey(c.id) && suggested.containsKey(c.id)) row(c)]
    ..sort((a, b) =>
        b.spentCents != a.spentCents ? b.spentCents.compareTo(a.spentCents) : a.name.compareTo(b.name));

  final spentAll = spentInMonth(movements, today: today);
  final cappedSpent = capped.fold<int>(0, (a, r) => a + r.spentCents);

  BudgetRow? first;
  if (active.isNotEmpty) {
    int byMonth(Category c) => spent[c.id] ?? 0;
    int by90(Category c) => suggested[c.id] ?? 0;
    final pick = active.reduce((a, b) => byMonth(b) > byMonth(a) ? b : a);
    final pick90 = active.reduce((a, b) => by90(b) > by90(a) ? b : a);
    first = row(byMonth(pick) > 0 ? pick : (by90(pick90) > 0 ? pick90 : active.first));
  }

  final month = DateFormat('MMMM', 'es_PE').format(DateTime(today.year, today.month));
  return BudgetSummary(
    month: '${month[0].toUpperCase()}${month.substring(1)}',
    total: budgetStatus({for (final r in capped) r.categoryId: r.capCents!}, spentCents: spentAll),
    uncappedSpentCents: spentAll - cappedSpent,
    capped: capped,
    uncapped: uncapped,
    firstToDefine: first,
  );
}
