import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/domain/recurrence.dart';

void main() {
  group('nextDue', () {
    test('cada semana: +7 días', () {
      expect(nextDue(day(2026, 10, 14), Frequency.weekly, anchorDay: 14), day(2026, 10, 21));
      expect(nextDue(day(2026, 12, 28), Frequency.weekly, anchorDay: 28), day(2027, 1, 4));
    });

    test('cada mes: mismo día del mes siguiente', () {
      expect(nextDue(day(2026, 10, 14), Frequency.monthly, anchorDay: 14), day(2026, 11, 14));
      expect(nextDue(day(2026, 12, 5), Frequency.monthly, anchorDay: 5), day(2027, 1, 5));
    });

    test('N3: ancla 31 → último día en meses cortos y vuelve al 31 después', () {
      final nov = nextDue(day(2026, 10, 31), Frequency.monthly, anchorDay: 31);
      expect(nov, day(2026, 11, 30));
      final dec = nextDue(nov, Frequency.monthly, anchorDay: 31);
      expect(dec, day(2026, 12, 31));
      expect(nextDue(day(2027, 1, 31), Frequency.monthly, anchorDay: 31), day(2027, 2, 28));
      expect(nextDue(day(2028, 1, 31), Frequency.monthly, anchorDay: 31), day(2028, 2, 29), reason: 'bisiesto');
    });

    test('cada año: misma fecha; 29 feb → 28 feb en años no bisiestos y vuelve al 29', () {
      expect(nextDue(day(2026, 10, 14), Frequency.yearly, anchorDay: 14), day(2027, 10, 14));
      final y2029 = nextDue(day(2028, 2, 29), Frequency.yearly, anchorDay: 29);
      expect(y2029, day(2029, 2, 28));
      expect(nextDue(day(2031, 2, 28), Frequency.yearly, anchorDay: 29), day(2032, 2, 29));
    });
  });

  group('fix5: estado', () {
    final today = day(2026, 10, 14);
    test('daysToDue: negativo si venció', () {
      expect(daysToDue(day(2026, 10, 14), today), 0);
      expect(daysToDue(day(2026, 10, 17), today), 3);
      expect(daysToDue(day(2026, 9, 14), today), -30);
    });

    test('tono: rojo si venció o vence hoy, ámbar a 1-3 días, neutro después', () {
      expect([for (final d in [-30, -1, 0, 1, 3, 4, 7]) dueTone(d)], [
        DueTone.overdue, DueTone.overdue, DueTone.overdue, DueTone.soon, DueTone.soon, DueTone.later, DueTone.later,
      ]);
    });

    test('pagos pendientes: cuántos vencimientos ya llegaron (E3)', () {
      expect(pendingPeriods(day(2026, 10, 20), Frequency.monthly, anchorDay: 20, today: today), 0);
      expect(pendingPeriods(day(2026, 10, 14), Frequency.monthly, anchorDay: 14, today: today), 1, reason: 'vence hoy');
      expect(pendingPeriods(day(2026, 9, 4), Frequency.monthly, anchorDay: 4, today: today), 2, reason: '4 sep y 4 oct');
      expect(pendingPeriods(day(2026, 9, 30), Frequency.weekly, anchorDay: 30, today: today), 3, reason: '30 sep, 7 y 14 oct');
    });

    test('vencimiento anterior (ventana del pago ya registrado, E1)', () {
      expect(previousDue(day(2026, 10, 17), Frequency.monthly, anchorDay: 17), day(2026, 9, 17));
      expect(previousDue(day(2026, 3, 3), Frequency.monthly, anchorDay: 3), day(2026, 2, 3));
      expect(previousDue(day(2026, 2, 28), Frequency.monthly, anchorDay: 31), day(2026, 1, 31), reason: 'ancla 31');
      expect(previousDue(day(2027, 1, 5), Frequency.monthly, anchorDay: 5), day(2026, 12, 5), reason: 'cruza de año');
      expect(previousDue(day(2026, 10, 21), Frequency.weekly, anchorDay: 21), day(2026, 10, 14));
      expect(previousDue(day(2029, 2, 28), Frequency.yearly, anchorDay: 29), day(2028, 2, 29), reason: 'bisiesto');
    });
  });

  group('fix5: avisos', () {
    test('3 días antes, el día y cada día hasta +7, a las 9:00 local', () {
      expect(reminderMoments(day(2026, 10, 17)), [
        DateTime(2026, 10, 14, 9),
        DateTime(2026, 10, 17, 9),
        for (var d = 18; d <= 24; d++) DateTime(2026, 10, d, 9),
      ]);
    });

    test('cruza de mes', () {
      final m = reminderMoments(day(2026, 11, 2));
      expect((m.first, m[1], m.last), (DateTime(2026, 10, 30, 9), DateTime(2026, 11, 2, 9), DateTime(2026, 11, 9, 9)));
    });
  });
}
