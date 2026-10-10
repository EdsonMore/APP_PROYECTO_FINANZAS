/// Métricas puras de SaldoClaro. Sin Flutter, sin BD: entra una lista de
/// movimientos, sale un número. Fórmulas y casos borde en SPEC.md §Fórmulas.
///
/// Convenciones:
/// - Dinero en centavos enteros (`int`).
/// - Fechas como día local normalizado con [day] (UTC medianoche, sin DST).
/// - Todo evento con fecha > `today` se ignora.
library;

enum EntryKind { income, expense }

/// Modo de uso persistido en `settings.mode`.
enum Mode { stable, variable, survival }

/// Opción elegida en el onboarding. `mixed` es azúcar de UI: no existe en BD.
enum IncomeProfile { stable, variable, mixed, none }

Mode modeFor(IncomeProfile p) => switch (p) {
      IncomeProfile.stable => Mode.stable,
      IncomeProfile.variable || IncomeProfile.mixed => Mode.variable,
      IncomeProfile.none => Mode.survival,
    };

/// Día calendario sin hora. Usar siempre esto para `today` y `Movement.day`.
DateTime day(int y, int m, int d) => DateTime.utc(y, m, d);
DateTime dayOf(DateTime local) => DateTime.utc(local.year, local.month, local.day);

class Movement {
  const Movement({
    this.id,
    required this.kind,
    required this.cents,
    required this.day,
    this.categoryId,
    this.createdAt,
  });

  /// entries.id: permite volver de una métrica a la fila (p. ej. recientes).
  final String? id;
  final EntryKind kind;
  final int cents;
  final DateTime day;
  final String? categoryId;

  /// Solo importa el día del saldo inicial (ver [Opening]).
  final DateTime? createdAt;

  bool get isIncome => kind == EntryKind.income;
}

/// "¿Cuánto tienes hoy?": foto del saldo en el instante [setAt] (hora local).
class Opening {
  const Opening({required this.cents, required this.setAt});
  final int cents;
  final DateTime setAt;
  DateTime get day => dayOf(setAt);
}

/// Un movimiento ya está reflejado en el saldo inicial si es de un día previo,
/// o del mismo día y registrado antes de fijar el saldo.
bool _coveredByOpening(Movement m, Opening o) {
  if (m.day.isBefore(o.day)) return true;
  if (m.day == o.day && m.createdAt != null) return m.createdAt!.isBefore(o.setAt);
  return false;
}

int balance(List<Movement> movements, {required DateTime today, Opening? opening}) {
  var b = opening?.cents ?? 0;
  for (final m in movements) {
    if (m.day.isAfter(today)) continue;
    if (opening != null && _coveredByOpening(m, opening)) continue;
    b += m.isIncome ? m.cents : -m.cents;
  }
  return b;
}

DateTime? firstDay(List<Movement> movements, {required DateTime today, Opening? opening}) {
  DateTime? first = opening?.day;
  for (final m in movements) {
    if (m.day.isAfter(today)) continue;
    if (first == null || m.day.isBefore(first)) first = m.day;
  }
  return first;
}

/// D(W) = clamp(today − first + 1, 1, W). Nunca 0.
int effectiveDays({required DateTime? first, required DateTime today, required int window}) {
  if (first == null) return 1;
  return (today.difference(first).inDays + 1).clamp(1, window);
}

/// Suma de [kind] en los últimos [days] días terminando hoy (inclusivo).
int _sumInWindow(List<Movement> movements, EntryKind kind, DateTime today, int days) {
  final from = today.subtract(Duration(days: days - 1));
  var s = 0;
  for (final m in movements) {
    if (m.kind == kind && !m.day.isBefore(from) && !m.day.isAfter(today)) s += m.cents;
  }
  return s;
}

/// Gasto diario promedio en centavos/día sobre la ventana efectiva.
double avgDailyExpense(List<Movement> movements,
    {required DateTime today, int window = 14, Opening? opening}) {
  final d = effectiveDays(first: firstDay(movements, today: today, opening: opening), today: today, window: window);
  return _sumInWindow(movements, EntryKind.expense, today, d) / d;
}

enum RunwayStatus { empty, noCushion, noSpending, days }

class Runway {
  const Runway(this.status, {this.days = 0, this.estimated = false, this.capped = false});
  final RunwayStatus status;
  final int days;

  /// Menos de [minReliableDays] de historial: la UI lo rotula "estimado".
  final bool estimated;

  /// R real > [maxRunwayDays]; la UI muestra "+999 días".
  final bool capped;
}

const minReliableDays = 7;
const maxRunwayDays = 999;

/// R = floor(B / g) = floor(B · D / G), en enteros para no perder centavos.
Runway runway(List<Movement> movements, {required DateTime today, int window = 14, Opening? opening}) {
  final first = firstDay(movements, today: today, opening: opening);
  if (first == null) return const Runway(RunwayStatus.empty);

  final b = balance(movements, today: today, opening: opening);
  if (b <= 0) return const Runway(RunwayStatus.noCushion);

  final d = effectiveDays(first: first, today: today, window: window);
  final g = _sumInWindow(movements, EntryKind.expense, today, d);
  if (g == 0) return const Runway(RunwayStatus.noSpending);

  final r = (b * d) ~/ g;
  return Runway(
    RunwayStatus.days,
    days: r > maxRunwayDays ? maxRunwayDays : r,
    estimated: d < minReliableDays,
    capped: r > maxRunwayDays,
  );
}

const incomeWindows = {30, 60, 90};

/// Total de [kind] en la ventana efectiva, llevado a "cada 30 días".
int _per30(List<Movement> movements, EntryKind kind, DateTime today, int window, Opening? opening) {
  if (!incomeWindows.contains(window)) throw ArgumentError.value(window, 'window', 'debe ser 30, 60 o 90');
  final d = effectiveDays(first: firstDay(movements, today: today, opening: opening), today: today, window: window);
  return (_sumInWindow(movements, kind, today, d) * 30 / d).round();
}

/// Ingreso típico cada 30 días, promediado sobre 30/60/90 días.
int avgIncome30(List<Movement> movements, {required DateTime today, int window = 30, Opening? opening}) =>
    _per30(movements, EntryKind.income, today, window, opening);

/// Gasto típico cada 30 días (mismo cálculo que [avgIncome30]).
int avgExpense30(List<Movement> movements, {required DateTime today, int window = 30, Opening? opening}) =>
    _per30(movements, EntryKind.expense, today, window, opening);

enum Light { none, green, amber, red }

class Ratio {
  const Ratio(this.incomeCents, this.expenseCents, this.light);
  final int incomeCents;
  final int expenseCents;
  final Light light;
}

/// Semáforo entrada/salida de los últimos 30 días efectivos. Sin divisiones.
Ratio entryExitRatio(List<Movement> movements, {required DateTime today, Opening? opening}) {
  final d = effectiveDays(first: firstDay(movements, today: today, opening: opening), today: today, window: 30);
  final i = _sumInWindow(movements, EntryKind.income, today, d);
  final g = _sumInWindow(movements, EntryKind.expense, today, d);
  final Light light;
  if (i == 0 && g == 0) {
    light = Light.none;
  } else if (i >= g) {
    light = Light.green;
  } else if (10 * i >= 7 * g) {
    light = Light.amber; // 70–99 %
  } else {
    light = Light.red;
  }
  return Ratio(i, g, light);
}

/// Umbral diario de la racha. Se calcula UNA vez (al abrir Insights) y queda
/// congelado: no se recalcula por cada día del pasado. null = no mostrar racha.
int? streakThreshold(List<Movement> movements,
    {required DateTime today, required Mode mode, Map<String, int> capsCents = const {}, Opening? opening}) {
  if (mode == Mode.stable && capsCents.isNotEmpty) {
    final daysInMonth = DateTime.utc(today.year, today.month + 1, 0).day;
    return capsCents.values.fold<int>(0, (a, b) => a + b) ~/ daysInMonth;
  }
  final first = firstDay(movements, today: today, opening: opening);
  if (first == null) return null;
  final d30 = effectiveDays(first: first, today: today, window: 30);
  final income = _sumInWindow(movements, EntryKind.income, today, d30);
  if (income > 0) return (income / d30).round();
  return avgDailyExpense(movements, today: today, opening: opening).round();
}

/// Días consecutivos, desde hoy hacia atrás, con gasto del día ≤ [thresholdCents].
/// Un día sin gasto cuenta. No cuenta días anteriores al primer evento.
int streak(List<Movement> movements, {required DateTime today, required int thresholdCents}) {
  final first = firstDay(movements, today: today);
  if (first == null) return 0;
  final perDay = <DateTime, int>{};
  for (final m in movements) {
    if (m.kind == EntryKind.expense) perDay.update(m.day, (v) => v + m.cents, ifAbsent: () => m.cents);
  }
  var n = 0;
  for (var d = today; !d.isBefore(first); d = d.subtract(const Duration(days: 1))) {
    if ((perDay[d] ?? 0) > thresholdCents) break;
    n++;
  }
  return n;
}

/// Techo mensual sugerido por categoría: gasto de 90 días efectivos llevado a
/// 30 días, redondeado a S/ 10 (mínimo S/ 10 si hubo gasto).
Map<String, int> suggestedCaps(List<Movement> movements, {required DateTime today, Opening? opening}) {
  final d = effectiveDays(first: firstDay(movements, today: today, opening: opening), today: today, window: 90);
  final from = today.subtract(Duration(days: d - 1));
  final byCat = <String, int>{};
  for (final m in movements) {
    if (m.kind != EntryKind.expense || m.categoryId == null) continue;
    if (m.day.isBefore(from) || m.day.isAfter(today)) continue;
    byCat.update(m.categoryId!, (v) => v + m.cents, ifAbsent: () => m.cents);
  }
  return byCat.map((cat, total) {
    final rounded = (total * 30 / d / 1000).round() * 1000;
    return MapEntry(cat, rounded < 1000 ? 1000 : rounded);
  });
}

/// Suma de [kind] desde el día 1 del mes de [today] hasta hoy (inclusive).
int _sumInMonth(List<Movement> movements, EntryKind kind, DateTime today) {
  final from = DateTime.utc(today.year, today.month, 1);
  var s = 0;
  for (final m in movements) {
    if (m.kind == kind && !m.day.isBefore(from) && !m.day.isAfter(today)) s += m.cents;
  }
  return s;
}

/// Gastado en el mes calendario actual ("Gastaste S/ X en octubre").
int spentInMonth(List<Movement> movements, {required DateTime today}) =>
    _sumInMonth(movements, EntryKind.expense, today);

/// Ingresado en el mes calendario actual (regla: sin ingreso no hay "presupuesto restante").
int incomeInMonth(List<Movement> movements, {required DateTime today}) =>
    _sumInMonth(movements, EntryKind.income, today);

/// Gastado por categoría en el mes calendario de [today], hasta hoy. Sin
/// categoría (no debería pasar en un gasto) no cuenta.
Map<String, int> spentByCategoryInMonth(List<Movement> movements, {required DateTime today}) {
  final from = DateTime.utc(today.year, today.month, 1);
  final byCat = <String, int>{};
  for (final m in movements) {
    if (m.kind != EntryKind.expense || m.categoryId == null) continue;
    if (m.day.isBefore(from) || m.day.isAfter(today)) continue;
    byCat.update(m.categoryId!, (v) => v + m.cents, ifAbsent: () => m.cents);
  }
  return byCat;
}

typedef BudgetStatus = ({int capCents, int spentCents, int remainingCents, int percent});

/// Presupuesto del mes: Σ techos vs gastado. null si no hay techos.
/// [percent] redondea hacia abajo y puede pasar de 100.
BudgetStatus? budgetStatus(Map<String, int> capsCents, {required int spentCents}) {
  if (capsCents.isEmpty) return null;
  final cap = capsCents.values.fold<int>(0, (a, b) => a + b);
  return (
    capCents: cap,
    spentCents: spentCents,
    remainingCents: cap - spentCents,
    percent: cap == 0 ? 0 : spentCents * 100 ~/ cap,
  );
}

/// Categorías con más gasto en los últimos [days] días calendario (hoy incluido),
/// de mayor a menor; empate por id para un orden estable.
List<({String categoryId, int cents})> topCategories(List<Movement> movements,
    {required DateTime today, int top = 3, int days = 30}) {
  final from = today.subtract(Duration(days: days - 1));
  final byCat = <String, int>{};
  for (final m in movements) {
    if (m.kind != EntryKind.expense || m.categoryId == null) continue;
    if (m.day.isBefore(from) || m.day.isAfter(today)) continue;
    byCat.update(m.categoryId!, (v) => v + m.cents, ifAbsent: () => m.cents);
  }
  final list = [for (final e in byCat.entries) (categoryId: e.key, cents: e.value)]
    ..sort((a, b) => b.cents != a.cents ? b.cents.compareTo(a.cents) : a.categoryId.compareTo(b.categoryId));
  return list.take(top).toList();
}

/// Últimos [limit] movimientos: por fecha del movimiento y luego por hora de
/// registro, más nuevo primero. Ignora fechas futuras.
List<Movement> recentMovements(List<Movement> movements, {required DateTime today, int limit = 5}) {
  final epoch = DateTime.fromMillisecondsSinceEpoch(0);
  final list = movements.where((m) => !m.day.isAfter(today)).toList()
    ..sort((a, b) {
      final byDay = b.day.compareTo(a.day);
      return byDay != 0 ? byDay : (b.createdAt ?? epoch).compareTo(a.createdAt ?? epoch);
    });
  return list.take(limit).toList();
}

