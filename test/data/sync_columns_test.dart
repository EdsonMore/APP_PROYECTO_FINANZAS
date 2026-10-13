import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';

/// Fase 3E: columnas de sync (updated_at, synced_at) y lápidas.
/// Las columnas se leen con SQL directo: el contrato es el esquema, no la API.
void main() {
  late AppDatabase db;
  var now = 1000; // reloj inyectado, epoch ms
  setUp(() {
    now = 1000;
    db = AppDatabase(NativeDatabase.memory(), () => now);
  });
  tearDown(() => db.close());

  Future<({int updated, int? synced})> stamps(String table, String where, List<Object> args) async {
    final r = await db
        .customSelect('SELECT updated_at, synced_at FROM $table WHERE $where', variables: [for (final a in args) Variable(a)])
        .getSingle();
    return (updated: r.read<int>('updated_at'), synced: r.readNullable<int>('synced_at'));
  }

  Future<void> markSynced(String table, String where, List<Object> args) => db.customUpdate(
      'UPDATE $table SET synced_at = updated_at WHERE $where',
      variables: [for (final a in args) Variable(a)]);

  Future<List<(String, String, int)>> tombstones() async => [
        for (final r in await db.customSelect('SELECT entity, row_id, deleted_at FROM tombstones ORDER BY 1, 2').get())
          (r.read<String>('entity'), r.read<String>('row_id'), r.read<int>('deleted_at')),
      ];

  Future<void> expense(String id, {String cat = 'comida'}) => db.insertManualEntry(
      id: id, kind: EntryKind.expense, amountCents: 100, day: day(2026, 10, 8), pickId: cat, now: DateTime.fromMillisecondsSinceEpoch(now));

  test('instalación nueva: la semilla nace con la hora del reloj y sin sincronizar; sin lápidas', () async {
    expect(await stamps('categories', 'id = ?', ['comida']), (updated: 1000, synced: null));
    expect(await stamps('sources', 'id = ?', ['chamba']), (updated: 1000, synced: null));
    expect(await tombstones(), isEmpty);
  });

  group('cada escritura pone updated_at', () {
    // (nombre, tabla, where, args, preparación, escritura)
    final cases = <(String, String, String, List<Object>, Future<void> Function(), Future<void> Function())>[
      ('completeOnboarding (repetido)', 'settings', 'id = ?', [1], () => db.completeOnboarding(mode: Mode.stable),
          () => db.completeOnboarding(mode: Mode.variable)),
      ('setMode', 'settings', 'id = ?', [1], () => db.completeOnboarding(mode: Mode.stable), () => db.setMode(Mode.survival)),
      ('setSpaceName', 'settings', 'id = ?', [1], () => db.completeOnboarding(mode: Mode.stable), () => db.setSpaceName('Casa')),
      ('setRunwayWindow', 'settings', 'id = ?', [1], () => db.completeOnboarding(mode: Mode.stable),
          () => db.setRunwayWindow(21)),
      ('setOpeningBalance', 'settings', 'id = ?', [1], () => db.completeOnboarding(mode: Mode.stable),
          () => db.setOpeningBalance(cents: 5000, at: DateTime(2026, 10, 8))),
      ('updateCatalogItem (categoría)', 'categories', 'id = ?', ['comida'], () async {},
          () => db.updateCatalogItem(EntryKind.expense, 'comida', name: 'Comidas', icon: 'restaurant')),
      ('updateCatalogItem (fuente)', 'sources', 'id = ?', ['chamba'], () async {},
          () => db.updateCatalogItem(EntryKind.income, 'chamba', name: 'Chambita', icon: 'payments')),
      ('setArchived (categoría)', 'categories', 'id = ?', ['ocio'], () async {},
          () => db.setArchived(EntryKind.expense, 'ocio', archived: true)),
      ('setArchived (fuente)', 'sources', 'id = ?', ['venta'], () async {},
          () => db.setArchived(EntryKind.income, 'venta', archived: true)),
      ('setBudget (reemplaza)', 'budgets', 'category_id = ?', ['comida'], () => db.setBudget('comida', 10000),
          () => db.setBudget('comida', 20000)),
    ];

    for (final (name, table, where, args, prepare, write) in cases) {
      test('$name: reloj adelante → ahora; quieto o atrás → anterior + 1; vuelve a quedar pendiente', () async {
        await prepare();
        final first = await stamps(table, where, args);
        await markSynced(table, where, args);

        now = first.updated + 500; // reloj adelante
        await write();
        final a = await stamps(table, where, args);
        expect(a.updated, first.updated + 500);
        expect(a.synced, first.updated, reason: 'synced_at no lo toca la escritura');
        expect(a.synced! < a.updated, isTrue, reason: 'pendiente de subir');

        // reloj quieto (mismo ms): igual crece, si no el cambio quedaría como "ya subido"
        await write();
        expect((await stamps(table, where, args)).updated, a.updated + 1);

        now = 1; // reloj hacia atrás
        await write();
        expect((await stamps(table, where, args)).updated, a.updated + 2);
      });
    }

    test('inserciones: addCatalogItem, setBudget nuevo, completeOnboarding nuevo e insertManualEntry usan la hora', () async {
      now = 7000;
      await db.addCatalogItem(EntryKind.expense, id: 'ropa', name: 'Ropa', icon: 'category');
      await db.addCatalogItem(EntryKind.income, id: 'bono', name: 'Bono', icon: 'payments');
      await db.setBudget('salud', 3000);
      await db.completeOnboarding(mode: Mode.variable);
      await expense('e1');
      expect(await stamps('categories', 'id = ?', ['ropa']), (updated: 7000, synced: null));
      expect(await stamps('sources', 'id = ?', ['bono']), (updated: 7000, synced: null));
      expect(await stamps('budgets', 'category_id = ?', ['salud']), (updated: 7000, synced: null));
      expect(await stamps('settings', 'id = ?', [1]), (updated: 7000, synced: null));
      expect(await stamps('entries', 'id = ?', ['e1']), (updated: 7000, synced: null));
    });
  });

  test('invariante: después de todas las escrituras ninguna fila queda con updated_at = 0', () async {
    await db.completeOnboarding(mode: Mode.stable, spaceName: 'Casa');
    await db.setMode(Mode.variable);
    await db.setSpaceName(null);
    await db.setRunwayWindow(30);
    await db.setOpeningBalance(cents: 1000, at: DateTime(2026, 10, 1));
    await db.addCatalogItem(EntryKind.expense, id: 'ropa', name: 'Ropa', icon: 'category');
    await db.addCatalogItem(EntryKind.income, id: 'bono', name: 'Bono', icon: 'payments');
    await db.updateCatalogItem(EntryKind.expense, 'ropa', name: 'Ropa y zapatos', icon: 'category');
    await db.updateCatalogItem(EntryKind.income, 'bono', name: 'Bonos', icon: 'payments');
    await db.setArchived(EntryKind.expense, 'ropa', archived: true);
    await db.setArchived(EntryKind.expense, 'ropa', archived: false);
    await db.setArchived(EntryKind.income, 'bono', archived: true);
    await db.setBudget('comida', 1000);
    await db.setBudget('comida', 2000);
    await db.setBudget('ocio', 500);
    await db.removeBudget('ocio');
    await expense('e1');
    await expense('e2');
    await db.deleteEntry('e2');
    for (final t in ['categories', 'sources', 'entries', 'budgets', 'settings']) {
      final n = (await db.customSelect('SELECT COUNT(*) AS n FROM $t WHERE updated_at = 0').getSingle()).read<int>('n');
      expect(n, 0, reason: t);
    }
  });

  group('lápidas', () {
    test('borrar un movimiento que nunca se sincronizó no deja lápida', () async {
      await expense('e1');
      expect(await db.deleteEntry('e1'), 1);
      expect(await tombstones(), isEmpty);
    });

    test('borrar un movimiento sincronizado deja lápida con la hora del borrado', () async {
      await expense('e1');
      await markSynced('entries', 'id = ?', ['e1']);
      now = 5000;
      expect(await db.deleteEntry('e1'), 1);
      expect(await tombstones(), [('entries', 'e1', 5000)]);
      expect(await db.select(db.entries).get(), isEmpty, reason: 'el borrado local es real');
    });

    test('borrar un id que no existe no deja lápida', () async {
      expect(await db.deleteEntry('nada'), 0);
      expect(await tombstones(), isEmpty);
    });

    test('quitar un techo sincronizado deja lápida; uno sin sincronizar no', () async {
      await db.setBudget('comida', 1000);
      await db.setBudget('ocio', 1000);
      await markSynced('budgets', 'category_id = ?', ['comida']);
      now = 6000;
      await db.removeBudget('comida');
      await db.removeBudget('ocio');
      expect(await tombstones(), [('budgets', 'comida', 6000)]);
    });

    test('volver a poner un techo quitado borra su lápida (el techo nuevo gana)', () async {
      await db.setBudget('comida', 1000);
      await markSynced('budgets', 'category_id = ?', ['comida']);
      await db.removeBudget('comida');
      expect(await tombstones(), hasLength(1));
      await db.setBudget('comida', 3000);
      expect(await tombstones(), isEmpty);
      expect((await db.select(db.budgets).getSingle()).capCents, 3000);
    });

    group('atómico: si la lápida falla, no se borra ni se cambia nada', () {
      // Un trigger de SQLite hace fallar cualquier escritura en tombstones.
      Future<void> breakTombstones() async {
        await db.customStatement(
            "CREATE TRIGGER fail_ins BEFORE INSERT ON tombstones BEGIN SELECT RAISE(ABORT, 'falla simulada'); END");
        await db.customStatement(
            "CREATE TRIGGER fail_del BEFORE DELETE ON tombstones BEGIN SELECT RAISE(ABORT, 'falla simulada'); END");
      }

      test('deleteEntry', () async {
        await expense('e1');
        await markSynced('entries', 'id = ?', ['e1']);
        await breakTombstones();
        await expectLater(db.deleteEntry('e1'), throwsA(isA<Exception>()));
        expect(await db.select(db.entries).get(), hasLength(1), reason: 'el movimiento sigue');
      });

      test('removeBudget', () async {
        await db.setBudget('comida', 1000);
        await markSynced('budgets', 'category_id = ?', ['comida']);
        await breakTombstones();
        await expectLater(db.removeBudget('comida'), throwsA(isA<Exception>()));
        expect(await db.select(db.budgets).get(), hasLength(1), reason: 'el techo sigue');
      });

      test('setBudget', () async {
        await db.setBudget('comida', 1000);
        await markSynced('budgets', 'category_id = ?', ['comida']);
        await db.removeBudget('comida');
        await breakTombstones();
        await expectLater(db.setBudget('comida', 3000), throwsA(isA<Exception>()));
        expect(await db.select(db.budgets).get(), isEmpty, reason: 'no queda un techo con la lápida viva');
        expect(await tombstones(), hasLength(1));
      });
    });

    test('la lápida de un techo no afecta a la de un movimiento con el mismo id', () async {
      await expense('comida'); // id de movimiento igual al de la categoría, a propósito
      await markSynced('entries', 'id = ?', ['comida']);
      await db.deleteEntry('comida');
      await db.setBudget('comida', 1000);
      expect(await tombstones(), [('entries', 'comida', 1000)]);
    });
  });
}
