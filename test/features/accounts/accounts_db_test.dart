import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';

void main() {
  late AppDatabase db;
  var now = 1000;

  setUp(() async {
    now = 1000;
    db = AppDatabase(NativeDatabase.memory(), () => now);
    await db.completeOnboarding(mode: Mode.variable);
    await db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone_android');
    await db.insertAccount(id: 'bcp', name: 'BCP', icon: 'account_balance');
  });
  tearDown(() => db.close());

  Future<TransferRow> transfer() => (db.select(db.transfers)..where((t) => t.id.equals('t1'))).getSingle();

  test('updateTransfer: cambia todo, sube updated_at; sin cambios no escribe', () async {
    await db.insertTransfer(id: 't1', fromAccountId: 'yape', toAccountId: 'bcp', amountCents: 100, day: day(2026, 10, 1));
    now = 5000;
    final same = await db.updateTransfer(
        id: 't1', fromAccountId: 'yape', toAccountId: 'bcp', amountCents: 100, day: day(2026, 10, 1));
    expect(same!.updatedAt, 1000);
    final t = await db.updateTransfer(
        id: 't1', fromAccountId: 'bcp', toAccountId: null, amountCents: 900, day: day(2026, 10, 3), note: 'x');
    expect((t!.fromAccountId, t.toAccountId, t.amountCents, t.occurredOn, t.note, t.updatedAt),
        ('bcp', null, 900, '2026-10-03', 'x', 5000));
    expect(await db.updateTransfer(id: 'nope', fromAccountId: null, toAccountId: 'yape', amountCents: 1, day: day(2026, 10, 1)),
        isNull);
    expect((await transfer()).amountCents, 900);
  });

  test('lastUsedAccount: la del último movimiento de ese tipo', () async {
    expect(await db.lastUsedAccount(EntryKind.expense), isNull);
    Future<void> add(String id, EntryKind k, String? acc, int at) => db.insertManualEntry(
        id: id, kind: k, amountCents: 1, day: day(2026, 10, 1), pickId: k == EntryKind.expense ? 'comida' : 'chamba',
        now: DateTime.fromMillisecondsSinceEpoch(at), accountId: acc);
    await add('a', EntryKind.expense, 'yape', 1);
    await add('b', EntryKind.income, 'bcp', 2);
    expect(await db.lastUsedAccount(EntryKind.expense), 'yape');
    expect(await db.lastUsedAccount(EntryKind.income), 'bcp');
  });

  test('updateEntry con cuenta: Value.absent no la toca; Value(null) la quita', () async {
    await db.insertManualEntry(
        id: 'e', kind: EntryKind.expense, amountCents: 1, day: day(2026, 10, 1), pickId: 'comida',
        now: DateTime.fromMillisecondsSinceEpoch(now), accountId: 'yape');
    await db.updateEntry(id: 'e', amountCents: 2, day: day(2026, 10, 1), pickId: 'comida');
    expect((await db.select(db.entries).getSingle()).accountId, 'yape');
    now = 2000;
    final changed = await db.updateEntry(
        id: 'e', amountCents: 2, day: day(2026, 10, 1), pickId: 'comida', accountId: const Value(null));
    expect((changed!.accountId, changed.updatedAt), (null, 2000));
  });

  test('editar y archivar una cuenta suben updated_at (se sincroniza)', () async {
    now = 3000;
    await db.updateAccount('yape', name: 'Yape BCP', icon: 'savings');
    now = 4000;
    await db.setAccountArchived('yape', archived: true);
    final a = await (db.select(db.accounts)..where((a) => a.id.equals('yape'))).getSingle();
    expect((a.name, a.icon, a.archived, a.updatedAt), ('Yape BCP', 'savings', true, 4000));
  });
}
