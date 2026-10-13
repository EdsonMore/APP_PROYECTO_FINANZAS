import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/sync/auth_gateway.dart';
import 'package:saldo_claro/features/sync/fake_auth_gateway.dart';
import 'package:saldo_claro/features/sync/remote.dart';
import 'package:saldo_claro/features/sync/status.dart';
import 'package:saldo_claro/features/sync/sync_engine.dart';

/// Un teléfono: su base, su reloj, su sesión y su motor, contra el servidor compartido.
class Phone {
  Phone._(this.name, this.db, this.auth, this.engine);
  final String name;
  final AppDatabase db;
  final FakeAuthGateway auth;
  final SyncEngine engine;
  int now = 1000;

  static Future<Phone> create(String name, FakeSyncRemote remote) async {
    late Phone p;
    final db = AppDatabase(NativeDatabase.memory(), () => p.now);
    final auth = FakeAuthGateway()..addAccount('ana@correo.com', 'secreto1');
    await auth.signIn('ana@correo.com', 'secreto1');
    p = Phone._(name, db, auth, SyncEngine(db, remote, auth));
    await db.completeOnboarding(mode: Mode.variable);
    return p;
  }

  Future<SyncStatus> sync() => engine.sync();

  Future<void> expense(String id, {String cat = 'comida', String? account}) => db.insertManualEntry(
      id: id, kind: EntryKind.expense, amountCents: 100, day: day(2026, 10, 8), pickId: cat,
      now: DateTime.fromMillisecondsSinceEpoch(now), accountId: account);

  /// Edición de un movimiento (la app todavía no la tiene: SQL directo, como lo haría con bumped()).
  Future<void> editEntry(String id, int cents) => db.customUpdate(
      'UPDATE entries SET amount_cents = ?, updated_at = MAX(?, updated_at + 1) WHERE id = ?',
      variables: [Variable(cents), Variable(now), Variable(id)]);

  /// Las tablas sincronizadas, sin synced_at (lo único que puede diferir).
  Future<Map<String, List<Map<String, Object?>>>> dump() async => {
        for (final MapEntry(key: t, value: k) in AppDatabase.syncTables.entries)
          t: [
            for (final r in await db.customSelect('SELECT * FROM $t ORDER BY $k').get())
              {for (final e in r.data.entries) if (e.key != 'synced_at') e.key: e.value},
          ],
      };

  Future<void> close() async {
    await engine.dispose();
    await db.close();
  }
}

void main() {
  late FakeSyncRemote remote;
  late Phone a, b;

  /// Los dos sincronizan dos veces (A, B, A, B) y quedan idénticos.
  Future<void> converge() async {
    for (var i = 0; i < 2; i++) {
      await a.sync();
      await b.sync();
    }
    expect(await b.dump(), await a.dump());
    expect(await a.db.hasPending(), isFalse);
    expect(await b.db.hasPending(), isFalse);
  }

  Future<String?> categoryName(Phone p, String id) async =>
      (await (p.db.select(p.db.categories)..where((c) => c.id.equals(id))).getSingleOrNull())?.name;

  Future<int?> cap(Phone p, String cat) async =>
      (await (p.db.select(p.db.budgets)..where((x) => x.categoryId.equals(cat))).getSingleOrNull())?.capCents;

  Future<int?> amount(Phone p, String id) async =>
      (await (p.db.select(p.db.entries)..where((e) => e.id.equals(id))).getSingleOrNull())?.amountCents;

  setUp(() async {
    remote = FakeSyncRemote();
    a = await Phone.create('a', remote);
    b = await Phone.create('b', remote);
    expect((await a.sync()).state, SyncState.ok, reason: 'A: nube vacía, sube todo');
    expect((await b.sync()).state, SyncState.ok, reason: 'B: solo semilla, usa la nube');
  });
  tearDown(() async {
    await a.close();
    await b.close();
  });

  test('A crea y B baja', () async {
    await a.expense('a1');
    await converge();
    expect(await amount(b, 'a1'), 100);
  });

  test('los dos editan lo mismo: gana el más reciente, en los dos teléfonos', () async {
    a.now = 2000;
    await a.db.updateCatalogItem(EntryKind.expense, 'comida', name: 'Comida A', icon: 'restaurant');
    await a.db.setSpaceName('Casa A');
    b.now = 3000;
    await b.db.updateCatalogItem(EntryKind.expense, 'comida', name: 'Comida B', icon: 'restaurant');
    await a.sync(); // A sube primero; igual gana B, que es más reciente
    await converge();
    expect(await categoryName(a, 'comida'), 'Comida B');
    expect((await a.db.select(a.db.settings).getSingle()).spaceName, 'Casa A', reason: 'B no tocó los ajustes');
  });

  group('techos', () {
    test('los dos lo cambian: gana el último', () async {
      a.now = 2000;
      await a.db.setBudget('comida', 5000);
      b.now = 2500;
      await b.db.setBudget('comida', 7000);
      await converge();
      expect((await cap(a, 'comida'), await cap(b, 'comida')), (7000, 7000));
    });

    test('A lo quita y B lo cambia después: el techo revive', () async {
      a.now = 2000;
      await a.db.setBudget('comida', 5000);
      await converge();
      a.now = 3000;
      await a.db.removeBudget('comida');
      b.now = 3500;
      await b.db.setBudget('comida', 9000);
      await converge();
      expect((await cap(a, 'comida'), await cap(b, 'comida')), (9000, 9000));
    });

    test('B lo cambia y A lo quita después: queda quitado', () async {
      a.now = 2000;
      await a.db.setBudget('comida', 5000);
      await converge();
      b.now = 4000;
      await b.db.setBudget('comida', 9000);
      a.now = 4500;
      await a.db.removeBudget('comida');
      await converge();
      expect((await cap(a, 'comida'), await cap(b, 'comida')), (null, null));
    });
  });

  group('lápida contra edición (D6)', () {
    setUp(() async {
      a.now = 2000;
      await a.expense('e1');
      await converge();
    });

    test('A borra y B edita después: gana la edición, el movimiento vuelve', () async {
      a.now = 3000;
      await a.db.deleteEntry('e1');
      b.now = 3500;
      await b.editEntry('e1', 4321);
      await a.sync();
      await converge();
      expect((await amount(a, 'e1'), await amount(b, 'e1')), (4321, 4321));
    });

    test('B edita y A borra después: gana el borrado', () async {
      b.now = 3000;
      await b.editEntry('e1', 4321);
      await b.sync();
      a.now = 3500;
      await a.db.deleteEntry('e1');
      await converge();
      expect((await amount(a, 'e1'), await amount(b, 'e1')), (null, null));
    });
  });

  test('empate en el mismo milisegundo: gana el que llegó primero al servidor', () async {
    a.now = b.now = 5000;
    await a.db.updateCatalogItem(EntryKind.expense, 'ocio', name: 'Ocio A', icon: 'movie');
    await b.db.updateCatalogItem(EntryKind.expense, 'ocio', name: 'Ocio B', icon: 'movie');
    await a.sync();
    await converge();
    expect((await categoryName(a, 'ocio'), await categoryName(b, 'ocio')), ('Ocio A', 'Ocio A'));
  });

  test('"Ropa" creada en los dos: terminan con "Ropa" y "Ropa (2)" en ambos', () async {
    a.now = 2000;
    await a.db.addCatalogItem(EntryKind.expense, id: 'ropa-a', name: 'Ropa', icon: 'category');
    b.now = 2100;
    await b.db.addCatalogItem(EntryKind.expense, id: 'ropa-b', name: 'Ropa', icon: 'category');
    await converge();
    final names = {for (final c in await a.db.select(a.db.categories).get()) c.name};
    expect(names, containsAll(['Ropa', 'Ropa (2)']));
  });

  test('sin conexión: B cambia y no puede subir; al volver la red, todo converge', () async {
    remote.offline = true;
    b.now = 3000;
    await b.expense('b-offline');
    await b.db.setBudget('salud', 1500);
    expect((await b.sync()).state, SyncState.offline);
    expect(await b.db.hasPending(), isTrue);
    remote.offline = false;
    a.now = 3100;
    await a.expense('a-online');
    await converge();
    expect(await amount(a, 'b-offline'), 100);
    expect(await cap(a, 'salud'), 1500);
  });

  test('sesión vencida en B: needsLogin y sus datos se quedan; A sigue; B vuelve a entrar, une y converge', () async {
    b.now = 3000;
    await b.expense('b1');
    remote.sessionExpired = true;
    b.auth.refreshOutcome = RefreshOutcome.invalid;
    expect((await b.sync()).state, SyncState.needsLogin);
    await b.engine.idle;
    expect(await amount(b, 'b1'), 100);
    remote.sessionExpired = false;

    a.now = 3100;
    await a.expense('a1');
    expect((await a.sync()).state, SyncState.ok);

    await b.auth.signIn('ana@correo.com', 'secreto1');
    expect((await b.sync()).state, SyncState.needsChoice, reason: 'cerró sesión: primer contacto otra vez');
    expect((await b.engine.join()).state, SyncState.ok);
    await converge();
    expect(await amount(a, 'b1'), 100);
    expect(await amount(b, 'a1'), 100);
  });

  group('cuentas y transferencias (Fase 4A)', () {
    Future<List<String>> accountNames(Phone p) async =>
        [for (final x in await p.db.select(p.db.accounts).get()) x.name]..sort();

    test('A crea cuenta, movimiento en ella y transferencia; B lo baja todo (cuenta antes que sus hijos)', () async {
      await a.db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone');
      await a.db.setAccountOpening('yape', cents: 5000, at: DateTime(2026, 10, 1));
      await a.expense('a1', account: 'yape');
      await a.db.insertTransfer(id: 't1', fromAccountId: 'yape', toAccountId: null, amountCents: 700, day: day(2026, 10, 9));
      await converge();
      final e = await (b.db.select(b.db.entries)..where((x) => x.id.equals('a1'))).getSingle();
      expect(e.accountId, 'yape');
      final yape = await (b.db.select(b.db.accounts)..where((x) => x.id.equals('yape'))).getSingle();
      expect((yape.openingBalanceCents, yape.archived), (5000, false));
      expect(await b.db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    });

    test('la misma cuenta "Yape" creada en los dos (ids distintos): quedan "Yape" y "Yape (2)"', () async {
      await a.db.insertAccount(id: 'ya', name: 'Yape', icon: 'phone');
      await b.db.insertAccount(id: 'yb', name: 'Yape', icon: 'phone');
      await converge();
      expect(await accountNames(a), ['Yape', 'Yape (2)']);
    });

    test('borrar una transferencia sincronizada la borra en el otro teléfono (lápida)', () async {
      await a.db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone');
      await a.db.insertTransfer(id: 't1', fromAccountId: null, toAccountId: 'yape', amountCents: 300, day: day(2026, 10, 9));
      await converge();
      expect(await b.db.select(b.db.transfers).get(), hasLength(1));
      a.now = 5000;
      await a.db.deleteTransfer('t1');
      await converge();
      expect(await b.db.select(b.db.transfers).get(), isEmpty);
    });

    test('archivar una cuenta viaja; una cuenta "borrada" en el servidor no borra la local (se archivan)', () async {
      await a.db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone');
      await converge();
      remote.rows['accounts']!['yape']!
        ..['deleted_at'] = 9000
        ..['updated_at'] = 9000
        ..['server_updated_at'] = DateTime.utc(2027).toIso8601String();
      await b.sync();
      expect(await accountNames(b), ['Yape'], reason: 'una cuenta nunca se borra al bajar');
    });
  });

  test('convergencia aleatoria: 200 rondas de cambios en los dos, syncs intercalados y caídas de red', () async {
    final rnd = Random(const int.fromEnvironment('SEED', defaultValue: 20261013)); // --dart-define=SEED=n para explorar
    const names = ['Comida', 'Ropa', 'Casa', 'Viaje', 'Extra', 'Ropa (2)'];
    const accountNames = ['Yape', 'BCP', 'Efectivo', 'Yape (2)'];
    var transfersMade = 0;
    var n = 0;
    Future<void> op(Phone p) async {
      p.now += rnd.nextInt(4); // 0: mismo ms (empates con el otro teléfono)
      final cats = [for (final c in await p.db.select(p.db.categories).get()) c.id];
      final entries = [for (final e in await p.db.select(p.db.entries).get()) e.id];
      final accounts = [for (final x in await p.db.select(p.db.accounts).get()) x.id];
      final transfers = [for (final t in await p.db.select(p.db.transfers).get()) t.id];
      final pick = cats[rnd.nextInt(cats.length)];
      String? anyAccount() => accounts.isEmpty || rnd.nextInt(3) == 0 ? null : accounts[rnd.nextInt(accounts.length)];
      try {
        switch (rnd.nextInt(14)) {
          case 0 || 1:
            await p.expense('${p.name}${n++}', cat: pick, account: anyAccount());
          case 2 when entries.isNotEmpty:
            await p.db.deleteEntry(entries[rnd.nextInt(entries.length)]);
          case 3 when entries.isNotEmpty:
            await p.editEntry(entries[rnd.nextInt(entries.length)], 1 + rnd.nextInt(9999));
          case 4:
            await p.db.setBudget(pick, 1 + rnd.nextInt(9999));
          case 5:
            await p.db.removeBudget(pick);
          case 6:
            await p.db.updateCatalogItem(EntryKind.expense, pick, name: names[rnd.nextInt(names.length)], icon: 'category');
          case 7:
            await p.db.addCatalogItem(EntryKind.expense,
                id: '${p.name}cat${n++}', name: names[rnd.nextInt(names.length)], icon: 'category');
          case 8:
            await p.db.setArchived(EntryKind.expense, pick, archived: rnd.nextBool());
          case 10:
            await p.db.insertAccount(id: '${p.name}acc${n++}', name: accountNames[rnd.nextInt(accountNames.length)], icon: 'phone');
          case 11 when accounts.isNotEmpty:
            await p.db.insertTransfer(
                id: '${p.name}t${n++}', fromAccountId: anyAccount(), toAccountId: anyAccount(),
                amountCents: 1 + rnd.nextInt(9999), day: day(2026, 10, 1 + rnd.nextInt(12)));
            transfersMade++;
          case 12 when transfers.isNotEmpty:
            await p.db.deleteTransfer(transfers[rnd.nextInt(transfers.length)]);
          case 13 when accounts.isNotEmpty:
            await p.db.setAccountOpening(accounts[rnd.nextInt(accounts.length)],
                cents: rnd.nextBool() ? null : rnd.nextInt(99999), at: DateTime(2026, 10, 1 + rnd.nextInt(12)));
          default:
            await p.db.setSpaceName(rnd.nextBool() ? null : 'Espacio ${rnd.nextInt(5)}');
        }
      } on Exception {
        // Nombre repetido (UNIQUE) o transferencia a la misma cuenta / sin
        // ningún lado (CHECK): la app también lo rechaza.
      }
    }

    for (var round = 0; round < const int.fromEnvironment('ROUNDS', defaultValue: 200); round++) {
      final p = rnd.nextBool() ? a : b;
      await op(p);
      if (rnd.nextInt(10) < 3) {
        remote.offline = rnd.nextInt(10) == 0;
        await p.sync();
        remote.offline = false;
      }
    }
    // Algún choque de nombres renombra filas al bajar y las deja pendientes:
    // pueden hacer falta más vueltas que en los casos simples.
    for (var i = 0; i < 4; i++) {
      await a.sync();
      await b.sync();
    }
    expect(await b.dump(), await a.dump());
    expect((await a.db.hasPending(), await b.db.hasPending()), (false, false));
    expect((a.engine.status.state, b.engine.status.state), (SyncState.ok, SyncState.ok));
    expect(await a.db.select(a.db.entries).get(), isNotEmpty, reason: 'la prueba ejercitó algo');
    expect(await a.db.select(a.db.accounts).get(), isNotEmpty, reason: 'también cuentas');
    expect(transfersMade, greaterThan(0), reason: 'y transferencias (pueden haberse borrado todas)');
  });
}
