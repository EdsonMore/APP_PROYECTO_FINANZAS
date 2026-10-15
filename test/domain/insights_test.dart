import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/domain/insights.dart';
import 'package:saldo_claro/domain/metrics.dart';

Movement out(int soles, DateTime d, [String cat = 'comida']) =>
    Movement(kind: EntryKind.expense, cents: soles * 100, day: d, categoryId: cat);
Movement inc(int soles, DateTime d) => Movement(kind: EntryKind.income, cents: soles * 100, day: d, categoryId: null);

PaidExpense paid(int soles, DateTime d, {String cat = 'vivienda', String? note, String? account}) =>
    (categoryId: cat, cents: soles * 100, day: d, note: note, accountId: account);

void main() {
  final today = day(2026, 10, 15); // jueves

  group('monthBalance', () {
    test('ingreso − gasto del mes hasta hoy; sin ingreso en el mes, nada', () {
      final ms = [inc(1000, day(2026, 10, 1)), out(1150, day(2026, 10, 5)), out(500, day(2026, 9, 20))];
      expect(monthBalance(ms, today: today)!.cents, -15000);
      expect(monthBalance([out(100, day(2026, 10, 2))], today: today), isNull);
    });
  });

  group('categoryChanges (H1: mismo tramo del mes anterior)', () {
    final base = [out(1, day(2026, 8, 30), 'otros')]; // hay datos desde antes de septiembre
    test('sube y baja contra el 1-15 de septiembre', () {
      final ms = [
        ...base,
        out(340, day(2026, 9, 10)), out(500, day(2026, 9, 25)), // el 25 sep queda fuera del tramo
        out(460, day(2026, 10, 3)), // Comida: 340 → 460, +120 (+35%)
        out(75, day(2026, 9, 5), 'ocio'), out(45, day(2026, 10, 5), 'ocio'), // Ocio: 75 → 45, −30 (−40%)
      ];
      final c = categoryChanges(ms, today: today);
      expect((c.up!.categoryId, c.up!.deltaCents, c.up!.percent), ('comida', 12000, 35));
      expect((c.down!.categoryId, c.down!.deltaCents, c.down!.percent), ('ocio', -3000, -40));
      expect(c.up!.previousMonth, day(2026, 9, 1));
    });

    test('H2: menos de S/ 20 o menos de 20% no entra', () {
      final ms = [
        ...base,
        out(100, day(2026, 9, 2)), out(115, day(2026, 10, 2)), // +15
        out(300, day(2026, 9, 2), 'vivienda'), out(330, day(2026, 10, 2), 'vivienda'), // +30 pero +10%
        out(50, day(2026, 9, 2), 'ocio'), out(65, day(2026, 10, 2), 'ocio'), // +30% pero solo +15
      ];
      final c = categoryChanges(ms, today: today);
      expect((c.up, c.down), (null, null));
    });

    test('sin datos que cubran el mes anterior, no compara', () {
      final c = categoryChanges([out(10, day(2026, 9, 10)), out(500, day(2026, 10, 2))], today: today);
      expect((c.up, c.down), (null, null));
    });

    test('meses cortos: el 31 de marzo compara contra el 1-28 de febrero', () {
      final ms = [out(1, day(2027, 1, 20), 'otros'), out(100, day(2027, 2, 28)), out(200, day(2027, 3, 31))];
      expect(categoryChanges(ms, today: day(2027, 3, 31)).up!.deltaCents, 10000);
    });
  });

  group('daysLeft', () {
    test('días hasta fin de mes (hoy incluido), saldo y sugerencia diaria', () {
      final f = daysLeft([inc(900, day(2026, 10, 1))], today: day(2026, 10, 14));
      expect((f.days, f.balanceCents, f.dailyCents), (18, 90000, 5000));
    });

    test('el último día queda 1; sin reserva, sin sugerencia', () {
      expect(daysLeft([inc(100, day(2026, 10, 1))], today: day(2026, 10, 31)).days, 1);
      final none = daysLeft([out(50, day(2026, 10, 1))], today: today);
      expect((none.dailyCents, none.balanceCents), (null, -5000));
    });
  });

  group('streakFact', () {
    test('desde 3 días; sin umbral útil, nada', () {
      expect(streakFact(days: 2, thresholdCents: 3000), isNull);
      expect(streakFact(days: 3, thresholdCents: 3000)!.days, 3);
      expect(streakFact(days: 10, thresholdCents: null), isNull);
    });
  });

  group('topWeekday', () {
    List<Movement> weeks(int n, {int saturday = 60, int other = 40}) => [
          for (var d = today.subtract(Duration(days: n * 7 - 1)); !d.isAfter(today); d = d.add(const Duration(days: 1)))
            out(d.weekday == DateTime.saturday ? saturday : other, d),
        ];

    test('sábados +50% durante 8 semanas → sábado, con su promedio', () {
      final f = topWeekday(weeks(8), today: today)!;
      expect((f.weekday, f.avgCents), (DateTime.saturday, 6000));
    });

    test('con menos de 4 semanas de datos, nada', () {
      expect(topWeekday(weeks(3), today: today), isNull);
    });

    test('parejo (+25%), nada', () {
      expect(topWeekday(weeks(8, saturday: 50), today: today), isNull);
    });
  });

  group('recurringPayments (H3)', () {
    final threePaid = [
      paid(45, day(2026, 8, 15), note: 'Internet'),
      paid(45, day(2026, 9, 14), note: 'Internet', account: 'yape'),
      paid(45, day(2026, 10, 15), account: 'bcp'),
    ];

    test('3 pagos iguales cada ~mes → uno, con día, nota más frecuente y la cuenta del último', () {
      final r = recurringPayments(threePaid, today: today).single;
      expect((r.categoryId, r.cents, r.anchorDay, r.note, r.accountId, r.last),
          ('vivienda', 4500, 15, 'Internet', 'bcp', day(2026, 10, 15)));
      expect(r.key, 'vivienda|4500');
    });

    test('solo 2 pagos, nada', () {
      expect(recurringPayments(threePaid.skip(1).toList(), today: today), isEmpty);
    });

    test('un intervalo de 50 días corta la cadena', () {
      final ms = [paid(45, day(2026, 7, 1)), paid(45, day(2026, 8, 20)), paid(45, day(2026, 9, 19))];
      expect(recurringPayments(ms, today: day(2026, 9, 25)), isEmpty);
    });

    test('el último hace más de 35 días ya no está activo', () {
      expect(recurringPayments(threePaid, today: day(2026, 11, 25)), isEmpty);
    });

    test('montos distintos no se juntan', () {
      final ms = [...threePaid, paid(46, day(2026, 9, 1)), paid(46, day(2026, 9, 25))];
      expect(recurringPayments(ms, today: today).single.cents, 4500);
    });

    test('un gasto igual que se repite seguido (menú diario) no es un pago mensual', () {
      final daily = [
        for (var d = day(2026, 8, 1); !d.isAfter(today); d = d.add(const Duration(days: 1))) paid(20, d, cat: 'comida'),
      ];
      expect(recurringPayments(daily, today: today), isEmpty);
      final extra = [...threePaid, paid(45, day(2026, 9, 25))]; // otro igual en el medio
      expect(recurringPayments(extra, today: today), isEmpty, reason: 'los 3 más recientes deben ir seguidos');
    });

    test('sin nota en ninguno: null (la UI usa la categoría)', () {
      final ms = [for (final p in threePaid) paid(45, p.day)];
      expect(recurringPayments(ms, today: today).single.note, isNull);
    });
  });

  group('pickTop', () {
    test('máximo 4, en orden de prioridad; "sale más" primero', () {
      final facts = <Fact>[
        const WeekdayFact(weekday: 6, avgCents: 6000),
        const StreakFact(days: 4, thresholdCents: 3000),
        CategoryChange(categoryId: 'ocio', deltaCents: -3000, percent: -40, previousMonth: day(2026, 9, 1)),
        const DaysLeftFact(days: 17, balanceCents: 85000, dailyCents: 5000),
        CategoryChange(categoryId: 'comida', deltaCents: 12000, percent: 35, previousMonth: day(2026, 9, 1)),
        const BalanceFact(cents: -15000),
        const StreakFact(days: 9, thresholdCents: 3000),
      ];
      expect(pickTop(facts).map((f) => f.runtimeType.toString() + (f is CategoryChange ? '${f.deltaCents > 0}' : '')),
          ['BalanceFact', 'CategoryChangetrue', 'DaysLeftFact', 'StreakFact']);
      expect((pickTop(facts)[3] as StreakFact).days, 9, reason: 'racha de 7+ antes que la de 3-6');
    });

    test('ahorro va después de los días restantes; la bajada y el día de la semana al final', () {
      final facts = <Fact>[
        const WeekdayFact(weekday: 6, avgCents: 6000),
        CategoryChange(categoryId: 'ocio', deltaCents: -3000, percent: -40, previousMonth: day(2026, 9, 1)),
        const BalanceFact(cents: 30000),
        const DaysLeftFact(days: 17, balanceCents: 85000, dailyCents: 5000),
      ];
      expect(pickTop(facts).map((f) => f.runtimeType.toString()),
          ['DaysLeftFact', 'BalanceFact', 'CategoryChange', 'WeekdayFact']);
    });
  });
}
