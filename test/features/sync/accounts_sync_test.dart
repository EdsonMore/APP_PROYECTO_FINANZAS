import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/domain/recurrence.dart';
import 'package:saldo_claro/features/sync/pull.dart';
import 'package:saldo_claro/features/sync/push.dart';
import 'package:saldo_claro/features/sync/remote.dart';

void main() {
  late AppDatabase db;
  late FakeSyncRemote remote;
  var now = 1000;

  setUp(() async {
    now = 1000;
    db = AppDatabase(NativeDatabase.memory(), () => now);
    await db.completeOnboarding(mode: Mode.variable);
    remote = FakeSyncRemote();
  });
  tearDown(() => db.close());

  Future<void> yapeWithChildren() async {
    await db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone');
    await db.insertManualEntry(
        id: 'e1', kind: EntryKind.expense, amountCents: 900, day: day(2026, 10, 8), pickId: 'comida',
        now: DateTime.fromMillisecondsSinceEpoch(now), accountId: 'yape');
    await db.insertTransfer(id: 't1', fromAccountId: 'yape', toAccountId: null, amountCents: 300, day: day(2026, 10, 9));
  }

  group('base local', () {
    test('CHECK: una transferencia a la misma cuenta o sin ningún lado se rechaza', () async {
      await db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone');
      expect(
          () => db.insertTransfer(id: 'x', fromAccountId: 'yape', toAccountId: 'yape', amountCents: 1, day: day(2026, 10, 1)),
          throwsA(isA<Exception>()));
      expect(() => db.insertTransfer(id: 'y', fromAccountId: null, toAccountId: null, amountCents: 1, day: day(2026, 10, 1)),
          throwsA(isA<Exception>()));
      expect(
          () => db.insertTransfer(id: 'z', fromAccountId: 'no-existe', toAccountId: null, amountCents: 1, day: day(2026, 10, 1)),
          throwsA(isA<Exception>()), reason: 'FK local');
    });

    test('nombre de cuenta repetido se rechaza (UNIQUE, como los catálogos)', () async {
      await db.insertAccount(id: 'a', name: 'Yape', icon: 'phone');
      expect(() => db.insertAccount(id: 'b', name: 'Yape', icon: 'phone'), throwsA(isA<Exception>()));
    });

    test('borrar una transferencia nunca subida no deja lápida', () async {
      await db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone');
      await db.insertTransfer(id: 't1', fromAccountId: null, toAccountId: 'yape', amountCents: 1, day: day(2026, 10, 1));
      await db.deleteTransfer('t1');
      expect(await db.pendingTombstones(), isEmpty);
    });

    test('saldo inicial de la cuenta: monto e instante juntos, o ninguno', () async {
      await db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone');
      await db.setAccountOpening('yape', cents: 5000, at: DateTime(2026, 10, 1, 9));
      var a = await db.select(db.accounts).getSingle();
      expect(a.opening!.cents, 5000);
      expect(a.opening!.setAt, DateTime(2026, 10, 1, 9));
      await db.setAccountOpening('yape', cents: null);
      a = await db.select(db.accounts).getSingle();
      expect((a.openingBalanceCents, a.openingBalanceAt), (null, null));
    });

    test('hasUserData: una cuenta sola ya es "datos del usuario" (D5)', () async {
      expect(await db.hasUserData(), isFalse);
      await db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone');
      expect(await db.hasUserData(), isTrue);
    });
  });

  group('push', () {
    test('sube cuentas antes que movimientos y transferencias (FK del servidor)', () async {
      await yapeWithChildren();
      final r = await Pusher(db, remote).push();
      expect(r.errors, isEmpty);
      final order = [for (final c in remote.upsertCalls) c.table];
      expect(order.indexOf('accounts'), lessThan(order.indexOf('entries')));
      expect(order.indexOf('entries'), lessThan(order.indexOf('transfers')));
      expect(remote.rows['transfers']!['t1']!['from_account_id'], 'yape');
      expect(remote.rows['accounts']!['yape']!['archived'], false, reason: 'booleano como bool');
      expect(await db.hasPending(), isFalse);
    });

    test('si la cuenta no sube, sus hijos fallan por FK y quedan pendientes; al otro intento suben', () async {
      await yapeWithChildren();
      remote.rejectIds = {'yape'};
      final first = await Pusher(db, remote).push();
      expect({for (final e in first.errors) e.table}, {'accounts', 'entries', 'transfers'});
      expect(await db.hasPending(), isTrue);
      remote.rejectIds = {};
      expect((await Pusher(db, remote).push()).errors, isEmpty);
      expect(await db.hasPending(), isFalse);
    });

    test('borrar una transferencia ya subida marca la lápida en el servidor', () async {
      await yapeWithChildren();
      await Pusher(db, remote).push();
      now = 5000;
      await db.deleteTransfer('t1');
      await Pusher(db, remote).push();
      expect(remote.rows['transfers']!['t1']!['deleted_at'], isNotNull);
      expect(await db.pendingTombstones(), isEmpty);
    });
  });

  test('"Usar solo lo de la nube" borra cuentas y transferencias locales y deja las de la nube', () async {
    await yapeWithChildren();
    // N1 (4D): un recordatorio que apunta a la cuenta y a una categoría no traba el borrado (sin FK).
    await db.insertRecurrence(
        id: 'r1', amountCents: 4500, categoryId: 'comida', accountId: 'yape', frequency: Frequency.monthly,
        firstDay: day(2026, 10, 14));
    // La nube tiene otra cuenta con su transferencia.
    final other = AppDatabase(NativeDatabase.memory(), () => 2000);
    await other.completeOnboarding(mode: Mode.variable);
    await other.insertAccount(id: 'bcp', name: 'BCP', icon: 'bank');
    await other.insertTransfer(id: 'tb', fromAccountId: null, toAccountId: 'bcp', amountCents: 10, day: day(2026, 10, 2));
    await Pusher(other, remote).push();
    await other.close();

    await Puller(db, remote).pull(mode: PullMode.replace);
    expect([for (final a in await db.select(db.accounts).get()) a.id], ['bcp']);
    expect([for (final t in await db.select(db.transfers).get()) t.id], ['tb']);
    expect(await db.select(db.entries).get(), isEmpty);
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
    expect((await db.select(db.recurrences).getSingle()).id, 'r1', reason: 'local: "Usar solo la nube" no lo toca');
  });
}
