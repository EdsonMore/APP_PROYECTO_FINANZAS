import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';

// Streams reactivos: al guardar o deshacer un movimiento, el Home se recalcula solo.
final entriesStreamProvider = StreamProvider<List<Entry>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.entries).watch();
});

final categoriesStreamProvider = StreamProvider<List<Category>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.categories).watch();
});

final sourcesStreamProvider = StreamProvider<List<Source>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.sources).watch();
});

final budgetsStreamProvider = StreamProvider<List<Budget>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.budgets).watch();
});

/// Todo lo que el Home pinta, ya calculado y formateado. La UI no hace cuentas.
final homeSummaryProvider = Provider<AsyncValue<HomeSummary>>((ref) {
  final parts = <AsyncValue<Object?>>[
    ref.watch(settingsProvider),
    ref.watch(entriesStreamProvider),
    ref.watch(categoriesStreamProvider),
    ref.watch(sourcesStreamProvider),
    ref.watch(budgetsStreamProvider),
  ];
  for (final p in parts) {
    if (p.hasError) return AsyncError(p.error!, p.stackTrace ?? StackTrace.current);
  }
  if (parts.any((p) => !p.hasValue)) return const AsyncLoading();
  return AsyncData(buildHomeSummary(
    settings: ref.watch(settingsProvider).value,
    entries: ref.watch(entriesStreamProvider).value!,
    categories: ref.watch(categoriesStreamProvider).value!,
    sources: ref.watch(sourcesStreamProvider).value!,
    budgets: ref.watch(budgetsStreamProvider).value!,
    today: ref.watch(todayProvider),
  ));
});

// ---------------------------------------------------------------------------
// Modelo de vista

enum HeadlineKind { welcome, budget, spent, runway }

class Headline {
  const Headline({
    required this.kind,
    required this.value,
    this.lead,
    this.secondary,
    this.stats = const [],
    this.budgetPercent,
    this.overBudget = false,
  });

  final HeadlineKind kind;

  /// "Te queda", "Gastaste", "Te alcanza para"; null en bienvenida.
  final String? lead;

  /// Lo que va a 52 sp: "S/ 640.00", "~23 días", "Empecemos", "Sin colchón".
  final String value;
  final String? secondary;

  /// Variable: "Ingreso típico 30d" / "Gasto 30d" con su monto.
  final List<({String label, String amount})> stats;

  /// Solo [HeadlineKind.budget]: 0..∞ (puede pasar de 100).
  final int? budgetPercent;
  final bool overBudget;

  /// Lo que lee el lector de pantalla: una sola frase.
  String get semantics => [lead, value.replaceFirst('~', 'unos '), secondary].whereType<String>().join(' ');
}

class LightView {
  const LightView(this.light, this.text, this.amounts);
  final Light light;
  final String text;

  /// "Entró S/ X · Salió S/ Y"
  final String amounts;
}

class TopRow {
  const TopRow({required this.icon, required this.name, required this.amount, required this.fraction});
  final String icon;
  final String name;
  final String amount;

  /// Ancho de la mini barra relativo a la primera (1.0).
  final double fraction;
}

class RecentRow {
  const RecentRow({
    required this.id,
    required this.icon,
    required this.name,
    required this.subtitle,
    required this.amount,
    required this.isIncome,
    required this.isAuto,
  });
  final String id;
  final String icon;
  final String name;
  final String subtitle;

  /// "+ S/ 80.00" / "− S/ 12.00" (signo menos tipográfico).
  final String amount;
  final bool isIncome;
  final bool isAuto;
}

class HomeSummary {
  const HomeSummary({
    required this.title,
    required this.mode,
    required this.headline,
    required this.light,
    required this.top,
    required this.recents,
  });

  final String title;
  final Mode mode;
  final Headline headline;
  final LightView light;
  final List<TopRow> top;
  final List<RecentRow> recents;
}

// ---------------------------------------------------------------------------
// Armado: solo llama a metrics.dart y Formatters.

const lightTexts = {
  Light.none: 'Aún sin movimientos',
  Light.green: 'Entra más que sale',
  Light.amber: 'Sale un poco más',
  Light.red: 'Sale más que entra',
};

const defaultSpaceName = 'Mis cuentas';

HomeSummary buildHomeSummary({
  required Setting? settings,
  required List<Entry> entries,
  required List<Category> categories,
  required List<Source> sources,
  required List<Budget> budgets,
  required DateTime today,
}) {
  final mode = settings?.mode ?? Mode.variable;
  final opening = settings?.opening;
  final movements = [for (final e in entries) e.toMovement()];
  final catById = {for (final c in categories) c.id: c};
  final srcById = {for (final s in sources) s.id: s};

  final ratio = entryExitRatio(movements, today: today, opening: opening);

  return HomeSummary(
    title: settings?.spaceName ?? defaultSpaceName,
    mode: mode,
    headline: _headline(mode, settings, movements, budgets, today),
    light: LightView(
      ratio.light,
      lightTexts[ratio.light]!,
      'Entró ${Formatters.soles(ratio.incomeCents)} · Salió ${Formatters.soles(ratio.expenseCents)}',
    ),
    top: _top(movements, catById, today),
    recents: _recents(movements, entries, catById, srcById, today),
  );
}

Headline _headline(Mode mode, Setting? settings, List<Movement> movements, List<Budget> budgets, DateTime today) {
  final opening = settings?.opening;
  if (movements.isEmpty && opening == null) {
    return const Headline(
      kind: HeadlineKind.welcome,
      value: 'Empecemos',
      secondary: 'Registra lo que gastas o lo que entra. Con eso te digo cuánto te alcanza.',
    );
  }

  final window = settings?.runwayWindowDays ?? 14;
  final r = runway(movements, today: today, window: window, opening: opening);
  final month = DateFormat('MMMM', 'es_PE').format(DateTime(today.year, today.month));

  if (mode == Mode.stable) {
    final spent = spentInMonth(movements, today: today);
    final b = budgetStatus({for (final x in budgets) x.categoryId: x.capCents}, spentCents: spent);
    // SPEC: nunca "presupuesto restante" sin ingreso registrado en el mes.
    if (b != null && incomeInMonth(movements, today: today) > 0) {
      final over = b.remainingCents < 0;
      return Headline(
        kind: HeadlineKind.budget,
        lead: over ? 'Te pasaste por' : 'Te queda',
        value: Formatters.soles(b.remainingCents.abs()),
        secondary: 'del presupuesto de $month',
        budgetPercent: b.percent,
        overBudget: over,
      );
    }
    final clause = switch (r.status) {
      RunwayStatus.days => ' Te alcanza para ${_days(r)}.',
      RunwayStatus.noCushion => ' Sin colchón por ahora.',
      _ => '',
    };
    return Headline(
      kind: HeadlineKind.spent,
      lead: 'Gastaste',
      value: Formatters.soles(spent),
      secondary: 'en $month.$clause',
    );
  }

  // Variable (incluye Mixto) y Supervivencia: el runway manda.
  switch (r.status) {
    case RunwayStatus.noCushion:
      return const Headline(
          kind: HeadlineKind.runway, value: 'Sin colchón', secondary: 'Registraste más gastos que ingresos.');
    case RunwayStatus.noSpending:
    case RunwayStatus.empty:
      return Headline(
        kind: HeadlineKind.runway,
        value: 'Sin gastos',
        secondary: 'En los últimos $window días. Registra uno y calculo cuánto te alcanza.',
      );
    case RunwayStatus.days:
      final estimated = r.estimated ? ' Estimado con pocos días de datos.' : '';
      if (mode == Mode.survival) {
        final perDay = avgDailyExpense(movements, today: today, window: window, opening: opening).round();
        return Headline(
          kind: HeadlineKind.runway,
          lead: 'Te alcanza para',
          value: _days(r),
          secondary: 'Gastas ~${Formatters.soles(perDay)} al día.$estimated',
        );
      }
      return Headline(
        kind: HeadlineKind.runway,
        lead: 'Te alcanza para',
        value: _days(r),
        secondary: r.estimated ? estimated.trim() : null,
        stats: [
          (label: 'Ingreso típico 30d', amount: Formatters.soles(avgIncome30(movements, today: today, opening: opening))),
          (label: 'Gasto 30d', amount: Formatters.soles(avgExpense30(movements, today: today, opening: opening))),
        ],
      );
  }
}

String _days(Runway r) => r.capped ? '+$maxRunwayDays días' : '~${r.days} ${r.days == 1 ? 'día' : 'días'}';

List<TopRow> _top(List<Movement> movements, Map<String, Category> catById, DateTime today) {
  final top = topCategories(movements, today: today);
  if (top.isEmpty) return const [];
  final max = top.first.cents;
  return [
    for (final t in top)
      TopRow(
        icon: catById[t.categoryId]?.icon ?? '',
        name: catById[t.categoryId]?.name ?? 'Sin categoría',
        amount: Formatters.soles(t.cents),
        fraction: t.cents / max,
      ),
  ];
}

List<RecentRow> _recents(List<Movement> movements, List<Entry> entries, Map<String, Category> catById,
    Map<String, Source> srcById, DateTime today) {
  final byId = {for (final e in entries) e.id: e};
  return [
    for (final m in recentMovements(movements, today: today))
      if (byId[m.id] case final e?) _recentRow(e, catById, srcById, today),
  ];
}

RecentRow _recentRow(Entry e, Map<String, Category> catById, Map<String, Source> srcById, DateTime today) {
  final income = e.kind == EntryKind.income;
  final pick = income ? srcById[e.sourceId] : null;
  final cat = income ? null : catById[e.categoryId];
  final day = parseIsoDay(e.occurredOn);
  final note = e.note?.trim();
  return RecentRow(
    id: e.id,
    icon: (income ? pick?.icon : cat?.icon) ?? '',
    name: (income ? pick?.name : cat?.name) ?? (income ? 'Ingreso' : 'Gasto'),
    subtitle: note == null || note.isEmpty ? shortDay(day, today) : '${shortDay(day, today)} · $note',
    amount: '${income ? '+' : '−'} ${Formatters.soles(e.amountCents)}',
    isIncome: income,
    isAuto: e.origin == Origin.auto,
  );
}

/// "hoy", "ayer" o "6 oct".
String shortDay(DateTime d, DateTime today) {
  if (d == today) return 'hoy';
  if (d == today.subtract(const Duration(days: 1))) return 'ayer';
  return DateFormat('d MMM', 'es_PE').format(DateTime(d.year, d.month, d.day));
}
