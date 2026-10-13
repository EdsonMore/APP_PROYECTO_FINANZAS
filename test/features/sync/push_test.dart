import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/sync/push.dart';
import 'package:saldo_claro/features/sync/remote.dart';

/// push() de la Fase 3B contra el remoto falso: sin red real.
void main() {
  late AppDatabase db;
  late FakeSyncRemote remote;
  late Pusher pusher;
  var now = 1000;

  setUp(() async {
    now = 1000;
    db = AppDatabase(NativeDatabase.memory(), () => now);
    remote = FakeSyncRemote();
    pusher = Pusher(db, remote);
    await db.completeOnboarding(mode: Mode.variable);
  });
  tearDown(() => db.close());

  Future<void> expense(String id, {String cat = 'comida'}) => db.insertManualEntry(
      id: id, kind: EntryKind.expense, amountCents: 100, day: day(2026, 10, 8), pickId: cat,
      now: DateTime.fromMillisecondsSinceEpoch(now));

  Future<int> pendingCount() async {
    var n = 0;
    for (final t in ['categories', 'sources', 'settings', 'entries', 'budgets']) {
      n += (await db.customSelect('SELECT COUNT(*) AS n FROM $t WHERE synced_at IS NULL OR synced_at < updated_at').getSingle())
          .read<int>('n');
    }
    return n;
  }

  Future<int?> syncedAt(String table, String pk, String id) async => (await db
          .customSelect('SELECT synced_at FROM $table WHERE $pk = ?', variables: [Variable(id)])
          .getSingle())
      .readNullable<int>('synced_at');

  test('1. todo sube: queda synced_at = updated_at y nada pendiente', () async {
    await expense('e1');
    await db.setBudget('comida', 5000);
    final r = await pusher.push();
    expect(r.failed, 0);
    expect(r.stoppedByNetwork, isFalse);
    expect(r.pushed, 6 + 5 + 1 + 1 + 1, reason: '6 categorías, 5 fuentes, ajustes, 1 movimiento, 1 techo');
    expect(await pendingCount(), 0);
    expect(await syncedAt('entries', 'id', 'e1'), 1000);
    expect(remote.rows['entries']!.keys, ['e1']);
  });

  test('lo que viaja: sin user_id, sin synced_at, sin server_updated_at; bools como bool; deleted_at null', () async {
    await expense('e1');
    await pusher.push();
    final cat = remote.rows['categories']!['comida']!;
    expect(cat.containsKey('user_id'), isFalse);
    expect(cat.containsKey('synced_at'), isFalse);
    expect(cat.containsKey('server_updated_at'), isFalse);
    expect(cat['archived'], isFalse);
    expect(cat['is_default'], isTrue);
    expect(cat.containsKey('deleted_at') && cat['deleted_at'] == null, isTrue);
    final settings = remote.rows['settings']!.values.single;
    expect(settings.containsKey('id'), isFalse, reason: 'en el servidor la clave es user_id');
    expect(settings.containsKey('deleted_at'), isFalse, reason: 'settings no tiene deleted_at');
    expect(settings['onboarding_done'], isTrue);
    expect(remote.rows['entries']!['e1']!['occurred_on'], '2026-10-08');
  });

  test('2. una fila con error de datos: las demás suben; esa queda pendiente y en el resumen', () async {
    for (var i = 0; i < 5; i++) {
      await expense('e$i');
    }
    remote.rejectIds = {'e2'};
    final r = await pusher.push();
    expect(r.failed, 1);
    expect(r.errors.single.table, 'entries');
    expect(r.errors.single.id, 'e2');
    expect(r.stoppedByNetwork, isFalse);
    expect(remote.rows['entries']!.keys.toSet(), {'e0', 'e1', 'e3', 'e4'});
    expect(await syncedAt('entries', 'id', 'e2'), isNull);
    expect(await pendingCount(), 1);
  });

  test('3. una categoría que falla arrastra sus movimientos (FK): quedan pendientes, nada se pierde', () async {
    await db.addCatalogItem(EntryKind.expense, id: 'ropa', name: 'Ropa', icon: 'category');
    await expense('e1', cat: 'ropa');
    await expense('e2');
    remote.rejectIds = {'ropa'};
    final r = await pusher.push();
    expect(r.errors.map((e) => (e.table, e.id)), containsAll([('categories', 'ropa'), ('entries', 'e1')]));
    expect(remote.rows['entries']!.keys, ['e2']);
    expect(await syncedAt('entries', 'id', 'e1'), isNull);
    expect(await syncedAt('categories', 'id', 'ropa'), isNull);
  });

  test('4. la red se corta en la 3ª tabla: las 2 primeras quedan marcadas, el resto pendiente', () async {
    await expense('e1');
    remote.networkDownAtTable = 'settings';
    final r = await pusher.push();
    expect(r.stoppedByNetwork, isTrue);
    expect(await syncedAt('categories', 'id', 'comida'), 1000);
    expect(await syncedAt('sources', 'id', 'chamba'), 1000);
    expect(await syncedAt('settings', 'id', '1'), isNull);
    expect(await syncedAt('entries', 'id', 'e1'), isNull);
    expect(remote.upsertCalls.map((c) => c.table), isNot(contains('entries')), reason: 'no sigue intentando sin red');
  });

  test('5. una fila que cambia en el teléfono durante la subida sigue pendiente', () async {
    await expense('e1');
    remote.onUpsert = (table) async {
      if (table == 'categories') {
        now = 9000;
        await db.updateCatalogItem(EntryKind.expense, 'comida', name: 'Comidas', icon: 'restaurant');
      }
    };
    await pusher.push();
    expect(await syncedAt('categories', 'id', 'comida'), 1000, reason: 'se marca con lo que se mandó');
    final updated = (await db.customSelect("SELECT updated_at FROM categories WHERE id = 'comida'").getSingle())
        .read<int>('updated_at');
    expect(updated, 9000);
    expect(await pendingCount(), 1, reason: 'el cambio nuevo sigue esperando');
  });

  test('6. una lápida sube y se borra; con la red caída, la lápida queda', () async {
    await expense('e1');
    await expense('e2');
    await pusher.push();
    now = 2000;
    await db.deleteEntry('e1');
    await db.deleteEntry('e2');
    remote.networkDownOnDelete = 'e2';
    final r = await pusher.push();
    expect(remote.rows['entries']!['e1']!['deleted_at'], 2000);
    expect(r.stoppedByNetwork, isTrue);
    final left = await db.pendingTombstones();
    expect(left.map((t) => t.recordId), ['e2']);
  });

  test('6b. sin red en la primera lápida no intenta las siguientes', () async {
    await expense('e1');
    await expense('e2');
    await pusher.push();
    now = 2000;
    await db.deleteEntry('e1');
    now = 3000;
    await db.deleteEntry('e2');
    remote.networkDownOnDelete = 'e1';
    final r = await pusher.push();
    expect(r.stoppedByNetwork, isTrue);
    expect(remote.log, isNot(contains('delete entries e2')));
    expect((await db.pendingTombstones()).map((t) => t.recordId).toSet(), {'e1', 'e2'});
  });

  test('7. un techo quitado y vuelto a poner viaja con deleted_at null (revive en el servidor)', () async {
    await db.setBudget('comida', 1000);
    await pusher.push();
    now = 2000; // el borrado es posterior a la versión subida (si no, last-write-wins lo ignora)
    await db.removeBudget('comida');
    await pusher.push();
    expect(remote.rows['budgets']!['comida']!['deleted_at'], 2000);
    now = 5000;
    await db.setBudget('comida', 3000);
    await pusher.push();
    final b = remote.rows['budgets']!['comida']!;
    expect(b['deleted_at'], isNull);
    expect(b['cap_cents'], 3000);
  });

  test('8. dos push() a la vez: el segundo recibe el resultado del primero (sin doble subida)', () async {
    await expense('e1');
    final a = pusher.push();
    final b = pusher.push();
    expect(identical(await a, await b), isTrue);
    expect(remote.upsertCalls.where((c) => c.table == 'entries'), hasLength(1));
  });

  test('9. orden fijo: categorías, fuentes, ajustes, movimientos, techos y al final lápidas', () async {
    await expense('e1');
    await expense('e2');
    await db.setBudget('comida', 100);
    await pusher.push();
    await db.deleteEntry('e2');
    await db.updateCatalogItem(EntryKind.expense, 'ocio', name: 'Salidas', icon: 'movie');
    await pusher.push();
    expect(remote.log, [
      'upsert categories', 'upsert sources', 'upsert settings', 'upsert entries', 'upsert budgets',
      'upsert categories', 'delete entries e2',
    ]);
  });

  test('lotes de 200: 450 movimientos son 3 subidas de entries', () async {
    for (var i = 0; i < 450; i++) {
      await expense('e$i');
    }
    final r = await pusher.push();
    expect(remote.upsertCalls.where((c) => c.table == 'entries').map((c) => c.count), [200, 200, 50]);
    expect(r.failed, 0);
  });

  test('10. desconectar: todo vuelve a quedar pendiente y las lápidas se vacían', () async {
    await expense('e1');
    await pusher.push();
    await db.deleteEntry('e1');
    expect(await db.pendingTombstones(), hasLength(1));
    await db.detachSync();
    expect(await db.pendingTombstones(), isEmpty);
    expect(await pendingCount(), greaterThan(0));
    final r = await db.customSelect('SELECT COUNT(*) AS n FROM categories WHERE synced_at IS NOT NULL').getSingle();
    expect(r.read<int>('n'), 0);
  });
}
