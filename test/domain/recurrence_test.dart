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

  group('rollForward (N2)', () {
    test('vencida hace varios períodos: la primera fecha >= hoy', () {
      expect(rollForward(day(2026, 7, 14), Frequency.monthly, anchorDay: 14, today: day(2026, 10, 14)), day(2026, 10, 14),
          reason: 'vence hoy: todavía no se pasó');
      expect(rollForward(day(2026, 7, 14), Frequency.monthly, anchorDay: 14, today: day(2026, 10, 15)), day(2026, 11, 14));
      expect(rollForward(day(2026, 9, 30), Frequency.weekly, anchorDay: 30, today: day(2026, 10, 15)), day(2026, 10, 21));
    });

    test('futura: no cambia', () {
      expect(rollForward(day(2026, 12, 1), Frequency.monthly, anchorDay: 1, today: day(2026, 10, 14)), day(2026, 12, 1));
    });
  });

  group('reminderAt', () {
    test('3 días antes del vencimiento, a las 9:00 (hora local)', () {
      expect(reminderAt(day(2026, 10, 17)), DateTime(2026, 10, 14, 9));
      expect(reminderAt(day(2026, 11, 2)), DateTime(2026, 10, 30, 9), reason: 'cruza de mes');
    });
  });
}
