import 'package:intl/intl.dart';

import '../../data/database.dart';
import '../../domain/metrics.dart';

/// Lógica pura del Historial (4B): filtrar, buscar, agrupar y sumar. Todo en
/// memoria sobre la lista de movimientos que ya usa el Home (H2).

enum KindFilter { all, expense, income }

enum RangePreset { all, thisMonth, lastMonth, last30, last90, custom }

/// Días del dominio, bordes incluidos.
typedef DayRange = ({DateTime from, DateTime to});

DayRange? rangeFor(RangePreset preset, DateTime today, {DayRange? custom}) => switch (preset) {
  RangePreset.all => null,
  RangePreset.thisMonth => (from: day(today.year, today.month, 1), to: day(today.year, today.month + 1, 0)),
  RangePreset.lastMonth => (from: day(today.year, today.month - 1, 1), to: day(today.year, today.month, 0)),
  RangePreset.last30 => (from: today.subtract(const Duration(days: 29)), to: today),
  RangePreset.last90 => (from: today.subtract(const Duration(days: 89)), to: today),
  RangePreset.custom => custom,
};

String rangeLabel(RangePreset preset, {DayRange? custom}) {
  if (preset == RangePreset.custom && custom != null) {
    final (:from, :to) = custom;
    String f(DateTime d, String pattern) => DateFormat(pattern, 'es_PE').format(DateTime(d.year, d.month, d.day));
    if (from == to) return f(from, 'd MMM');
    if (from.year != to.year) return '${f(from, 'd MMM y')} – ${f(to, 'd MMM y')}';
    if (from.month != to.month) return '${f(from, 'd MMM')} – ${f(to, 'd MMM')}';
    return '${from.day} – ${f(to, 'd MMM')}';
  }
  return switch (preset) {
    RangePreset.thisMonth => 'Este mes',
    RangePreset.lastMonth => 'Mes pasado',
    RangePreset.last30 => 'Últimos 30 días',
    RangePreset.last90 => 'Últimos 90 días',
    RangePreset.custom => 'Personalizado',
    RangePreset.all => 'Todo',
  };
}

const _plain = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u', 'ñ': 'n'};

/// Minúsculas, sin tildes y la ñ como n (solo para comparar, H5).
String normalizeForSearch(String s) => s.toLowerCase().split('').map((c) => _plain[c] ?? c).join();

class HistoryFilter {
  const HistoryFilter({
    this.kind = KindFilter.all,
    this.picks = const {},
    this.preset = RangePreset.all,
    this.custom,
    this.query = '',
    this.account,
  });

  final KindFilter kind;

  /// Categorías o fuentes marcadas; se suman (O). Vacío = todas.
  final Set<String> picks;
  final RangePreset preset;
  final DayRange? custom;
  final String query;

  /// Filtro por cuenta (4A, desde el Home). null = todas; (id: null) = "Sin asignar".
  final ({String? id})? account;

  bool get isDefault =>
      kind == KindFilter.all && picks.isEmpty && preset == RangePreset.all && query.trim().isEmpty && account == null;

  HistoryFilter copyWith({KindFilter? kind, Set<String>? picks, RangePreset? preset, DayRange? custom, String? query}) =>
      HistoryFilter(
        kind: kind ?? this.kind,
        picks: picks ?? this.picks,
        preset: preset ?? this.preset,
        custom: custom ?? this.custom,
        query: query ?? this.query,
        account: account,
      );

  /// Sin el filtro de cuenta (la ✕ de su chip).
  HistoryFilter withoutAccount() =>
      HistoryFilter(kind: kind, picks: picks, preset: preset, custom: custom, query: query);
}

List<Entry> applyFilter(
  List<Entry> entries,
  HistoryFilter f, {
  required DateTime today,
  required Map<String, String> catNames,
  required Map<String, String> srcNames,
}) {
  final range = rangeFor(f.preset, today, custom: f.custom);
  final from = range == null ? null : isoDay(range.from), to = range == null ? null : isoDay(range.to);
  final q = normalizeForSearch(f.query.trim());
  return [
    for (final e in entries)
      if (switch (f.kind) {
            KindFilter.all => true,
            KindFilter.expense => e.kind == EntryKind.expense,
            KindFilter.income => e.kind == EntryKind.income,
          } &&
          (f.picks.isEmpty || f.picks.contains(e.categoryId ?? e.sourceId)) &&
          (f.account == null || e.accountId == f.account!.id) &&
          // 'YYYY-MM-DD' se ordena igual que la fecha.
          (from == null || (e.occurredOn.compareTo(from) >= 0 && e.occurredOn.compareTo(to!) <= 0)) &&
          (q.isEmpty ||
              normalizeForSearch(e.note ?? '').contains(q) ||
              normalizeForSearch(catNames[e.categoryId] ?? srcNames[e.sourceId] ?? '').contains(q)))
        e,
  ];
}

/// "Yape → Efectivo"; un lado nulo es "Sin asignar".
String transferTitle(TransferRow t, Map<String, String> accountNames) =>
    '${accountNames[t.fromAccountId] ?? 'Sin asignar'} → ${accountNames[t.toAccountId] ?? 'Sin asignar'}';

/// Transferencias del Historial (4A): solo con "Todos" y sin chips de
/// categoría/fuente (no son gasto ni ingreso). Rango, búsqueda (nota y nombres
/// de las cuentas) y filtro de cuenta (la que sale o la que entra) aplican.
List<TransferRow> applyTransferFilter(List<TransferRow> transfers, HistoryFilter f,
    {required DateTime today, required Map<String, String> accountNames}) {
  if (f.kind != KindFilter.all || f.picks.isNotEmpty) return const [];
  final range = rangeFor(f.preset, today, custom: f.custom);
  final from = range == null ? null : isoDay(range.from), to = range == null ? null : isoDay(range.to);
  final q = normalizeForSearch(f.query.trim());
  return [
    for (final t in transfers)
      if ((from == null || (t.occurredOn.compareTo(from) >= 0 && t.occurredOn.compareTo(to!) <= 0)) &&
          (f.account == null || t.fromAccountId == f.account!.id || t.toAccountId == f.account!.id) &&
          (q.isEmpty ||
              normalizeForSearch(t.note ?? '').contains(q) ||
              normalizeForSearch(transferTitle(t, accountNames)).contains(q)))
        t,
  ];
}

typedef PickChoice = ({String id, String name, String icon, String colorHex, bool isCategory});

/// Chips según el tipo (H4): activas y archivadas con movimientos, en su orden;
/// con "Todos", categorías y después fuentes.
List<PickChoice> pickChoices(KindFilter kind, List<Category> cats, List<Source> srcs, List<Entry> entries) {
  final used = {for (final e in entries) e.categoryId ?? e.sourceId};
  return [
    if (kind != KindFilter.income)
      for (final c in [...cats]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
        if (!c.archived || used.contains(c.id))
          (id: c.id, name: c.name, icon: c.icon, colorHex: c.colorHex, isCategory: true),
    if (kind != KindFilter.expense)
      for (final s in [...srcs]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
        if (!s.archived || used.contains(s.id))
          (id: s.id, name: s.name, icon: s.icon, colorHex: s.colorHex, isCategory: false),
  ];
}

typedef DayGroup = ({DateTime day, List<Entry> entries});

/// Del día más nuevo al más viejo; dentro del día, el último registrado primero.
List<DayGroup> groupByDay(List<Entry> entries) => [
      for (final g in groupByDayOf(entries, day: (e) => e.occurredOn, created: (e) => e.createdAt))
        (day: g.day, entries: g.items),
    ];

/// Lo mismo para cualquier fila (movimientos y transferencias mezclados, 4A).
List<({DateTime day, List<T> items})> groupByDayOf<T>(List<T> rows,
    {required String Function(T) day, required int Function(T) created}) {
  final sorted = [...rows]..sort((a, b) {
      final byDay = day(b).compareTo(day(a));
      return byDay != 0 ? byDay : created(b).compareTo(created(a));
    });
  final groups = <({DateTime day, List<T> items})>[];
  for (final r in sorted) {
    if (groups.isEmpty || isoDay(groups.last.day) != day(r)) {
      groups.add((day: parseIsoDay(day(r)), items: <T>[]));
    }
    groups.last.items.add(r);
  }
  return groups;
}

const _weekdays = ['lun', 'mar', 'mié', 'jue', 'vie', 'sáb', 'dom'];

/// "Hoy", "Ayer", "lun 5 oct"; de otro año, "lun 6 oct 2025".
String dayHeader(DateTime d, DateTime today) {
  if (d == today) return 'Hoy';
  if (d == today.subtract(const Duration(days: 1))) return 'Ayer';
  final date = DateFormat(d.year == today.year ? 'd MMM' : 'd MMM y', 'es_PE').format(DateTime(d.year, d.month, d.day));
  return '${_weekdays[d.weekday - 1]} $date';
}

typedef Totals = ({int count, int expenseCents, int incomeCents});

Totals totalsOf(List<Entry> entries) {
  var expense = 0, income = 0;
  for (final e in entries) {
    e.kind == EntryKind.expense ? expense += e.amountCents : income += e.amountCents;
  }
  return (count: entries.length, expenseCents: expense, incomeCents: income);
}
