import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/formatters.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/insights.dart';
import '../../domain/metrics.dart';
import '../accounts/providers.dart';
import '../budget/providers.dart';
import '../home/providers.dart';
import 'reading.dart';

/// Todo lo que pinta Insights, con los bloques ya ordenados por modo.
final insightsSummaryProvider = Provider<AsyncValue<InsightsSummary>>((ref) {
  return combineAsync([
    ref.watch(settingsProvider),
    ref.watch(entriesStreamProvider),
    ref.watch(categoriesStreamProvider),
    ref.watch(budgetsStreamProvider),
    ref.watch(accountsStreamProvider),
    ref.watch(transfersStreamProvider),
  ], () => buildInsightsSummary(
    settings: ref.watch(settingsProvider).value,
    entries: ref.watch(entriesStreamProvider).value!,
    categories: ref.watch(categoriesStreamProvider).value!,
    budgets: ref.watch(budgetsStreamProvider).value!,
    today: ref.watch(todayProvider),
    accounts: ref.watch(accountsStreamProvider).value!,
    transfers: ref.watch(transfersStreamProvider).value!,
  ));
});

// ---------------------------------------------------------------------------
// Modelo de vista: un tipo por bloque de la ficha.

sealed class InsightBlock {
  const InsightBlock();
}

/// Estable. [summary] sin techos (`total == null`) → enlace "Definir presupuestos".
class BudgetBlock extends InsightBlock {
  const BudgetBlock(this.summary);
  final BudgetSummary summary;
}

class SpendRow {
  const SpendRow({required this.name, required this.colorHex, required this.cents, required this.percent, required this.fraction});
  final String name;
  final String colorHex;
  final int cents;
  final int percent;

  /// Largo de la barra relativo a la fila mayor (1.0).
  final double fraction;
}

/// "En qué se fue": hasta 5 filas + "Otros" (piedra) al final.
class SpendBlock extends InsightBlock {
  const SpendBlock(this.rows);
  final List<SpendRow> rows;
}

class StreakBlock extends InsightBlock {
  const StreakBlock({required this.days, required this.thresholdCents});
  final int days;
  final int thresholdCents;
}

typedef MonthIncome = ({DateTime month, int cents});

/// [best] null = menos de 2 meses cerrados (texto de espera); [worst] null = todos empatan.
class MonthsBlock extends InsightBlock {
  const MonthsBlock({this.best, this.worst});
  final MonthIncome? best;
  final MonthIncome? worst;
}

/// Variable: los mismos números que el Home (I2).
class FlowBlock extends InsightBlock {
  const FlowBlock({required this.incomeCents, required this.expenseCents});
  final int incomeCents;
  final int expenseCents;
  int get diffCents => incomeCents - expenseCents;
}

/// [series] con menos de 7 puntos → texto de espera. [tall] en Supervivencia.
class RunwayBlock extends InsightBlock {
  const RunwayBlock({required this.series, required this.today, required this.tall});
  final List<int?> series;
  final Runway today;
  final bool tall;
}

class SuggestedRow {
  const SuggestedRow({required this.categoryId, required this.name, required this.icon, required this.cents});
  final String categoryId;
  final String name;
  final String icon;
  final int cents;
}

/// Supervivencia: hasta 3 techos sugeridos de categorías activas sin techo.
class SuggestedBlock extends InsightBlock {
  const SuggestedBlock(this.rows);
  final List<SuggestedRow> rows;
}

/// "Por cuenta" (4A): saldo y, de los últimos 30 días, lo que salió y entró
/// (gastos e ingresos de la cuenta; las transferencias no cuentan).
typedef AccountFlowRow = ({String name, int balance, int outCents, int inCents});

/// "Lectura del mes" (5AB): hasta 4 frases del motor de hechos.
class ReadingBlock extends InsightBlock {
  const ReadingBlock(this.lines);
  final List<String> lines;
}

class ByAccountBlock extends InsightBlock {
  const ByAccountBlock(this.rows);
  final List<AccountFlowRow> rows;
}

class InsightsSummary {
  const InsightsSummary({required this.mode, required this.phrase, required this.blocks});
  final Mode mode;
  final String phrase;
  final List<InsightBlock> blocks;
}

// ---------------------------------------------------------------------------
// Armado

const emptyPhrase = 'Registra unos días más y aquí verás tu patrón.';
const noCushionPhrase = 'Sin reserva por ahora.';
const quietPhrase = 'Sin movimientos en los últimos 30 días.';
const minRunwayPoints = 7;

InsightsSummary buildInsightsSummary({
  required Setting? settings,
  required List<Entry> entries,
  required List<Category> categories,
  required List<Budget> budgets,
  required DateTime today,
  List<Account> accounts = const [],
  List<TransferRow> transfers = const [],
}) {
  final mode = settings?.mode ?? Mode.variable;
  final book = accountBookOf(accounts, transfers);
  final opening = settings?.opening;
  final window = settings?.runwayWindowDays ?? 14;
  final movements = [for (final e in entries) e.toMovement()];
  final catById = {for (final c in categories) c.id: c};
  final activeCaps = {
    for (final b in budgets)
      if (catById[b.categoryId]?.archived == false) b.categoryId: b.capCents,
  };
  final hasData = firstDay(movements, today: today, opening: opening) != null;

  // Un umbral de 0 (sin ingreso ni gasto reciente) haría decir "menos de S/ 0.00": sin umbral útil, sin racha.
  final raw = streakThreshold(movements, today: today, mode: mode, capsCents: activeCaps, opening: opening);
  final threshold = raw != null && raw > 0 ? raw : null;
  final streakDays = threshold == null ? 0 : streak(movements, today: today, thresholdCents: threshold);
  final streakB = threshold == null ? null : StreakBlock(days: streakDays, thresholdCents: threshold);

  final spend = _spend(movements, catById, today);
  final months = incomeByClosedMonth(movements, today: today);
  // Sin ningún mes con ingreso no hay nada que comparar (se oculta); si todos
  // empatan, "peor" repetiría a "mejor" y se muestra solo el mejor.
  final best = months.length < 2 ? null : months.reduce((a, b) => b.cents >= a.cents ? b : a);
  final worst = months.length < 2 ? null : months.reduce((a, b) => b.cents < a.cents ? b : a);
  final monthsB = switch (best) {
    null => const MonthsBlock(),
    _ when best.cents == 0 => null,
    _ => MonthsBlock(best: best, worst: worst!.cents == best.cents ? null : worst),
  };
  final series = runwaySeries(movements, today: today, window: window, opening: opening, book: book);
  final todayRunway = runway(movements, today: today, window: window, opening: opening, book: book);
  final runwayB = RunwayBlock(series: series, today: todayRunway, tall: mode == Mode.survival);
  final flow = FlowBlock(
    incomeCents: avgIncome30(movements, today: today, opening: opening),
    expenseCents: avgExpense30(movements, today: today, opening: opening),
  );

  final phrase = switch (mode) {
    Mode.stable => _first([
        () => _budgetPhrase(activeCaps, movements, today),
        () => _sharePhrase(spend),
        () => _streakPhrase(streakDays),
      ], hasData: hasData, today: todayRunway),
    Mode.variable => _first([
        // V1 necesita un ingreso típico; sin él, V2 dice lo que hubo.
        () => flow.incomeCents > 0 ? _flowPhrase(flow) : null,
        // Montos reales de los últimos 30 días (los del semáforo del Home), no "cada 30 días".
        () {
          final r = entryExitRatio(movements, today: today, opening: opening);
          return r.expenseCents > 0
              ? 'En 30 días entró ${Formatters.soles(r.incomeCents)} y salió ${Formatters.soles(r.expenseCents)}.'
              : null;
        },
        () => monthsB?.best == null
            ? null
            : 'Tu mejor mes fue ${Formatters.month(monthsB!.best!.month).toLowerCase()}, con ${Formatters.soles(monthsB.best!.cents)}.',
      ], hasData: hasData, today: todayRunway),
    Mode.survival => _first([
        () => todayRunway.status == RunwayStatus.days ? 'A este ritmo te alcanza para ${_days(todayRunway)}.' : null,
        // S2 ("tu reserva pasó de X a Y") se descartó: necesita el runway de hoy,
        // justo lo que falta cuando S1 no aplica.
        () => streakDays > 0 ? 'Vas ${_n(streakDays, 'día')} gastando menos de ${Formatters.soles(threshold!)} al día.' : null,
      ], hasData: hasData, today: todayRunway),
  };

  final spendB = spend.isEmpty ? null : SpendBlock(spend);
  final blocks = switch (mode) {
    Mode.stable => [
        BudgetBlock(buildBudgetSummary(
            settings: settings, entries: entries, categories: categories, budgets: budgets, today: today)),
        spendB,
        streakB,
        monthsB,
        runwayB,
      ],
    Mode.variable => [hasData ? flow : null, monthsB, spendB, runwayB, streakB],
    Mode.survival => [
        runwayB,
        streakB,
        _suggested(movements, categories, activeCaps, today, opening),
        spendB,
        monthsB,
      ],
  };
  // 5AB: arriba de "Por cuenta" (al final si no hay cuentas). Sin datos, no aparece.
  final changes = categoryChanges(movements, today: today);
  final facts = pickTop([
    ?monthBalance(movements, today: today),
    ?changes.up,
    ?changes.down,
    daysLeft(movements, today: today, opening: opening, book: book),
    ?streakFact(days: streakDays, thresholdCents: threshold),
    ?topWeekday(movements, today: today),
  ]);
  final names = {for (final MapEntry(key: id, value: c) in catById.entries) id: c.name};
  final reading = hasData ? ReadingBlock([for (final f in facts) factText(f, categoryNames: names)]) : null;
  return InsightsSummary(
    mode: mode,
    phrase: phrase,
    blocks: [...blocks.nonNulls, ?reading, ?_byAccount(entries, accounts, transfers, opening, today)],
  );
}

/// Al final, solo con cuentas. "Sin asignar" con la misma regla que el Home.
ByAccountBlock? _byAccount(
    List<Entry> entries, List<Account> accounts, List<TransferRow> transfers, Opening? opening, DateTime today) {
  if (accounts.isEmpty) return null;
  final balances = balancesByAccount(
      entries: entries, accounts: accounts, transfers: transfers, unassignedOpening: opening, today: today);
  final from = isoDay(today.subtract(const Duration(days: 29))), to = isoDay(today);
  AccountFlowRow row(String? id, String name) {
    var out = 0, inc = 0;
    for (final e in entries) {
      if (e.accountId != id || e.occurredOn.compareTo(from) < 0 || e.occurredOn.compareTo(to) > 0) continue;
      e.kind == EntryKind.expense ? out += e.amountCents : inc += e.amountCents;
    }
    return (name: name, balance: balances[id]!, outCents: out, inCents: inc);
  }

  return ByAccountBlock([
    for (final a in accounts)
      if (!a.archived) row(a.id, a.name),
    if (showUnassigned(balances[null]!, entries, transfers)) row(null, unassignedName),
  ]);
}

String _first(List<String? Function()> options, {required bool hasData, required Runway today}) {
  for (final o in options) {
    if (o() case final s?) return s;
  }
  // "Registra unos días más" solo sin ningún dato: con historial sería falso.
  if (!hasData) return emptyPhrase;
  return today.status == RunwayStatus.noCushion ? noCushionPhrase : quietPhrase;
}

String? _budgetPhrase(Map<String, int> caps, List<Movement> movements, DateTime today) {
  final b = budgetStatus(caps, spentCents: spentInMonth(movements, today: today));
  if (b == null) return null;
  return 'Llevas ${Formatters.soles(b.spentCents)} de ${Formatters.soles(b.capCents)} de tus techos este mes.';
}

String? _sharePhrase(List<SpendRow> spend) {
  if (spend.isEmpty) return null;
  final top = spend.first; // la fila mayor nunca es el pliegue "Otros" salvo que sea la única
  return '${top.name} se llevó el ${top.percent} % de lo que gastaste en 30 días.';
}

String? _streakPhrase(int days) => days > 0 ? 'Vas ${_n(days, 'día')} sin pasarte de tu límite diario.' : null;

String _flowPhrase(FlowBlock f) => f.diffCents >= 0
    ? 'En un mes típico te sobran ~${Formatters.soles(f.diffCents)}.'
    : 'En un mes típico te faltan ~${Formatters.soles(-f.diffCents)}.';

String _n(int n, String word) => '$n ${n == 1 ? word : '${word}s'}';

String _days(Runway r) => r.capped ? '+$maxRunwayDays días' : _n(r.days, 'día');

const _foldId = 'otros';

/// Top 5 de 30 días (archivadas incluidas, V3) sin la categoría "Otros", que se
/// pliega con el resto en una sola fila final en piedra (nunca dos "Otros").
List<SpendRow> _spend(List<Movement> movements, Map<String, Category> catById, DateTime today) {
  final all = topCategories(movements, today: today, top: null, days: 30);
  final total = all.fold<int>(0, (a, x) => a + x.cents);
  if (total == 0) return const [];
  final named = all.where((x) => x.categoryId != _foldId).take(5).toList();
  final folded = total - named.fold<int>(0, (a, x) => a + x.cents);
  final rows = [
    for (final x in named) (name: catById[x.categoryId]?.name ?? 'Sin categoría', hex: catById[x.categoryId]?.colorHex ?? '', cents: x.cents),
    if (folded > 0) (name: 'Otros', hex: 'cat:6', cents: folded),
  ];
  final max = rows.map((r) => r.cents).reduce((a, b) => a > b ? a : b);
  return [
    for (final r in rows)
      SpendRow(
        name: r.name,
        colorHex: r.hex,
        cents: r.cents,
        percent: (r.cents * 100 / total).round(),
        fraction: r.cents / max,
      ),
  ];
}

SuggestedBlock? _suggested(
    List<Movement> movements, List<Category> categories, Map<String, int> caps, DateTime today, Opening? opening) {
  final suggested = suggestedCaps(movements, today: today, opening: opening);
  final rows = [
    for (final c in categories)
      if (!c.archived && !caps.containsKey(c.id) && suggested[c.id] != null)
        SuggestedRow(categoryId: c.id, name: c.name, icon: c.icon, cents: suggested[c.id]!),
  ]..sort((a, b) => b.cents != a.cents ? b.cents.compareTo(a.cents) : a.name.compareTo(b.name));
  return rows.isEmpty ? null : SuggestedBlock(rows.take(3).toList());
}
