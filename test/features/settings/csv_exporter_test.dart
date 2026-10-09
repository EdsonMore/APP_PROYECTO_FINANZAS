import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/settings/csv_exporter.dart';

const cats = [
  Category(id: 'comida', name: 'Comida', icon: 'restaurant', colorHex: '#000', sortOrder: 0, archived: false, isDefault: true),
  Category(id: 'viajes', name: 'Viajes', icon: 'flight', colorHex: '#000', sortOrder: 1, archived: true, isDefault: false),
];
const srcs = [
  Source(id: 'prestamo', name: 'Préstamo', icon: 'account_balance', colorHex: '#000', sortOrder: 0, archived: false, isDefault: true),
];

int ms(int day, int hour, [int minute = 0]) => DateTime(2026, 10, day, hour, minute).millisecondsSinceEpoch;

Entry entry(String id, EntryKind kind, int cents, String on, int created,
        {String? cat, String? src, String? note, Origin origin = Origin.manual, String? account}) =>
    Entry(
      id: id,
      kind: kind,
      amountCents: cents,
      occurredOn: on,
      categoryId: cat,
      sourceId: src,
      note: note,
      origin: origin,
      accountLabel: account,
      createdAt: created,
      updatedAt: created,
    );

List<String> lines(String csv) => csv.substring(1).split('\r\n')..removeLast();

void main() {
  test('empieza con BOM UTF-8 y termina cada línea en CRLF', () {
    final csv = entriesToCsv(const [], categories: cats, sources: srcs);
    expect(csv.codeUnitAt(0), 0xFEFF);
    expect(csv.endsWith('\r\n'), isTrue);
  });

  test('encabezados separados por punto y coma, con updated_at y account_label al final', () {
    final header = lines(entriesToCsv(const [], categories: cats, sources: srcs)).single;
    expect(header,
        'id;kind;amount_cents;amount;occurred_on;category_or_source;category_or_source_id;note;origin;created_at;updated_at;account_label');
  });

  test('fila completa: tipo en español, montos entero y decimal, nombre, id, ISO local', () {
    final csv = entriesToCsv([entry('e1', EntryKind.expense, 1250, '2026-10-08', ms(8, 14, 32), cat: 'comida')],
        categories: cats, sources: srcs);
    expect(lines(csv)[1], 'e1;gasto;1250;12.50;2026-10-08;Comida;comida;;manual;2026-10-08T14:32:00;2026-10-08T14:32:00;');
  });

  test('montos chicos y redondos', () {
    final csv = entriesToCsv([
      entry('a', EntryKind.income, 5, '2026-10-08', ms(8, 9), src: 'prestamo'),
      entry('b', EntryKind.income, 100000, '2026-10-07', ms(7, 9), src: 'prestamo'),
    ], categories: cats, sources: srcs);
    expect(lines(csv)[1].split(';').sublist(1, 4), ['ingreso', '5', '0.05']);
    expect(lines(csv)[2].split(';').sublist(1, 4), ['ingreso', '100000', '1000.00']);
  });

  test('orden: fecha del movimiento y luego hora de registro, más nuevo primero', () {
    final csv = entriesToCsv([
      entry('viejo', EntryKind.expense, 1, '2026-10-01', ms(1, 9), cat: 'comida'),
      entry('hoy-tarde', EntryKind.expense, 1, '2026-10-08', ms(8, 20), cat: 'comida'),
      entry('hoy-mañana', EntryKind.expense, 1, '2026-10-08', ms(8, 8), cat: 'comida'),
    ], categories: cats, sources: srcs);
    expect(lines(csv).skip(1).map((l) => l.split(';').first), ['hoy-tarde', 'hoy-mañana', 'viejo']);
  });

  test('incluye el nombre de categorías archivadas y de fuentes con tilde', () {
    final csv = entriesToCsv([
      entry('a', EntryKind.expense, 100, '2026-10-08', ms(8, 9), cat: 'viajes'),
      entry('b', EntryKind.income, 100, '2026-10-07', ms(7, 9), src: 'prestamo'),
    ], categories: cats, sources: srcs);
    expect(lines(csv)[1].split(';')[5], 'Viajes');
    expect(lines(csv)[2].split(';').sublist(5, 7), ['Préstamo', 'prestamo']);
  });

  group('escape', () {
    String noteOf(String note) =>
        entriesToCsv([entry('a', EntryKind.expense, 1, '2026-10-08', ms(8, 9), cat: 'comida', note: note)],
            categories: cats, sources: srcs);

    test('punto y coma → entre comillas', () => expect(noteOf('menú; postre'), contains(';"menú; postre";')));

    test('comillas → duplicadas y entre comillas', () {
      expect(noteOf('dijo "barato"'), contains(';"dijo ""barato""";'));
    });

    test('salto de línea → entre comillas (la fila sigue siendo una sola)', () {
      final csv = noteOf('línea 1\nlínea 2');
      expect(csv, contains(';"línea 1\nlínea 2";'));
    });

    test('coma no se escapa (el separador es punto y coma)', () => expect(noteOf('a, b'), contains(';a, b;')));
  });

  test('origin auto y account_label', () {
    final csv = entriesToCsv(
        [entry('a', EntryKind.expense, 1, '2026-10-08', ms(8, 9), cat: 'comida', origin: Origin.auto, account: 'Yape')],
        categories: cats,
        sources: srcs);
    final cols = lines(csv)[1].split(';');
    expect(cols[8], 'auto');
    expect(cols.last, 'Yape');
  });

  test('nombre del archivo con la fecha de hoy', () {
    expect(csvFileName(day(2026, 10, 9)), 'saldoclaro-movimientos-2026-10-09.csv');
  });
}
