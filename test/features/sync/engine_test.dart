import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/sync/auth_gateway.dart';
import 'package:saldo_claro/features/sync/fake_auth_gateway.dart';
import 'package:saldo_claro/features/sync/push.dart';
import 'package:saldo_claro/features/sync/remote.dart';
import 'package:saldo_claro/features/sync/status.dart';
import 'package:saldo_claro/features/sync/sync_engine.dart';

/// Cuenta las peticiones en vuelo: si alguna vez hay 2, hubo dos sync() a la vez
/// (dentro de un mismo sync las peticiones van una detrás de otra).
class CountingRemote implements SyncRemote {
  CountingRemote(this.inner);
  final FakeSyncRemote inner;
  var _inFlight = 0;
  var maxInFlight = 0;

  Future<T> _count<T>(Future<T> Function() f) async {
    maxInFlight = ++_inFlight > maxInFlight ? _inFlight : maxInFlight;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 1));
      return await f();
    } finally {
      _inFlight--;
    }
  }

  @override
  Future<Set<String>> upsert(String table, List<Map<String, Object?>> rows) => _count(() => inner.upsert(table, rows));
  @override
  Future<bool> markDeleted(String table, String id, int deletedAt) => _count(() => inner.markDeleted(table, id, deletedAt));
  @override
  Future<List<Map<String, Object?>>> fetch(String table, List<String> keys) => _count(() => inner.fetch(table, keys));
  @override
  Future<List<Map<String, Object?>>> pullPage(String table, {String? from, bool inclusive = false, int limit = pullPageSize}) =>
      _count(() => inner.pullPage(table, from: from, inclusive: inclusive, limit: limit));
}

void main() {
  late AppDatabase db;
  late FakeSyncRemote remote;
  late FakeAuthGateway auth;
  late SyncEngine engine;
  var now = 1000;

  Future<AppDatabase> phone() async {
    final d = AppDatabase(NativeDatabase.memory(), () => now);
    await d.completeOnboarding(mode: Mode.variable);
    return d;
  }

  Future<void> expense(AppDatabase d, String id) => d.insertManualEntry(
      id: id, kind: EntryKind.expense, amountCents: 100, day: day(2026, 10, 8), pickId: 'comida',
      now: DateTime.fromMillisecondsSinceEpoch(now));

  /// Otro teléfono ya subió su semilla, sus ajustes y [ids] a la cuenta.
  Future<void> cloudHas(List<String> ids) async {
    final other = await phone();
    for (final id in ids) {
      await expense(other, id);
    }
    await Pusher(other, remote).push();
    await other.close();
  }

  Future<List<String>> entryIds(AppDatabase d) async => [for (final e in await d.select(d.entries).get()) e.id]..sort();

  setUp(() async {
    now = 1000;
    db = await phone();
    remote = FakeSyncRemote();
    auth = FakeAuthGateway()..addAccount('ana@correo.com', 'secreto1');
    await auth.signIn('ana@correo.com', 'secreto1');
    engine = SyncEngine(db, remote, auth, clock: () => DateTime.fromMillisecondsSinceEpoch(now));
  });
  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  test('sin sesión: off y ninguna petición', () async {
    await auth.signOut();
    await engine.idle;
    expect((await engine.sync()).state, SyncState.off);
    expect(remote.log, isEmpty);
  });

  test('siempre primero el pull y después el push', () async {
    await engine.sync(); // primer contacto, nube vacía: sube todo
    await expense(db, 'e1');
    remote.log.clear();
    expect((await engine.sync()).state, SyncState.ok);
    final firstUpsert = remote.log.indexWhere((l) => l.startsWith('upsert'));
    expect(remote.log.lastIndexWhere((l) => l.startsWith('pull')), lessThan(firstUpsert));
  });

  test('candado: un sync corriendo + uno esperando; los demás reciben el que espera; nunca dos a la vez', () async {
    final counting = CountingRemote(remote);
    final e = SyncEngine(db, counting, auth);
    addTearDown(e.dispose);
    final s1 = e.sync();
    await Future<void>.delayed(Duration.zero); // s1 ya está corriendo
    final s2 = e.sync();
    final s3 = e.sync();
    final s4 = e.sync();
    expect(identical(s2, s3) && identical(s3, s4), isTrue);
    expect(identical(s1, s2), isFalse);
    await Future.wait([s1, s2, s3, s4]);
    expect(remote.log.where((l) => l == 'pull budgets'), hasLength(2), reason: 'dos corridas, no cuatro');
    expect(counting.maxInFlight, 1);
  });

  test('sin red al bajar: offline, no sube nada y conserva la última sincronización buena', () async {
    await engine.sync();
    final last = engine.status.lastSyncAt;
    expect(last, isNotNull);
    await expense(db, 'e1');
    now = 5000;
    remote.offline = true;
    remote.upsertCalls.clear();
    final s = await engine.sync();
    expect((s.state, s.lastSyncAt), (SyncState.offline, last));
    expect(remote.upsertCalls, isEmpty);
  });

  test('sin red al subir: offline, pero lo que bajó queda aplicado', () async {
    await engine.sync();
    final other = await phone();
    await expense(other, 'b1');
    await Pusher(other, remote).push();
    await other.close();
    await expense(db, 'mio');
    remote.networkDownAtTable = 'entries';
    expect((await engine.sync()).state, SyncState.offline);
    expect(await entryIds(db), contains('b1'));
  });

  test('una fila rechazada por datos: issues(1)', () async {
    await engine.sync();
    await expense(db, 'mala');
    remote.rejectIds = {'mala'};
    final s = await engine.sync();
    expect((s.state, s.issues), (SyncState.issues, 1));
  });

  test('sesión vencida y refresh ok: reintenta una vez y queda ok', () async {
    await engine.sync();
    remote.sessionExpired = true;
    auth.onRefresh = () => remote.sessionExpired = false;
    expect((await engine.sync()).state, SyncState.ok);
    expect(auth.calls.where((c) => c == 'refreshSession'), hasLength(1));
  });

  test('refresh "ok" pero la sesión sigue vencida: un solo reintento y needsLogin (sin bucle)', () async {
    await engine.sync();
    remote.sessionExpired = true;
    expect((await engine.sync()).state, SyncState.needsLogin);
    expect(auth.calls.where((c) => c == 'refreshSession'), hasLength(1));
  });

  test('sesión vencida y refresh inválido: needsLogin, sesión local cerrada, detachSync; los datos siguen', () async {
    await engine.sync();
    await expense(db, 'e1');
    remote.sessionExpired = true;
    auth.refreshOutcome = RefreshOutcome.invalid;
    expect((await engine.sync()).state, SyncState.needsLogin);
    await engine.idle;
    expect(auth.currentEmail, isNull);
    expect(auth.calls, contains('signOutLocal'));
    expect(engine.status.state, SyncState.needsLogin, reason: 'no lo pisa el off del cierre de sesión');
    expect(await db.readSyncCursors(), isEmpty);
    expect(await entryIds(db), ['e1']);
    expect(await db.neverSynced(), isTrue, reason: 'todo pendiente para la próxima cuenta');
  });

  test('sesión vencida y refresh sin red: offline (la sesión puede seguir valiendo)', () async {
    await engine.sync();
    remote.sessionExpired = true;
    auth.refreshOutcome = RefreshOutcome.offline;
    expect((await engine.sync()).state, SyncState.offline);
    expect(auth.currentEmail, isNotNull);
  });

  group('primer contacto con la cuenta (D5)', () {
    test('nube vacía: sube todo, como "Crear cuenta"', () async {
      await expense(db, 'e1');
      expect((await engine.sync()).state, SyncState.ok);
      expect(remote.rows['categories'], hasLength(6));
      expect(remote.rows['entries']!.keys, ['e1']);
      expect(await db.hasPending(), isFalse);
    });

    test('teléfono solo con la semilla: usa la nube sin preguntar', () async {
      await cloudHas(['b1', 'b2']);
      expect((await engine.sync()).state, SyncState.ok);
      expect(await entryIds(db), ['b1', 'b2']);
      expect(await db.hasPending(), isFalse);
    });

    test('teléfono con datos propios: needsChoice, no sube nada y no vuelve a pedir hasta elegir', () async {
      await cloudHas(['b1']);
      await expense(db, 'mio');
      remote.upsertCalls.clear();
      expect((await engine.sync()).state, SyncState.needsChoice);
      expect(remote.upsertCalls, isEmpty);
      remote.pullLog.clear();
      expect((await engine.sync()).state, SyncState.needsChoice);
      expect(remote.pullLog, isEmpty, reason: 'sin red mientras espera la elección');
      await engine.pushOnly();
      expect(remote.upsertCalls, isEmpty, reason: 'ir al background tampoco sube');
    });

    test('"Unir": quedan los dos conjuntos y los ajustes de la nube ganan', () async {
      await cloudHas(['b1']);
      now = 9000;
      await db.setSpaceName('Teléfono');
      await expense(db, 'mio');
      await engine.sync();
      expect((await engine.join()).state, SyncState.ok);
      expect(await entryIds(db), ['b1', 'mio']);
      expect(remote.rows['entries']!.keys.toSet(), {'b1', 'mio'});
      expect((await db.select(db.settings).getSingle()).spaceName, isNull, reason: 'el de la nube');
    });

    test('"Usar solo los de la nube": lo propio del teléfono se va', () async {
      await cloudHas(['b1']);
      await expense(db, 'mio');
      await engine.sync();
      expect((await engine.useCloud()).state, SyncState.ok);
      expect(await entryIds(db), ['b1']);
      expect(remote.rows['entries']!.keys, ['b1']);
    });

    test('V2: si se cierra la app sin elegir, al volver a abrir se pregunta de nuevo (nada persistido)', () async {
      await cloudHas(['b1']);
      await expense(db, 'mio');
      expect((await engine.sync()).state, SyncState.needsChoice);
      final reopened = SyncEngine(db, remote, auth);
      addTearDown(reopened.dispose);
      expect((await reopened.sync()).state, SyncState.needsChoice);
      expect(await entryIds(db), ['mio'], reason: 'nada se aplicó');
    });
  });

  group('el servidor descarta lo que sube este teléfono (su reloj va atrasado)', () {
    /// El cursor queda bien por delante de la versión del servidor (más que
    /// el solapamiento): sin el arreglo, el teléfono nunca la volvería a bajar.
    Future<void> moveCursorPast() async {
      remote.tickSeconds(60);
      final other = await phone();
      await other.setBudget('ocio', 100);
      await Pusher(other, remote).push();
      await other.close();
      await engine.sync();
    }

    test('techo quitado en la nube con reloj adelantado y vuelto a poner aquí: el teléfono termina como el servidor',
        () async {
      await db.setBudget('comida', 1000);
      await engine.sync();
      await remote.markDeleted('budgets', 'comida', 9000); // otro teléfono, reloj adelantado
      await engine.sync();
      expect(await db.select(db.budgets).get(), isEmpty);
      await moveCursorPast();
      now = 2000;
      await db.setBudget('comida', 5000); // versión 2000 < 9000: el servidor la descarta
      expect((await engine.sync()).state, SyncState.ok);
      expect((await db.select(db.budgets).get()).map((b) => b.categoryId), ['ocio'], reason: 'como el servidor');
      expect(await db.hasPending(), isFalse);
    });

    test('lápida descartada (el servidor tiene una edición más nueva): el movimiento vuelve con esa edición', () async {
      await expense(db, 'e1');
      await engine.sync();
      final edited = Map.of(remote.rows['entries']!['e1']!)..['updated_at'] = 9000;
      edited['amount_cents'] = 4321;
      await remote.upsert('entries', [edited]);
      await moveCursorPast();
      // Este teléfono aún no bajó la edición si la borra justo antes de sincronizar:
      await db.customUpdate("UPDATE entries SET updated_at = 1500, synced_at = 1500, amount_cents = 100 WHERE id = 'e1'");
      now = 2000;
      await db.deleteEntry('e1');
      expect((await engine.sync()).state, SyncState.ok);
      expect((await db.select(db.entries).getSingle()).amountCents, 4321);
      expect(await db.pendingTombstones(), isEmpty);
    });

    test('lápida de una fila que ya no está en el servidor: la lápida se descarta (no queda pendiente para siempre)',
        () async {
      await expense(db, 'e1');
      await engine.sync();
      remote.rows['entries']!.remove('e1');
      await db.deleteEntry('e1');
      expect((await engine.sync()).state, SyncState.ok);
      expect(await db.pendingTombstones(), isEmpty);
    });
  });

  test('cerrar sesión por cualquier causa: detachSync (cursores fuera, todo pendiente)', () async {
    await engine.sync();
    expect(await db.readSyncCursors(), isNotEmpty);
    await auth.signOut();
    await engine.idle;
    expect(engine.status.state, SyncState.off);
    expect(await db.readSyncCursors(), isEmpty);
    expect(await db.hasPending(), isTrue);
  });

  test('pushOnly antes del primer sync (D5 sin resolver, app recién abierta): no sube nada', () async {
    await cloudHas(['b1']);
    await expense(db, 'mio');
    await engine.pushOnly();
    expect(remote.rows['entries']!.keys, ['b1']);
  });

  test('pushOnly: sube lo pendiente sin bajar', () async {
    await engine.sync();
    await expense(db, 'e1');
    remote.pullLog.clear();
    await engine.pushOnly();
    expect(remote.rows['entries']!.keys, ['e1']);
    expect(remote.pullLog, isEmpty);
  });

  test('V2 dos usuarios: los datos de A no suben a B (salvo "Unir") y A conserva los suyos', () async {
    remote.user = 'a';
    await expense(db, 'de-a');
    expect((await engine.sync()).state, SyncState.ok);
    await auth.signOut();
    await engine.idle;

    remote.user = 'b';
    await cloudHas(['de-b']);
    auth.addAccount('beto@correo.com', 'secreto2');
    await auth.signIn('beto@correo.com', 'secreto2');
    expect((await engine.sync()).state, SyncState.needsChoice, reason: 'el teléfono tiene datos de A');
    expect(remote.rows['entries']!.keys, ['de-b']);
    await engine.useCloud();
    expect(await entryIds(db), ['de-b']);

    remote.user = 'a';
    expect(remote.rows['entries']!.keys, ['de-a'], reason: 'la nube de A no se tocó');
  });
}
