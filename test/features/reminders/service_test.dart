import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/domain/recurrence.dart';
import 'package:saldo_claro/features/reminders/notifier.dart';
import 'package:saldo_claro/features/reminders/service.dart';

void main() {
  late AppDatabase db;
  late FakeReminderNotifier notifier;
  late ReminderService service;
  var now = DateTime(2026, 10, 14, 10);

  setUpAll(() => initializeDateFormatting('es_PE'));
  setUp(() async {
    now = DateTime(2026, 10, 14, 10);
    db = AppDatabase(NativeDatabase.memory());
    await db.completeOnboarding(mode: Mode.variable);
    notifier = FakeReminderNotifier();
    service = ReminderService(db, notifier, clock: () => now);
  });
  tearDown(() => db.close());

  Future<Recurrence> internet({String? note = 'Internet', Frequency f = Frequency.monthly, DateTime? first}) =>
      db.insertRecurrence(
          id: 'r1', amountCents: 4500, categoryId: 'vivienda', note: note, frequency: f,
          firstDay: first ?? day(2026, 10, 17));

  test('al crear: próximo vencimiento un período después; aviso 3 días antes a las 9:00 con su texto', () async {
    final r = await internet();
    expect(r.nextDue, '2026-11-17');
    await service.schedule(r);
    final s = notifier.scheduled[r.notificationId]!;
    expect(s.at, DateTime(2026, 11, 14, 9));
    expect(s.title, 'Se viene un pago: S/ 45.00');
    expect(s.body, 'Internet (Vivienda) vence el martes 17 nov. Toca para registrarlo.');
    expect(s.payload, 'r1');
  });

  test('si el momento del aviso ya pasó, no avisa (espera al próximo período)', () async {
    final r = await internet(f: Frequency.weekly, first: day(2026, 10, 10)); // vence el 17; el aviso era el 14 a las 9
    await service.schedule(r);
    expect(notifier.scheduled, isEmpty);
  });

  test('N2/N8 refreshAll: corre las fechas vencidas sin crear gastos, cancela todo y reprograma', () async {
    final r = await internet(first: day(2026, 7, 20)); // próximo 20 ago: vencido
    now = DateTime(2026, 10, 14, 10);
    await service.refreshAll();
    final after = await db.select(db.recurrences).getSingle();
    expect(after.nextDue, '2026-10-20');
    expect(await db.select(db.entries).get(), isEmpty, reason: 'R1: nunca crea solo');
    expect(notifier.cancelAllCalls, 1);
    expect(notifier.scheduled[r.notificationId]!.at, DateTime(2026, 10, 17, 9));
  });

  test('confirmado: el vencimiento pasa al período siguiente y se reprograma', () async {
    final r = await internet();
    await service.confirmed(r.id);
    expect((await db.select(db.recurrences).getSingle()).nextDue, '2026-12-17');
    expect(notifier.scheduled[r.notificationId]!.at, DateTime(2026, 12, 14, 9));
  });

  test('borrar cancela la alarma', () async {
    final r = await internet();
    await service.schedule(r);
    await service.remove(r);
    expect(notifier.scheduled, isEmpty);
    expect(await db.select(db.recurrences).get(), isEmpty);
  });

  test('N1: categoría que ya no existe → el texto dice "Gasto"; sin nota, solo la categoría', () async {
    final r = await db.insertRecurrence(
        id: 'r2', amountCents: 100, categoryId: 'no-existe', frequency: Frequency.monthly, firstDay: day(2026, 10, 30));
    expect(reminderLabel(r, null), 'Gasto');
    expect(reminderLabel(await internet(note: null), 'Vivienda'), 'Vivienda');
  });

  test('cada recordatorio tiene su propio id de alarma', () async {
    final a = await internet();
    final b = await db.insertRecurrence(
        id: 'r2', amountCents: 100, categoryId: 'comida', frequency: Frequency.weekly, firstDay: day(2026, 10, 30));
    expect(b.notificationId, a.notificationId + 1);
  });
}
