import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  EntriesCompanion entry({required EntryKind kind, String? cat, String? src, int cents = 1000}) =>
      EntriesCompanion.insert(
        id: 'e1',
        kind: kind,
        amountCents: cents,
        occurredOn: '2026-10-08',
        categoryId: Value(cat),
        sourceId: Value(src),
        createdAt: 0,
        updatedAt: 0,
      );

  test('v1 siembra 6 categorías y 5 fuentes', () async {
    expect(await db.select(db.categories).get(), hasLength(6));
    expect((await db.select(db.sources).get()).map((s) => s.name), contains('Chamba'));
  });

  test('instalación nueva: la semilla nace con los slots cat:1…cat:6', () async {
    final cats = await (db.select(db.categories)..orderBy([(c) => OrderingTerm(expression: c.sortOrder)])).get();
    expect(cats.map((c) => (c.id, c.colorHex)), [
      ('comida', 'cat:1'), ('transporte', 'cat:2'), ('vivienda', 'cat:3'),
      ('ocio', 'cat:4'), ('salud', 'cat:5'), ('otros', 'cat:6'),
    ]);
  });

  test('customCategorySlot: 7, 8, 9 y luego reutiliza desde 1', () {
    expect([for (var k = 0; k < 12; k++) customCategorySlot(k)],
        ['cat:7', 'cat:8', 'cat:9', 'cat:1', 'cat:2', 'cat:3', 'cat:4', 'cat:5', 'cat:6', 'cat:7', 'cat:8', 'cat:9']);
  });

  test('addCatalogItem: categorías toman el siguiente slot (con vuelta al 1); fuentes, el neutro', () async {
    for (final id in ['ropa', 'mascota', 'regalos', 'deudas']) {
      await db.addCatalogItem(EntryKind.expense, id: id, name: id, icon: 'category');
    }
    await db.setArchived(EntryKind.expense, 'ropa', archived: true); // archivar no libera su slot
    await db.addCatalogItem(EntryKind.expense, id: 'cursos', name: 'cursos', icon: 'category');
    await db.addCatalogItem(EntryKind.income, id: 'bono', name: 'Bono', icon: 'payments');

    final cats = {for (final c in await db.select(db.categories).get()) c.id: c.colorHex};
    expect([for (final id in ['ropa', 'mascota', 'regalos', 'deudas', 'cursos']) cats[id]],
        ['cat:7', 'cat:8', 'cat:9', 'cat:1', 'cat:2']);
    final bono = await (db.select(db.sources)..where((s) => s.id.equals('bono'))).getSingle();
    expect(bono.colorHex, newItemColor);
  });

  test('sin fila de settings = onboarding pendiente', () async {
    expect(await db.watchSettings().first, isNull);
  });

  test('gasto válido se guarda y mapea a Movement', () async {
    await db.into(db.entries).insert(entry(kind: EntryKind.expense, cat: 'comida'));
    final m = (await db.select(db.entries).getSingle()).toMovement();
    expect(m.day, day(2026, 10, 8));
    expect(m.cents, 1000);
  });

  test('gasto con fuente en vez de categoría se rechaza', () async {
    expect(() => db.into(db.entries).insert(entry(kind: EntryKind.expense, src: 'chamba')),
        throwsA(isA<SqliteException>()));
  });

  test('monto 0 se rechaza', () async {
    expect(() => db.into(db.entries).insert(entry(kind: EntryKind.income, src: 'chamba', cents: 0)),
        throwsA(isA<SqliteException>()));
  });

  test('FK activa: categoría inexistente se rechaza', () async {
    expect(() => db.into(db.entries).insert(entry(kind: EntryKind.expense, cat: 'nope')),
        throwsA(isA<SqliteException>()));
  });

  test('settings solo admite id = 1 y ventana de runway 7–90', () async {
    expect(() => db.into(db.settings).insert(SettingsCompanion.insert(id: const Value(2), mode: Mode.variable)),
        throwsA(isA<SqliteException>()));
    expect(
        () => db.into(db.settings).insert(
            SettingsCompanion.insert(id: const Value(1), mode: Mode.variable, runwayWindowDays: const Value(3))),
        throwsA(isA<SqliteException>()));
  });

  test('isoDay ida y vuelta', () {
    expect(parseIsoDay(isoDay(day(2026, 1, 5))), day(2026, 1, 5));
  });
}
