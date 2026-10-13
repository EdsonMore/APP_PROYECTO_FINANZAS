import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/settings/csv_exporter.dart';

const cats = [
  Category(updatedAt: 1, id: 'comida', name: 'Comida', icon: 'restaurant', colorHex: '#000', sortOrder: 0, archived: false, isDefault: true),
  Category(updatedAt: 1, id: 'viajes', name: 'Viajes', icon: 'flight', colorHex: '#000', sortOrder: 1, archived: true, isDefault: false),
];
const srcs = [
  Source(updatedAt: 1, id: 'prestamo', name: 'Préstamo', icon: 'account_balance', colorHex: '#000', sortOrder: 0, archived: false, isDefault: true),
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

  test('encabezados separados por punto y coma; al final account_label y las columnas de cuenta (4A)', () {
    final header = lines(entriesToCsv(const [], categories: cats, sources: srcs)).single;
    expect(header,
        'id;kind;amount_cents;amount;occurred_on;category_or_source;category_or_source_id;note;origin;created_at;updated_at;'
        'account_label;account_id;account_name;to_account_id;to_account_name');
  });

  test('fila completa: tipo en español, montos entero y decimal, nombre, id, ISO local', () {
    final csv = entriesToCsv([entry('e1', EntryKind.expense, 1250, '2026-10-08', ms(8, 14, 32), cat: 'comida')],
        categories: cats, sources: srcs);
    expect(lines(csv)[1], 'e1;gasto;1250;12.50;2026-10-08;Comida;comida;;manual;2026-10-08T14:32:00;2026-10-08T14:32:00;;;;;',
        reason: 'sin cuentas, las columnas de cuenta van vacías');
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
    expect(cols[11], 'Yape');
  });

  group('cuentas y transferencias (4A, O2)', () {
    const accounts = [
      Account(id: 'yape', name: 'Yape', icon: 'phone_android', colorHex: '#525252', sortOrder: 0, archived: false,
          isDefault: false, createdAt: 1, updatedAt: 1),
      Account(id: 'bcp', name: 'BCP viejo', icon: 'account_balance', colorHex: '#525252', sortOrder: 1, archived: true,
          isDefault: false, createdAt: 1, updatedAt: 1),
    ];
    TransferRow transfer(String id, String? from, String? to, int cents, String on, int created, {String? note}) =>
        TransferRow(id: id, fromAccountId: from, toAccountId: to, amountCents: cents, occurredOn: on, note: note,
            createdAt: created, updatedAt: created);

    test('movimiento con cuenta (también archivada) y sin cuenta ("Sin asignar")', () {
      final csv = entriesToCsv([
        Entry(id: 'a', kind: EntryKind.expense, amountCents: 1, occurredOn: '2026-10-08', categoryId: 'comida',
            origin: Origin.manual, accountId: 'yape', createdAt: ms(8, 9), updatedAt: ms(8, 9)),
        Entry(id: 'b', kind: EntryKind.expense, amountCents: 1, occurredOn: '2026-10-07', categoryId: 'comida',
            origin: Origin.manual, accountId: 'bcp', createdAt: ms(7, 9), updatedAt: ms(7, 9)),
        entry('c', EntryKind.expense, 1, '2026-10-06', ms(6, 9), cat: 'comida'),
      ], categories: cats, sources: srcs, accounts: accounts);
      final rows = [for (final l in lines(csv).skip(1)) l.split(';').sublist(12)];
      expect(rows, [
        ['yape', 'Yape', '', ''],
        ['bcp', 'BCP viejo', '', ''],
        ['', 'Sin asignar', '', ''],
      ]);
    });

    test('transferencias como filas "transferencia", mezcladas por fecha; "Sin asignar" con id vacío', () {
      final csv = entriesToCsv([entry('e', EntryKind.expense, 500, '2026-10-08', ms(8, 9), cat: 'comida')],
          categories: cats,
          sources: srcs,
          accounts: accounts,
          transfers: [
            transfer('t1', 'yape', null, 1250, '2026-10-09', ms(9, 9), note: 'al bolsillo'),
            transfer('t2', null, 'yape', 300, '2026-10-07', ms(7, 9)),
          ]);
      final l = lines(csv);
      expect([for (final x in l.skip(1)) x.split(';').first], ['t1', 'e', 't2'], reason: 'más nuevo primero');
      expect(l[1], 't1;transferencia;1250;12.50;2026-10-09;;;al bolsillo;manual;2026-10-09T09:00:00;2026-10-09T09:00:00;;'
          'yape;Yape;;Sin asignar');
      expect(l[3].split(';').sublist(12), ['', 'Sin asignar', 'yape', 'Yape']);
    });
  });

  test('nombre del archivo con la fecha de hoy', () {
    expect(csvFileName(day(2026, 10, 9)), 'saldoclaro-movimientos-2026-10-09.csv');
  });
}
