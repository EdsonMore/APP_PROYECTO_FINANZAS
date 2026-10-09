import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/domain/metrics.dart';

final today = day(2026, 10, 8);

Movement exp(int soles, DateTime on, {String cat = 'comida'}) =>
    Movement(kind: EntryKind.expense, cents: soles * 100, day: on, categoryId: cat);

Movement inc(int soles, DateTime on) =>
    Movement(kind: EntryKind.income, cents: soles * 100, day: on);

DateTime ago(int n) => today.subtract(Duration(days: n));

void main() {
  group('balance', () {
    test('sin datos es 0', () {
      expect(balance(const [], today: today), 0);
    });

    test('suma ingresos y resta gastos', () {
      expect(balance([inc(100, ago(2)), exp(30, ago(1))], today: today), 7000);
    });

    test('ignora eventos con fecha futura', () {
      expect(balance([inc(100, ago(1)), exp(50, today.add(const Duration(days: 1)))], today: today), 10000);
    });

    test('dos ingresos el mismo día se suman sin importar el orden', () {
      final a = [inc(40, ago(1)), inc(60, ago(1)), exp(10, ago(1))];
      expect(balance(a, today: today), 9000);
      expect(balance(a.reversed.toList(), today: today), 9000);
    });

    test('saldo inicial: eventos anteriores ya están reflejados y no cuentan', () {
      final setAt = DateTime(2026, 10, 8, 12);
      final m = [
        exp(30, ago(1)), // antes del saldo inicial: ya incluido en los 800
        Movement(kind: EntryKind.expense, cents: 1000, day: today, createdAt: DateTime(2026, 10, 8, 9)),
        Movement(kind: EntryKind.expense, cents: 2000, day: today, createdAt: DateTime(2026, 10, 8, 13)),
      ];
      final b = balance(m, today: today, opening: Opening(cents: 80000, setAt: setAt));
      expect(b, 80000 - 2000);
    });
  });

  group('effectiveDays', () {
    test('sin historial es 1 (nunca divide por cero)', () {
      expect(effectiveDays(first: null, today: today, window: 14), 1);
    });

    test('historial corto usa los días reales, inclusivo', () {
      expect(effectiveDays(first: ago(2), today: today, window: 14), 3);
    });

    test('historial largo se recorta a la ventana', () {
      expect(effectiveDays(first: ago(100), today: today, window: 14), 14);
    });
  });

  group('avgDailyExpense', () {
    test('sin datos es 0', () {
      expect(avgDailyExpense(const [], today: today, window: 14), 0);
    });

    test('divide por días efectivos, no por la ventana completa', () {
      // primer evento hace 4 días -> D = 5
      final m = [exp(50, ago(4)), exp(50, ago(0))];
      expect(avgDailyExpense(m, today: today, window: 14), 2000);
    });

    test('el primer ingreso cuenta para D aunque no sea gasto', () {
      final m = [inc(500, ago(9)), exp(100, ago(0))];
      expect(avgDailyExpense(m, today: today, window: 14), 1000);
    });

    test('gastos fuera de la ventana no cuentan', () {
      final m = [exp(999, ago(20)), exp(140, ago(1))];
      expect(avgDailyExpense(m, today: today, window: 14), 1000);
    });
  });

  group('runway', () {
    test('sin datos -> empty', () {
      expect(runway(const [], today: today).status, RunwayStatus.empty);
    });

    test('B <= 0 -> noCushion con 0 días', () {
      final r = runway([exp(50, ago(10))], today: today);
      expect(r.status, RunwayStatus.noCushion);
      expect(r.days, 0);
    });

    test('B = 0 exacto también es noCushion', () {
      final r = runway([inc(50, ago(10)), exp(50, ago(9))], today: today);
      expect(r.status, RunwayStatus.noCushion);
    });

    test('sin gasto en la ventana -> noSpending (no divide por cero)', () {
      final r = runway([exp(10, ago(30)), inc(500, ago(29))], today: today);
      expect(r.status, RunwayStatus.noSpending);
    });

    test('calcula floor(B / g) con aritmética entera', () {
      // 14 días de historial, gasto 14 * S/10 = 140 -> g = S/10; B = 1000 - 140 = 860 -> 86 días
      final m = [inc(1000, ago(13)), for (var i = 0; i < 14; i++) exp(10, ago(i))];
      final r = runway(m, today: today);
      expect(r.status, RunwayStatus.days);
      expect(r.days, 86);
      expect(r.estimated, isFalse);
    });

    test('floor, no redondeo', () {
      // D = 3, G = 30 -> g = 10; B = 59 - 30 = 29 -> 2.9 -> 2
      final m = [inc(59, ago(2)), exp(30, ago(0))];
      expect(runway(m, today: today).days, 2);
    });

    test('D < 7 -> estimated', () {
      final m = [inc(100, ago(2)), exp(10, ago(0))];
      expect(runway(m, today: today).estimated, isTrue);
    });

    test('D = 7 ya no es estimado', () {
      final m = [inc(100, ago(6)), exp(10, ago(0))];
      expect(runway(m, today: today).estimated, isFalse);
    });

    test('R > 999 se recorta a 999 con capped', () {
      final m = [inc(100000, ago(13)), exp(1, ago(0))];
      final r = runway(m, today: today);
      expect(r.days, 999);
      expect(r.capped, isTrue);
    });

    test('solo saldo inicial sin eventos -> noSpending, no empty', () {
      final r = runway(const [], today: today, opening: Opening(cents: 50000, setAt: DateTime(2026, 10, 8, 8)));
      expect(r.status, RunwayStatus.noSpending);
    });

    test('ventana configurable', () {
      // ventana 7: solo cuenta el último gasto de S/70 -> g = 10; B = 1000 - 70 - 700 = 230 -> 23
      final m = [inc(1000, ago(29)), exp(700, ago(20)), exp(70, ago(0))];
      expect(runway(m, today: today, window: 7).days, 23);
    });
  });

  group('avgIncome30', () {
    test('sin ingresos es 0', () {
      expect(avgIncome30([exp(10, ago(1))], today: today), 0);
    });

    test('normaliza a 30 días con historial corto', () {
      // D = 10, I = 100 -> 100 * 30 / 10 = 300
      final m = [exp(1, ago(9)), inc(100, ago(0))];
      expect(avgIncome30(m, today: today), 30000);
    });

    test('ventana 90 normalizada a 30', () {
      final m = [inc(900, ago(89)), inc(900, ago(0))];
      expect(avgIncome30(m, today: today, window: 90), 60000);
    });

    test('ingreso fuera de la ventana no cuenta', () {
      final m = [inc(500, ago(45)), inc(300, ago(1))];
      expect(avgIncome30(m, today: today, window: 30), 30000);
    });

    test('ventana inválida falla', () {
      expect(() => avgIncome30(const [], today: today, window: 45), throwsArgumentError);
    });
  });

  group('entryExitRatio', () {
    Light light(List<Movement> m) => entryExitRatio(m, today: today).light;

    test('sin movimientos -> none', () {
      expect(light(const []), Light.none);
    });

    test('solo ingresos -> green', () {
      expect(light([inc(10, ago(1))]), Light.green);
    });

    test('entró igual que salió -> green', () {
      expect(light([inc(100, ago(1)), exp(100, ago(1))]), Light.green);
    });

    test('entró 70% exacto -> amber', () {
      expect(light([inc(70, ago(1)), exp(100, ago(1))]), Light.amber);
    });

    test('entró 69.99% -> red', () {
      final m = [
        Movement(kind: EntryKind.income, cents: 6999, day: ago(1)),
        exp(100, ago(1)),
      ];
      expect(light(m), Light.red);
    });

    test('sin ingresos y con gastos -> red', () {
      expect(light([exp(5, ago(1))]), Light.red);
    });

    test('expone los totales de 30 días', () {
      final r = entryExitRatio([inc(80, ago(1)), exp(100, ago(2)), exp(999, ago(40))], today: today);
      expect(r.incomeCents, 8000);
      expect(r.expenseCents, 10000);
    });
  });

  group('streak', () {
    test('sin datos es 0', () {
      expect(streak(const [], today: today, thresholdCents: 1000), 0);
    });

    test('cuenta días consecutivos dentro del umbral desde hoy hacia atrás', () {
      final m = [exp(50, ago(5)), exp(5, ago(4)), exp(9, ago(2)), exp(10, ago(0))];
      // umbral S/10: ago5 rompe; ago4..hoy ok (ago3 y ago1 sin gasto) -> 5
      expect(streak(m, today: today, thresholdCents: 1000), 5);
    });

    test('hoy fuera del umbral -> 0', () {
      expect(streak([exp(1, ago(3)), exp(11, ago(0))], today: today, thresholdCents: 1000), 0);
    });

    test('no cuenta días antes del primer evento', () {
      expect(streak([exp(1, ago(2))], today: today, thresholdCents: 1000), 3);
    });

    test('suma varios gastos del mismo día', () {
      expect(streak([exp(6, ago(0)), exp(6, ago(0))], today: today, thresholdCents: 1000), 0);
    });
  });

  group('streakThreshold', () {
    test('Estable con techos: Σ techos / días del mes', () {
      // octubre = 31 días
      final t = streakThreshold(const [], today: today, mode: Mode.stable, capsCents: const {'a': 31000, 'b': 31000});
      expect(t, 2000);
    });

    test('con ingreso típico: ingreso típico / 30', () {
      final m = [inc(300, ago(29)), exp(1, ago(0))];
      expect(streakThreshold(m, today: today, mode: Mode.variable), 1000);
    });

    test('sin ingreso: g de los últimos 14 días desde hoy (congelado)', () {
      final m = [for (var i = 0; i < 14; i++) exp(7, ago(i))];
      expect(streakThreshold(m, today: today, mode: Mode.survival), 700);
    });

    test('sin datos -> null (no se muestra racha)', () {
      expect(streakThreshold(const [], today: today, mode: Mode.survival), isNull);
    });

    test('Estable sin techos cae a la regla de ingreso', () {
      final m = [inc(300, ago(29)), exp(1, ago(0))];
      expect(streakThreshold(m, today: today, mode: Mode.stable), 1000);
    });
  });

  group('suggestedCaps', () {
    test('sin gastos -> vacío', () {
      expect(suggestedCaps([inc(100, ago(1))], today: today), isEmpty);
    });

    test('mensualiza 90 días efectivos y redondea a S/10', () {
      // D = 90, comida 900 -> 300; transporte 95 -> 31.67 -> 30
      final m = [
        exp(450, ago(89), cat: 'comida'),
        exp(450, ago(0), cat: 'comida'),
        exp(95, ago(10), cat: 'transporte'),
      ];
      expect(suggestedCaps(m, today: today), {'comida': 30000, 'transporte': 3000});
    });

    test('mínimo S/10 si hubo gasto', () {
      final m = [exp(1, ago(89)), exp(1, ago(0))];
      expect(suggestedCaps(m, today: today), {'comida': 1000});
    });
  });

  group('modeFor', () {
    test('Mixto mapea a variable', () {
      expect(modeFor(IncomeProfile.mixed), Mode.variable);
      expect(modeFor(IncomeProfile.none), Mode.survival);
    });
  });
}
