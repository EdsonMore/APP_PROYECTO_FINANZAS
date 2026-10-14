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

  /// Internet (Vivienda), S/ 45.00, cada mes. [due]: próximo pago.
  Future<Recurrence> internet({String id = 'r1', String? note = 'Internet', DateTime? due}) async {
    final r = await db.insertRecurrence(
        id: id, amountCents: 4500, categoryId: 'vivienda', note: note, frequency: Frequency.monthly,
        firstDue: due ?? day(2026, 11, 17));
    return r;
  }

  int idOf(Recurrence r, int k) => r.notificationId * 10 + k;

  Future<void> expense(String id, int cents, String pick, DateTime d, {EntryKind kind = EntryKind.expense}) =>
      db.insertManualEntry(id: id, kind: kind, amountCents: cents, day: d, pickId: pick, now: now);

  group('avisos (fix5)', () {
    test('hasta 9 por recordatorio: 3 días antes, el día y del +1 al +7, a las 9:00, con su texto', () async {
      final r = await internet();
      await service.schedule(r);
      expect(notifier.scheduled.keys, [for (var k = 0; k < 9; k++) idOf(r, k)]);
      final before = notifier.scheduled[idOf(r, 0)]!;
      expect((before.at, before.title, before.body, before.payload), (
        DateTime(2026, 11, 14, 9),
        'Se viene un pago: S/ 45.00',
        'Internet (Vivienda) vence el martes 17 nov. Toca para registrarlo.',
        'r1',
      ));
      final dayOf = notifier.scheduled[idOf(r, 1)]!;
      expect((dayOf.at, dayOf.title, dayOf.body),
          (DateTime(2026, 11, 17, 9), 'Hoy vence: S/ 45.00', 'Internet (Vivienda) vence hoy. Toca para registrarlo.'));
      final late = notifier.scheduled[idOf(r, 2)]!;
      expect((late.at, late.title, late.body), (
        DateTime(2026, 11, 18, 9),
        'Pago vencido: S/ 45.00',
        'Internet (Vivienda) venció el martes 17 nov. Toca para registrarlo.',
      ));
      expect(notifier.scheduled[idOf(r, 8)]!.at, DateTime(2026, 11, 24, 9));
    });

    test('los que ya pasaron no se programan; vencido hace más de 7 días, ninguno', () async {
      final soon = await internet(due: day(2026, 10, 15)); // el aviso de 3 días antes (12 oct) ya pasó
      await service.schedule(soon);
      expect(notifier.scheduled.keys, [for (var k = 1; k < 9; k++) idOf(soon, k)]);
      notifier.scheduled.clear();
      final old = await internet(id: 'r2', due: day(2026, 10, 4)); // último aviso: 11 oct
      await service.schedule(old);
      expect(notifier.scheduled, isEmpty);
    });

    test('a las 10:00 del día +7 ya no avisa; a las 8:00 sí', () async {
      final r = await internet(due: day(2026, 10, 7));
      await service.schedule(r);
      expect(notifier.scheduled, isEmpty, reason: 'el +7 (14 oct, 9:00) ya pasó');
      now = DateTime(2026, 10, 14, 8);
      await service.schedule(r);
      expect(notifier.scheduled.keys, [idOf(r, 8)]);
    });

    test('ids: no chocan entre recordatorios', () async {
      final a = await internet();
      final b = await internet(id: 'r2');
      expect(b.notificationId, a.notificationId + 1);
      expect(idOf(a, 8), lessThan(idOf(b, 0)));
    });
  });

  test('refreshAll: la fecha NO avanza sola; cancela todo y reprograma', () async {
    await internet(due: day(2026, 8, 20)); // vencido hace casi 2 meses
    final future = await internet(id: 'r2');
    await service.refreshAll();
    final rows = {for (final r in await db.select(db.recurrences).get()) r.id: r.nextDue};
    expect(rows, {'r1': '2026-08-20', 'r2': '2026-11-17'});
    expect(await db.select(db.entries).get(), isEmpty, reason: 'nunca crea gastos solo');
    expect(notifier.cancelAllCalls, 1);
    expect(notifier.scheduled.keys.toSet(), {for (var k = 0; k < 9; k++) idOf(future, k)});
  });

  test('pagado (confirmed): avanza un período y reprograma', () async {
    final r = await internet(due: day(2026, 10, 15));
    await service.schedule(r);
    await service.confirmed(r.id);
    expect((await db.select(db.recurrences).getSingle()).nextDue, '2026-11-15');
    expect(notifier.scheduled[idOf(r, 0)]!.at, DateTime(2026, 11, 12, 9));
    expect(notifier.scheduled.values.where((s) => s.at.month == 10), isEmpty, reason: 'los de octubre se cancelan');
  });

  test('saltar: avanza sin crear gasto; deshacer devuelve la fecha y los avisos', () async {
    final r = await internet(due: day(2026, 10, 10)); // vencido
    final previous = await service.skip(r.id);
    expect(previous, day(2026, 10, 10));
    expect((await db.select(db.recurrences).getSingle()).nextDue, '2026-11-10');
    expect(await db.select(db.entries).get(), isEmpty);
    expect(notifier.scheduled[idOf(r, 0)]!.at, DateTime(2026, 11, 7, 9));
    await service.setDue(r.id, previous!);
    expect((await db.select(db.recurrences).getSingle()).nextDue, '2026-10-10');
    expect(notifier.scheduled[idOf(r, 8)]!.at, DateTime(2026, 10, 17, 9), reason: 'vuelven los de +7');
  });

  test('borrar cancela sus 9 avisos', () async {
    final r = await internet();
    await service.schedule(r);
    await service.remove(r);
    expect(notifier.scheduled, isEmpty);
    expect(await db.select(db.recurrences).get(), isEmpty);
  });

  group('E1: gasto ya registrado', () {
    test('mismo monto y categoría, después del vencimiento anterior: el más reciente', () async {
      final r = await internet(due: day(2026, 10, 17)); // anterior: 17 sep
      await expense('viejo', 4500, 'vivienda', day(2026, 9, 17)); // justo el vencimiento anterior: no
      await expense('a', 4500, 'vivienda', day(2026, 10, 2));
      await expense('b', 4500, 'vivienda', day(2026, 10, 10));
      expect((await service.findPayment(r, today: day(2026, 10, 14)))?.id, 'b');
    });

    test('el pago del período anterior (justo en su vencimiento) no cuenta', () async {
      final r = await internet(due: day(2026, 10, 17)); // anterior: 17 sep
      await expense('anterior', 4500, 'vivienda', day(2026, 9, 17));
      expect(await service.findPayment(r, today: day(2026, 10, 14)), isNull);
    });

    test('otro monto, otra categoría o un ingreso: no', () async {
      final r = await internet(due: day(2026, 10, 17));
      await expense('monto', 4600, 'vivienda', day(2026, 10, 10));
      await expense('cat', 4500, 'comida', day(2026, 10, 10));
      expect(await service.findPayment(r, today: day(2026, 10, 14)), isNull);
    });
  });

  test('estado: textos por días', () {
    expect([for (final d in [-30, -2, -1, 0, 1, 3]) dueStatus(d)],
        ['vencido hace 30 días', 'vencido hace 2 días', 'venció ayer', 'vence hoy', 'vence mañana', 'en 3 días']);
  });

  test('N1: categoría que ya no existe → el texto dice "Gasto"; sin nota, solo la categoría', () async {
    final r = await db.insertRecurrence(
        id: 'r2', amountCents: 100, categoryId: 'no-existe', frequency: Frequency.monthly, firstDay: day(2026, 10, 30));
    expect(reminderLabel(r, null), 'Gasto');
    expect(reminderLabel(await internet(note: null), 'Vivienda'), 'Vivienda');
  });
}
