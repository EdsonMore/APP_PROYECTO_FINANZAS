import 'metrics.dart';

/// Motor de hechos (fase 5AB): funciones puras sobre los movimientos. Devuelven
/// datos con su prioridad, no texto: las frases las arma la UI, y la capa de IA
/// (5B) recibirá exactamente estos mismos hechos.

sealed class Fact {
  const Fact();
}

/// Ingreso − gasto del mes calendario hasta hoy. Negativo: salió más.
class BalanceFact extends Fact {
  const BalanceFact({required this.cents});
  final int cents;
}

/// Una categoría contra el mismo tramo del mes anterior (H1).
class CategoryChange extends Fact {
  const CategoryChange(
      {required this.categoryId, required this.deltaCents, required this.percent, required this.previousMonth});
  final String categoryId;
  final int deltaCents;
  final int percent;

  /// Día 1 del mes con el que se compara.
  final DateTime previousMonth;
}

/// Días del mes que quedan (hoy incluido), saldo y cuánto da por día.
/// [dailyCents] null = sin reserva.
class DaysLeftFact extends Fact {
  const DaysLeftFact({required this.days, required this.balanceCents, required this.dailyCents});
  final int days;
  final int balanceCents;
  final int? dailyCents;
}

class StreakFact extends Fact {
  const StreakFact({required this.days, required this.thresholdCents});
  final int days;
  final int thresholdCents;
}

/// [weekday]: DateTime.monday … DateTime.sunday.
class WeekdayFact extends Fact {
  const WeekdayFact({required this.weekday, required this.avgCents});
  final int weekday;
  final int avgCents;
}

// H2: umbrales para que un hecho aparezca.
const _minDeltaCents = 2000;
const _minDeltaPercent = 20;
const _minStreakDays = 3;
const _weekdayLift = 1.3;
const _weekdayMinDays = 28;
const _weekdayWindow = 56;

BalanceFact? monthBalance(List<Movement> movements, {required DateTime today}) {
  final income = incomeInMonth(movements, today: today);
  if (income == 0) return null;
  return BalanceFact(cents: income - spentInMonth(movements, today: today));
}

Map<String, int> _byCategory(List<Movement> movements, DateTime from, DateTime to) {
  final out = <String, int>{};
  for (final m in movements) {
    if (m.kind != EntryKind.expense || m.categoryId == null || m.day.isBefore(from) || m.day.isAfter(to)) continue;
    out.update(m.categoryId!, (v) => v + m.cents, ifAbsent: () => m.cents);
  }
  return out;
}

/// H1: del 1 a hoy contra el 1 al mismo día del mes anterior (o su último día,
/// si es más corto). Solo si los datos cubren el mes anterior desde el día 1.
({CategoryChange? up, CategoryChange? down}) categoryChanges(List<Movement> movements, {required DateTime today}) {
  final prevStart = DateTime.utc(today.year, today.month - 1, 1);
  final first = firstDay(movements, today: today);
  if (first == null || first.isAfter(prevStart)) return (up: null, down: null);
  final prevLast = DateTime.utc(today.year, today.month, 0).day;
  final prevEnd = DateTime.utc(prevStart.year, prevStart.month, today.day < prevLast ? today.day : prevLast);
  final cur = _byCategory(movements, DateTime.utc(today.year, today.month, 1), today);
  final prev = _byCategory(movements, prevStart, prevEnd);
  CategoryChange? up, down;
  for (final MapEntry(key: cat, value: before) in prev.entries) {
    final delta = (cur[cat] ?? 0) - before;
    if (delta.abs() < _minDeltaCents || delta.abs() * 100 < _minDeltaPercent * before) continue;
    final c = CategoryChange(
        categoryId: cat, deltaCents: delta, percent: (delta * 100 / before).round(), previousMonth: prevStart);
    if (delta > 0 && (up == null || delta > up.deltaCents)) up = c;
    if (delta < 0 && (down == null || delta < down.deltaCents)) down = c;
  }
  return (up: up, down: down);
}

/// Días hasta fin de mes con la calculadora de 4E (`dailyAllowance`).
DaysLeftFact daysLeft(List<Movement> movements,
    {required DateTime today, Opening? opening, AccountBook book = const AccountBook()}) {
  final days = daysUntil(DateTime.utc(today.year, today.month + 1, 0), today: today);
  final a = dailyAllowance(movements, today: today, days: days, opening: opening, book: book);
  return DaysLeftFact(
    days: days,
    balanceCents: globalBalance(movements, today: today, opening: opening, book: book),
    dailyCents: a?.limitCents,
  );
}

/// La racha de Insights (`streak`), con el umbral ya calculado.
StreakFact? streakFact({required int days, required int? thresholdCents}) =>
    thresholdCents == null || days < _minStreakDays ? null : StreakFact(days: days, thresholdCents: thresholdCents);

/// Promedio por día de la semana en las últimas 8 semanas. Solo con 4 semanas
/// de datos y si el día top supera en 30% al promedio de los otros seis.
WeekdayFact? topWeekday(List<Movement> movements, {required DateTime today}) {
  final first = firstDay(movements, today: today);
  if (first == null || today.difference(first).inDays + 1 < _weekdayMinDays) return null;
  final windowStart = today.subtract(const Duration(days: _weekdayWindow - 1));
  final from = first.isAfter(windowStart) ? first : windowStart;
  final sum = List.filled(8, 0), count = List.filled(8, 0);
  for (var d = from; !d.isAfter(today); d = d.add(const Duration(days: 1))) {
    count[d.weekday]++;
  }
  for (final m in movements) {
    if (m.kind == EntryKind.expense && !m.day.isBefore(from) && !m.day.isAfter(today)) sum[m.day.weekday] += m.cents;
  }
  final avg = [for (var w = 1; w <= 7; w++) count[w] == 0 ? 0.0 : sum[w] / count[w]];
  var top = 0;
  for (var i = 1; i < 7; i++) {
    if (avg[i] > avg[top]) top = i;
  }
  final others = [for (var i = 0; i < 7; i++) if (i != top) avg[i]];
  final mean = others.reduce((a, b) => a + b) / others.length;
  if (avg[top] <= 0 || avg[top] < mean * _weekdayLift) return null;
  return WeekdayFact(weekday: top + 1, avgCents: avg[top].round());
}

/// H3: un gasto ya guardado, con su nota (para el nombre del pago).
typedef PaidExpense = ({String categoryId, int cents, DateTime day, String? note, String? accountId});

class RecurringPayment {
  const RecurringPayment({
    required this.categoryId,
    required this.cents,
    required this.anchorDay,
    required this.note,
    required this.accountId,
    required this.last,
  });
  final String categoryId;
  final int cents;
  final int anchorDay;

  /// La nota más frecuente de la cadena; null si ninguno tenía.
  final String? note;

  /// La cuenta del último pago.
  final String? accountId;
  final DateTime last;

  /// Para "No, gracias" (H5) y para saber si ya hay un recordatorio igual.
  String get key => '$categoryId|$cents';
}

const _minChain = 3;
const _minGap = 26, _maxGap = 35;

/// H3: misma categoría y mismo monto exacto, y los 3 pagos más recientes
/// seguidos, a 26-35 días uno del otro; el último hace 35 días o menos. Un
/// gasto igual que se repite más seguido (un menú diario) no califica.
List<RecurringPayment> recurringPayments(List<PaidExpense> expenses, {required DateTime today}) {
  final groups = <String, List<PaidExpense>>{};
  for (final e in expenses) {
    groups.putIfAbsent('${e.categoryId}|${e.cents}', () => []).add(e);
  }
  final out = <RecurringPayment>[];
  for (final g in groups.values) {
    g.sort((a, b) => b.day.compareTo(a.day)); // del más nuevo al más viejo
    final last = g.first;
    if (today.difference(last.day).inDays > _maxGap) continue;
    final chain = g.take(_minChain).toList();
    if (chain.length < _minChain) continue;
    var monthly = true;
    for (var i = 1; i < chain.length; i++) {
      final gap = chain[i - 1].day.difference(chain[i].day).inDays;
      if (gap < _minGap || gap > _maxGap) monthly = false;
    }
    if (!monthly) continue;
    final counts = <String, int>{};
    for (final e in chain) {
      final n = e.note?.trim();
      if (n != null && n.isNotEmpty) counts.update(n, (v) => v + 1, ifAbsent: () => 1);
    }
    String? note;
    for (final e in chain) {
      // Empate: la más reciente (la cadena va de nuevo a viejo).
      final n = e.note?.trim();
      if (n != null && n.isNotEmpty && (note == null || counts[n]! > counts[note]!)) note = n;
    }
    out.add(RecurringPayment(
        categoryId: last.categoryId, cents: last.cents, anchorDay: last.day.day, note: note,
        accountId: last.accountId, last: last.day));
  }
  out.sort((a, b) => b.last.compareTo(a.last));
  return out;
}

/// Prioridad de la "Lectura del mes": las 4 más relevantes.
int _rank(Fact f) => switch (f) {
      BalanceFact(:final cents) when cents < 0 => 0,
      CategoryChange(:final deltaCents) when deltaCents > 0 => 1,
      DaysLeftFact() => 2,
      BalanceFact() => 3,
      StreakFact(:final days) when days >= 7 => 4,
      CategoryChange() => 5,
      WeekdayFact() => 6,
      StreakFact() => 7,
    };

List<Fact> pickTop(List<Fact> facts, {int max = 4}) {
  final sorted = [...facts]..sort((a, b) => _rank(a).compareTo(_rank(b)));
  return sorted.take(max).toList();
}
