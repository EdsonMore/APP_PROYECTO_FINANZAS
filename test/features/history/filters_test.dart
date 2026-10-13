import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/history/filters.dart';

final today = day(2026, 10, 13);
var _n = 0;

Entry e({
  EntryKind kind = EntryKind.expense,
  int cents = 1000,
  DateTime? on,
  String? cat = 'comida',
  String? src,
  String? note,
  int? created,
}) =>
    Entry(
      id: 'e${_n++}',
      kind: kind,
      amountCents: cents,
      occurredOn: isoDay(on ?? today),
      categoryId: kind == EntryKind.expense ? cat : null,
      sourceId: kind == EntryKind.income ? (src ?? 'chamba') : null,
      note: note,
      origin: Origin.manual,
      createdAt: created ?? _n,
      updatedAt: created ?? _n,
    );

Category cat(String id, String name, {bool archived = false, int order = 0}) => Category(
    id: id, name: name, icon: 'x', colorHex: 'cat:1', sortOrder: order, archived: archived, isDefault: true, updatedAt: 1);

Source src(String id, String name, {bool archived = false, int order = 0}) => Source(
    id: id, name: name, icon: 'y', colorHex: '#525252', sortOrder: order, archived: archived, isDefault: true, updatedAt: 1);

void main() {
  setUpAll(() => initializeDateFormatting('es_PE'));

  group('rangos', () {
    DayRange? r(RangePreset p) => rangeFor(p, today);

    test('Todo: sin límite', () => expect(r(RangePreset.all), isNull));
    test('Este mes: del 1 al último día (incluye fechas futuras del mes)', () {
      expect(r(RangePreset.thisMonth), (from: day(2026, 10, 1), to: day(2026, 10, 31)));
    });
    test('Mes pasado', () => expect(r(RangePreset.lastMonth), (from: day(2026, 9, 1), to: day(2026, 9, 30))));
    test('Mes pasado en enero: diciembre del año anterior', () {
      expect(rangeFor(RangePreset.lastMonth, day(2027, 1, 5)), (from: day(2026, 12, 1), to: day(2026, 12, 31)));
    });
    test('Este mes en febrero bisiesto', () {
      expect(rangeFor(RangePreset.thisMonth, day(2028, 2, 10)), (from: day(2028, 2, 1), to: day(2028, 2, 29)));
    });
    test('Últimos 30 y 90 días: incluyen hoy', () {
      expect(r(RangePreset.last30), (from: day(2026, 9, 14), to: today));
      expect(r(RangePreset.last90), (from: day(2026, 7, 16), to: today));
    });
    test('Personalizado: el que se eligió', () {
      final c = (from: day(2026, 10, 1), to: day(2026, 10, 15));
      expect(rangeFor(RangePreset.custom, today, custom: c), c);
    });

    test('etiquetas del chip Fecha', () {
      expect(rangeLabel(RangePreset.all), 'Todo');
      expect(rangeLabel(RangePreset.thisMonth), 'Este mes');
      expect(rangeLabel(RangePreset.lastMonth), 'Mes pasado');
      expect(rangeLabel(RangePreset.last30), 'Últimos 30 días');
      expect(rangeLabel(RangePreset.last90), 'Últimos 90 días');
      expect(rangeLabel(RangePreset.custom, custom: (from: day(2026, 10, 1), to: day(2026, 10, 15))), '1 – 15 oct');
      expect(rangeLabel(RangePreset.custom, custom: (from: day(2026, 9, 28), to: day(2026, 10, 3))), '28 sept – 3 oct', reason: 'es_PE abrevia septiembre como "sept"');
      expect(rangeLabel(RangePreset.custom, custom: (from: day(2025, 12, 28), to: day(2026, 1, 3))),
          '28 dic 2025 – 3 ene 2026');
      expect(rangeLabel(RangePreset.custom, custom: (from: day(2026, 10, 5), to: day(2026, 10, 5))), '5 oct');
    });
  });

  group('búsqueda', () {
    test('normaliza mayúsculas, tildes y ñ', () {
      expect(normalizeForSearch('Café NIÑO Ácido ü'), 'cafe nino acido u');
    });

    final cats = {'comida': 'Comida', 'ocio': 'Ocio'};
    final srcs = {'chamba': 'Chamba'};
    List<String> find(List<Entry> es, String q) =>
        [for (final x in applyFilter(es, HistoryFilter(query: q), today: today, catNames: cats, srcNames: srcs)) x.id];

    test('O4: busca en la nota, la categoría y la fuente', () {
      final super1 = e(note: 'supermercado Plaza Vea');
      final comida = e(); // sin nota
      final cine = e(cat: 'ocio', note: 'cine');
      final pago = e(kind: EntryKind.income, src: 'chamba');
      final all = [super1, comida, cine, pago];
      expect(find(all, 'supermercado'), [super1.id]);
      expect(find(all, 'comida'), unorderedEquals([super1.id, comida.id]), reason: 'por el nombre de la categoría');
      expect(find(all, 'CHAMBA'), [pago.id], reason: 'por el nombre de la fuente');
      expect(find(all, ''), hasLength(4));
      expect(find(all, '  '), hasLength(4), reason: 'solo espacios = sin búsqueda');
    });

    test('sin tildes encuentra con tildes y al revés', () {
      final cafe = e(note: 'Café con Niño');
      expect(find([cafe], 'cafe con nino'), [cafe.id]);
      expect(find([cafe], 'nino'), [cafe.id]);
      expect(find([e(note: 'cafe')], 'café'), hasLength(1));
    });
  });

  group('combinaciones', () {
    final cats = {'comida': 'Comida', 'ocio': 'Ocio'};
    final srcs = {'chamba': 'Chamba', 'venta': 'Venta'};
    late List<Entry> all;
    late Entry comidaHoy, ocioViejo, comidaMesPasado, chamba, venta;
    setUp(() {
      comidaHoy = e(note: 'menú');
      ocioViejo = e(cat: 'ocio', on: day(2026, 6, 1));
      comidaMesPasado = e(on: day(2026, 9, 20));
      chamba = e(kind: EntryKind.income, src: 'chamba', on: day(2026, 10, 2));
      venta = e(kind: EntryKind.income, src: 'venta', on: day(2026, 8, 1));
      all = [comidaHoy, ocioViejo, comidaMesPasado, chamba, venta];
    });
    List<String> ids(HistoryFilter f) =>
        [for (final x in applyFilter(all, f, today: today, catNames: cats, srcNames: srcs)) x.id];

    test('tipo', () {
      expect(ids(const HistoryFilter(kind: KindFilter.expense)),
          unorderedEquals([comidaHoy.id, ocioViejo.id, comidaMesPasado.id]));
      expect(ids(const HistoryFilter(kind: KindFilter.income)), unorderedEquals([chamba.id, venta.id]));
    });
    test('chips: se suman (O)', () {
      expect(ids(const HistoryFilter(picks: {'ocio', 'venta'})), unorderedEquals([ocioViejo.id, venta.id]));
    });
    test('tipo + chip + rango + búsqueda juntos', () {
      expect(ids(const HistoryFilter(kind: KindFilter.expense, picks: {'comida'}, preset: RangePreset.thisMonth)),
          [comidaHoy.id]);
      expect(ids(const HistoryFilter(kind: KindFilter.expense, picks: {'comida'}, preset: RangePreset.last90)),
          unorderedEquals([comidaHoy.id, comidaMesPasado.id]));
      expect(ids(const HistoryFilter(preset: RangePreset.last90, query: 'menu')), [comidaHoy.id]);
    });
    test('rango personalizado: bordes incluidos', () {
      expect(
          ids(HistoryFilter(preset: RangePreset.custom, custom: (from: day(2026, 9, 20), to: day(2026, 10, 2)))),
          unorderedEquals([comidaMesPasado.id, chamba.id]));
    });
    test('isDefault: solo sin ningún filtro', () {
      expect(const HistoryFilter().isDefault, isTrue);
      expect(const HistoryFilter(query: ' ').isDefault, isTrue);
      expect(const HistoryFilter(query: 'x').isDefault, isFalse);
      expect(const HistoryFilter(kind: KindFilter.income).isDefault, isFalse);
      expect(const HistoryFilter(picks: {'a'}).isDefault, isFalse);
      expect(const HistoryFilter(preset: RangePreset.last30).isDefault, isFalse);
    });
  });

  group('chips según tipo (H4)', () {
    final cats = [cat('comida', 'Comida', order: 1), cat('ropa', 'Ropa', archived: true, order: 2), cat('viajes', 'Viajes', archived: true, order: 3)];
    final srcs = [src('chamba', 'Chamba'), src('vieja', 'Vieja', archived: true)];
    final entries = [e(cat: 'ropa')]; // la archivada "Ropa" tiene movimientos; "Viajes" no

    List<String> chips(KindFilter k) => [for (final c in pickChoices(k, cats, srcs, entries)) c.id];

    test('Gastos: activas + archivadas con movimientos, en su orden', () {
      expect(chips(KindFilter.expense), ['comida', 'ropa']);
    });
    test('Ingresos: fuentes', () => expect(chips(KindFilter.income), ['chamba']));
    test('Todos: categorías y después fuentes', () => expect(chips(KindFilter.all), ['comida', 'ropa', 'chamba']));
  });

  group('agrupación por día', () {
    test('del más nuevo al más viejo; dentro del día, por hora de registro', () {
      final a = e(on: day(2026, 10, 12), created: 1);
      final b = e(on: today, created: 2);
      final c = e(on: today, created: 3);
      final g = groupByDay([a, b, c]);
      expect([for (final x in g) x.day], [today, day(2026, 10, 12)]);
      expect([for (final x in g.first.entries) x.id], [c.id, b.id]);
    });

    test('encabezados: Hoy, Ayer, "lun 5 oct" y otro año', () {
      expect(dayHeader(today, today), 'Hoy');
      expect(dayHeader(day(2026, 10, 12), today), 'Ayer');
      expect(dayHeader(day(2026, 10, 5), today), 'lun 5 oct');
      expect(dayHeader(day(2026, 10, 6), today), 'mar 6 oct');
      expect(dayHeader(day(2026, 10, 11), today), 'dom 11 oct');
      expect(dayHeader(day(2025, 10, 6), today), 'lun 6 oct 2025');
      expect(dayHeader(day(2026, 10, 14), today), 'mié 14 oct', reason: 'una fecha futura no es "Hoy"');
    });
  });

  test('totales', () {
    final t = totalsOf([e(cents: 1050), e(cents: 200), e(kind: EntryKind.income, cents: 80000)]);
    expect(t, (count: 3, expenseCents: 1250, incomeCents: 80000));
    expect(totalsOf(const []), (count: 0, expenseCents: 0, incomeCents: 0));
  });
}
