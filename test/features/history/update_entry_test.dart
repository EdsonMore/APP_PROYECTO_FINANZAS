import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/sync/push.dart';
import 'package:saldo_claro/features/sync/remote.dart';

void main() {
  late AppDatabase db;
  var now = 1000;

  setUp(() async {
    now = 1000;
    db = AppDatabase(NativeDatabase.memory(), () => now);
    await db.completeOnboarding(mode: Mode.variable);
    await db.insertManualEntry(
        id: 'e1', kind: EntryKind.expense, amountCents: 1200, day: day(2026, 10, 10), pickId: 'comida',
        note: 'menú', now: DateTime.fromMillisecondsSinceEpoch(now));
  });
  tearDown(() => db.close());

  Future<Entry> row() => (db.select(db.entries)..where((e) => e.id.equals('e1'))).getSingle();

  test('cambia monto, fecha, categoría y nota, y sube updated_at', () async {
    now = 5000;
    final e = await db.updateEntry(
        id: 'e1', amountCents: 4250, day: day(2026, 10, 12), pickId: 'transporte', note: 'taxi');
    expect(e!.amountCents, 4250);
    expect(e.occurredOn, '2026-10-12');
    expect(e.categoryId, 'transporte');
    expect(e.sourceId, isNull);
    expect(e.note, 'taxi');
    expect(e.updatedAt, 5000);
    expect(e.createdAt, 1000, reason: 'created_at no cambia');
  });

  test('updated_at = MAX(ahora, updated_at + 1): crece aunque el reloj no avance o retroceda', () async {
    now = 900; // el reloj retrocedió
    final e = await db.updateEntry(id: 'e1', amountCents: 1300, day: day(2026, 10, 10), pickId: 'comida', note: 'menú');
    expect(e!.updatedAt, 1001);
  });

  test('sin cambios no escribe (ni updated_at ni pendiente de sync)', () async {
    now = 5000;
    final e = await db.updateEntry(id: 'e1', amountCents: 1200, day: day(2026, 10, 10), pickId: 'comida', note: 'menú');
    expect(e!.updatedAt, 1000);
    expect((await row()).updatedAt, 1000);
  });

  test('ingreso: cambia la fuente, nunca la categoría', () async {
    await db.insertManualEntry(
        id: 'i1', kind: EntryKind.income, amountCents: 50000, day: day(2026, 10, 1), pickId: 'chamba',
        now: DateTime.fromMillisecondsSinceEpoch(now));
    final e = await db.updateEntry(id: 'i1', amountCents: 50000, day: day(2026, 10, 1), pickId: 'venta', note: null);
    expect(e!.sourceId, 'venta');
    expect(e.categoryId, isNull);
  });

  test('un id que ya no existe (se borró en otro teléfono): null, no escribe nada', () async {
    expect(await db.updateEntry(id: 'nope', amountCents: 1, day: day(2026, 10, 1), pickId: 'comida'), isNull);
  });

  test('O1: editar un movimiento YA sincronizado lo vuelve a subir en el próximo sync', () async {
    final remote = FakeSyncRemote();
    final pusher = Pusher(db, remote);
    await pusher.push();
    expect((await row()).syncedAt, isNotNull);
    expect(await db.hasPending(), isFalse);

    now = 5000;
    await db.updateEntry(id: 'e1', amountCents: 9900, day: day(2026, 10, 10), pickId: 'comida', note: 'menú');
    expect(await db.hasPending(), isTrue, reason: 'synced_at < updated_at');
    await pusher.push();
    expect(remote.rows['entries']!['e1']!['amount_cents'], 9900);
    expect(await db.hasPending(), isFalse);
  });
}
