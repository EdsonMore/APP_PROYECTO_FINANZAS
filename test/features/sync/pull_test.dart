import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/sync/pull.dart';
import 'package:saldo_claro/features/sync/push.dart';
import 'package:saldo_claro/features/sync/remote.dart';

/// pull() de la Fase 3C contra el remoto falso (SPEC §Sync, tabla de reglas).
void main() {
  late AppDatabase db;
  late FakeSyncRemote remote;
  late Puller puller;
  var now = 1000;

  setUp(() async {
    now = 1000;
    db = AppDatabase(NativeDatabase.memory(), () => now);
    remote = FakeSyncRemote();
    puller = Puller(db, remote);
    await db.completeOnboarding(mode: Mode.variable);
    // El servidor ya tiene lo de este teléfono (semilla y ajustes).
    await Pusher(db, remote).push();
  });
  tearDown(() => db.close());

  /// Otro teléfono escribe en el servidor (formato del servidor).
  Future<void> serverEntry(String id, int updatedAt, {String cat = 'comida', int cents = 500, int? deletedAt}) =>
      remote.upsert('entries', [
        {
          'id': id, 'kind': 'expense', 'amount_cents': cents, 'occurred_on': '2026-10-08', 'category_id': cat,
          'source_id': null, 'note': null, 'origin': 'manual', 'account_label': null, 'account_id': null,
          'created_at': updatedAt, 'updated_at': updatedAt, 'deleted_at': deletedAt,
        }
      ]);

  Future<void> serverCategory(String id, String name, int updatedAt) => remote.upsert('categories', [
        {
          'id': id, 'name': name, 'icon': 'category', 'color_hex': 'cat:7', 'sort_order': 9, 'archived': false,
          'is_default': false, 'updated_at': updatedAt, 'deleted_at': null,
        }
      ]);

  Future<void> localExpense(String id, {String cat = 'comida'}) => db.insertManualEntry(
      id: id, kind: EntryKind.expense, amountCents: 100, day: day(2026, 10, 8), pickId: cat,
      now: DateTime.fromMillisecondsSinceEpoch(now));

  Future<Map<String, Object?>?> row(String table, String key, String id) async =>
      (await db.customSelect('SELECT * FROM $table WHERE $key = ?', variables: [Variable(id)]).getSingleOrNull())?.data;

  Future<List<String>> tombstones() async =>
      [for (final r in await db.customSelect('SELECT entity, row_id FROM tombstones ORDER BY 1, 2').get()) '${r.data['entity']}/${r.data['row_id']}'];

  Future<int> pendingEntries() async =>
      (await db.customSelect('SELECT COUNT(*) AS n FROM entries WHERE synced_at IS NULL OR synced_at < updated_at').getSingle())
          .read<int>('n');

  test('baja lo nuevo de otro teléfono: entra sincronizado (no pendiente) y guarda los cursores', () async {
    await serverEntry('b1', 2000);
    final r = await puller.pull();
    expect(r.applied, greaterThan(0));
    final e = (await row('entries', 'id', 'b1'))!;
    expect((e['amount_cents'], e['updated_at'], e['synced_at']), (500, 2000, 2000));
    expect(await pendingEntries(), 0);
    final cursors = await db.readSyncCursors();
    expect(cursors.keys.toSet(), AppDatabase.syncTables.keys.toSet(), reason: 'las 5 tablas, aunque no bajara nada');
    expect(cursors['entries'], isNotEmpty);
  });

  test('remota más nueva pisa la local aunque esté pendiente', () async {
    await localExpense('e1'); // updated_at 1000, pendiente
    await serverEntry('e1', 3000, cents: 999);
    await puller.pull();
    final e = (await row('entries', 'id', 'e1'))!;
    expect((e['amount_cents'], e['updated_at'], e['synced_at']), (999, 3000, 3000));
  });

  test('remota más vieja que la local: se ignora y la local sigue pendiente (la sube el push)', () async {
    now = 5000;
    await localExpense('e1');
    await serverEntry('e1', 3000, cents: 999);
    await puller.pull();
    final e = (await row('entries', 'id', 'e1'))!;
    expect((e['amount_cents'], e['updated_at'], e['synced_at']), (100, 5000, null));
  });

  test('empate (mismo updated_at, distinto contenido): gana la del servidor', () async {
    await localExpense('e1'); // 1000
    await serverEntry('e1', 1000, cents: 777);
    await puller.pull();
    final e = (await row('entries', 'id', 'e1'))!;
    expect((e['amount_cents'], e['synced_at']), (777, 1000));
  });

  test('una lápida que baja borra la fila local sin dejar lápida nueva', () async {
    await serverEntry('b1', 2000);
    await puller.pull();
    await remote.markDeleted('entries', 'b1', 2500);
    await puller.pull();
    expect(await row('entries', 'id', 'b1'), isNull);
    expect(await tombstones(), isEmpty);
  });

  test('lápida de algo que este teléfono nunca tuvo: no hace nada', () async {
    await serverEntry('b1', 2000, deletedAt: 2000);
    await puller.pull();
    expect(await row('entries', 'id', 'b1'), isNull);
  });

  test('borrado local más nuevo que la versión remota: no se recrea y la lápida sigue', () async {
    await serverEntry('b1', 2000);
    await puller.pull();
    now = 4000;
    await db.deleteEntry('b1'); // lápida 4000
    await puller.pull();
    expect(await row('entries', 'id', 'b1'), isNull);
    expect(await tombstones(), ['entries/b1']);
  });

  test('edición remota posterior al borrado local: la fila vuelve y la lápida se descarta (D6)', () async {
    await serverEntry('b1', 2000);
    await puller.pull();
    now = 3000;
    await db.deleteEntry('b1'); // lápida 3000
    await serverEntry('b1', 3500, cents: 1234);
    await puller.pull();
    expect((await row('entries', 'id', 'b1'))!['amount_cents'], 1234);
    expect(await tombstones(), isEmpty);
  });

  test('empate entre lápida local y versión remota viva: gana el servidor (si no, nunca se volvería a bajar)', () async {
    await serverEntry('b1', 2000);
    await puller.pull();
    now = 3000;
    await db.deleteEntry('b1'); // lápida 3000
    await serverEntry('b1', 3000, cents: 4321);
    await puller.pull();
    expect((await row('entries', 'id', 'b1'))!['amount_cents'], 4321);
    expect(await tombstones(), isEmpty);
  });

  test('techos: quitado en el servidor después del cambio local → se quita; antes → se queda', () async {
    await db.setBudget('comida', 1000); // 1000
    await db.setBudget('ocio', 2000);
    await Pusher(db, remote).push();
    await puller.pull();
    now = 1500;
    await db.setBudget('ocio', 2500); // local 1500, pendiente
    await remote.markDeleted('budgets', 'comida', 1200);
    await remote.markDeleted('budgets', 'ocio', 1200);
    await puller.pull();
    expect(await row('budgets', 'category_id', 'comida'), isNull);
    expect((await row('budgets', 'category_id', 'ocio'))!['cap_cents'], 2500);
  });

  test('mismo nombre con otro id: la local pasa a "Ropa (2)" y queda pendiente; la remota entra como "Ropa"', () async {
    await db.addCatalogItem(EntryKind.expense, id: 'ropa-a', name: 'Ropa', icon: 'category');
    now = 1500;
    await serverCategory('ropa-b', 'Ropa', 1400);
    await serverCategory('ropa-c', 'Ropa (2)', 1400); // el siguiente libre es (3)
    // ropa-b desplaza a la local a 'Ropa (2)'; ropa-c ('Ropa (2)') la desplaza a 'Ropa (3)'.
    await puller.pull();
    expect((await row('categories', 'id', 'ropa-b'))!['name'], 'Ropa');
    expect((await row('categories', 'id', 'ropa-c'))!['name'], 'Ropa (2)');
    final mine = (await row('categories', 'id', 'ropa-a'))!;
    expect(mine['name'], 'Ropa (3)');
    expect(mine['synced_at'], isNull, reason: 'el cambio de nombre se sube');
    expect(mine['updated_at'], 1501, reason: 'dos renombres: MAX(ahora, anterior + 1)');
  });

  test('cursor: la siguiente bajada pide desde cursor − 10 s y releer el solapamiento no cambia nada', () async {
    await serverEntry('b1', 2000);
    await puller.pull();
    final cursor = (await db.readSyncCursors())['entries']!;
    remote.pullLog.clear();
    final r = await puller.pull();
    final from = remote.pullLog.firstWhere((p) => p.table == 'entries').from!;
    expect(DateTime.parse(cursor).difference(DateTime.parse(from)), pullOverlap);
    expect((await row('entries', 'id', 'b1'))!['synced_at'], 2000);
    expect(await pendingEntries(), 0);
    expect(r.skipped, 0);
  });

  test('descarga hijos antes que padres y aplica padres antes que hijos: un movimiento con categoría nueva entra', () async {
    await serverCategory('mascotas', 'Mascotas', 2000);
    await serverEntry('b1', 2100, cat: 'mascotas');
    remote.pullLog.clear();
    await puller.pull();
    expect({for (final p in remote.pullLog) p.table}.toList(), ['transfers', 'budgets', 'entries', 'settings', 'accounts', 'sources', 'categories']);
    expect((await row('entries', 'id', 'b1'))!['category_id'], 'mascotas');
  });

  test('se cae la red a mitad de la descarga: no se aplica nada y el cursor no se mueve', () async {
    await serverEntry('b1', 2000);
    remote.networkDownOnPull = 'sources';
    await expectLater(puller.pull(), throwsA(isA<NetworkFailure>()));
    expect(await row('entries', 'id', 'b1'), isNull);
    expect(await db.readSyncCursors(), isEmpty);
  });

  test('una fila remota que no se puede aplicar se salta (cuenta) y el resto entra; el cursor avanza', () async {
    await serverEntry('b1', 2000);
    await serverEntry('b2', 2001, cents: 0); // el servidor no la frenaría en el falso; la base local sí (CHECK)
    final r = await puller.pull();
    expect(r.skipped, 1);
    expect(await row('entries', 'id', 'b1'), isNotNull);
    expect(await row('entries', 'id', 'b2'), isNull);
    expect((await db.readSyncCursors())['entries'], isNotEmpty);
  });

  test('paginación: con páginas de 2, bajan las 7 filas', () async {
    for (var i = 0; i < 7; i++) {
      await serverEntry('p$i', 2000 + i);
    }
    final r = await Puller(db, remote, pageSize: 2).pull();
    expect(r.skipped, 0);
    expect(await db.select(db.entries).get(), hasLength(7));
  });

  test('ajustes: la versión remota más nueva entra en la fila 1, con booleanos de SQLite', () async {
    await remote.upsert('settings', [
      {
        'mode': 'survival', 'space_name': 'Casa', 'runway_window_days': 21, 'income_window_days': 60,
        'opening_balance_cents': null, 'opening_balance_at': null, 'onboarding_done': true, 'updated_at': 9000,
      }
    ]);
    await puller.pull();
    final s = (await row('settings', 'id', '1'))!;
    expect((s['mode'], s['space_name'], s['runway_window_days'], s['onboarding_done'], s['synced_at']),
        ('survival', 'Casa', 21, 1, 9000));
  });

  test('join: los ajustes de la nube ganan aunque los locales sean más nuevos (D5)', () async {
    await remote.upsert('settings', [
      {'mode': 'stable', 'space_name': 'Nube', 'runway_window_days': 14, 'income_window_days': 30, 'onboarding_done': true, 'updated_at': 1500}
    ]);
    now = 8000;
    await db.setSpaceName('Teléfono');
    await puller.pull(mode: PullMode.join);
    final s = (await row('settings', 'id', '1'))!;
    expect((s['space_name'], s['updated_at'], s['synced_at']), ('Nube', 1500, 1500));
  });

  test('replace: lo local sincronizable se borra y queda exactamente lo de la nube (D5 "usar la nube")', () async {
    await serverEntry('b1', 2000);
    final cloud = FakeSyncRemote();
    cloud.rows.addAll(remote.rows);
    await db.addCatalogItem(EntryKind.expense, id: 'ropa', name: 'Ropa', icon: 'category');
    await localExpense('mio', cat: 'ropa');
    await db.setBudget('ropa', 5000);
    final r = await Puller(db, cloud).pull(mode: PullMode.replace);
    expect(r.skipped, 0);
    expect([for (final e in await db.select(db.entries).get()) e.id], ['b1']);
    expect(await row('categories', 'id', 'ropa'), isNull);
    expect(await db.select(db.budgets).get(), isEmpty);
    expect(await tombstones(), isEmpty);
    expect((await db.select(db.settings).getSingle()).onboardingDone, isTrue);
  });

  test('categorías y fuentes con deleted_at (no debería pasar): se ignoran, la local no se borra', () async {
    await serverCategory('rara', 'Rara', 1500);
    await puller.pull();
    expect(await row('categories', 'id', 'rara'), isNotNull);
    await remote.upsert('categories', [
      {
        'id': 'rara', 'name': 'Rara', 'icon': 'category', 'color_hex': 'cat:7', 'sort_order': 9, 'archived': false,
        'is_default': false, 'updated_at': 2000, 'deleted_at': 2000,
      }
    ]);
    await puller.pull();
    expect(await row('categories', 'id', 'rara'), isNotNull);
  });

  test('detachSync borra los cursores: la próxima cuenta baja todo desde cero', () async {
    await puller.pull();
    expect(await db.readSyncCursors(), isNotEmpty);
    await db.detachSync();
    expect(await db.readSyncCursors(), isEmpty);
  });
}
