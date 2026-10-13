import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/domain/metrics.dart';

final today = day(2026, 10, 13);
DateTime at(int d, [int h = 12]) => DateTime(2026, 10, d, h);

Movement out(int cents, int d, {String? acc, int h = 12}) =>
    Movement(kind: EntryKind.expense, cents: cents, day: day(2026, 10, d), categoryId: 'comida', createdAt: at(d, h), accountId: acc);
Movement inc(int cents, int d, {String? acc, int h = 12}) =>
    Movement(kind: EntryKind.income, cents: cents, day: day(2026, 10, d), createdAt: at(d, h), accountId: acc);
Transfer tr(int cents, int d, {String? from, String? to, int h = 12}) =>
    Transfer(fromAccountId: from, toAccountId: to, cents: cents, day: day(2026, 10, d), createdAt: at(d, h));

void main() {
  group('equivalencia: sin cuentas ni transferencias, el saldo global es el de siempre', () {
    final opening = Opening(cents: 30000, setAt: at(5));
    final cases = <String, List<Movement>>{
      'vacío': [],
      'gastos e ingresos': [out(1000, 6), inc(5000, 7), out(250, 13)],
      'antes del saldo inicial (ya incluido)': [out(999, 4), out(500, 5, h: 9), inc(100, 5, h: 15)],
      'fecha futura': [out(700, 20)],
    };
    for (final MapEntry(key: name, value: ms) in cases.entries) {
      test(name, () {
        for (final o in [null, opening]) {
          expect(totalBalance(ms, const [], today: today, unassignedOpening: o), balance(ms, today: today, opening: o));
        }
      });
    }
  });

  test('saldo por cuenta: ingresos, gastos y transferencias de ida y vuelta', () {
    final ms = [inc(50000, 1, acc: 'yape'), out(1200, 2, acc: 'yape'), out(800, 3, acc: 'efectivo')];
    final ts = [tr(10000, 4, from: 'yape', to: 'efectivo'), tr(500, 5, from: 'efectivo', to: 'yape')];
    expect(accountBalance('yape', ms, ts, today: today), 50000 - 1200 - 10000 + 500);
    expect(accountBalance('efectivo', ms, ts, today: today), -800 + 10000 - 500);
    expect(accountBalance(null, ms, ts, today: today), 0, reason: '"Sin asignar" no tiene nada');
    expect(totalBalance(ms, ts, today: today), 50000 - 1200 - 800, reason: 'las transferencias se cancelan en el global');
  });

  test('"Sin asignar": movimientos sin cuenta + el saldo inicial de settings; transferencias desde y hacia ahí', () {
    final ms = [out(1000, 6), inc(2000, 7, acc: 'yape')];
    final ts = [tr(5000, 8, from: null, to: 'yape'), tr(300, 9, from: 'yape', to: null)];
    final opening = Opening(cents: 30000, setAt: at(5));
    expect(accountBalance(null, ms, ts, today: today, opening: opening), 30000 - 1000 - 5000 + 300);
    expect(accountBalance('yape', ms, ts, today: today), 2000 + 5000 - 300);
    expect(totalBalance(ms, ts, today: today, unassignedOpening: opening), 30000 - 1000 + 2000);
  });

  test('saldo inicial por cuenta: lo de antes de su instante ya estaba incluido (también transferencias)', () {
    final yape = Opening(cents: 20000, setAt: at(10, 12));
    final ms = [out(400, 9, acc: 'yape'), out(300, 10, acc: 'yape', h: 9), out(200, 10, acc: 'yape', h: 15)];
    final ts = [tr(1000, 10, from: 'yape', to: 'efectivo', h: 8)]; // antes del saldo de Yape, no del efectivo
    expect(accountBalance('yape', ms, ts, today: today, opening: yape), 20000 - 200);
    expect(accountBalance('efectivo', ms, ts, today: today), 1000);
    expect(totalBalance(ms, ts, today: today, accountOpenings: {'yape': yape}), 20000 - 200 + 1000,
        reason: 'la transferencia cuenta solo del lado que no la tenía incluida');
  });

  test('cuentas sin movimientos pero con saldo inicial (p. ej. archivadas) suman en el global', () {
    final ops = {'vieja': Opening(cents: 7000, setAt: at(1))};
    expect(totalBalance(const [], const [], today: today, accountOpenings: ops), 7000);
  });

  group('R1 (fase-4a): runway, serie, calculadora y firstDay usan el saldo global', () {
    final opening = Opening(cents: 30000, setAt: at(1));
    final ms = [out(1000, 2), inc(500, 3), out(2000, 5), out(700, 13)];

    test('sin cuentas (libro vacío): idénticos a los de siempre', () {
      const book = AccountBook();
      for (final o in [null, opening]) {
        expect(runway(ms, today: today, opening: o, book: book).days, runway(ms, today: today, opening: o).days);
        expect(runwaySeries(ms, today: today, opening: o, book: book), runwaySeries(ms, today: today, opening: o));
        expect(dailyAllowance(ms, today: today, days: 14, opening: o, book: book),
            dailyAllowance(ms, today: today, days: 14, opening: o));
        expect(firstDay(ms, today: today, opening: o, book: book), firstDay(ms, today: today, opening: o));
      }
    });

    test('con el saldo inicial de una cuenta, el runway y la calculadora lo suman', () {
      final book = AccountBook(openings: {'yape': Opening(cents: 60000, setAt: at(1))});
      final plain = runway(ms, today: today, opening: opening);
      final withYape = runway(ms, today: today, opening: opening, book: book);
      expect(withYape.days, greaterThan(plain.days));
      final a = dailyAllowance(ms, today: today, days: 10, opening: opening, book: book)!;
      expect(a.limitCents, (30000 - 1000 + 500 - 2000 + 60000) ~/ 10, reason: 'el saldo con el que empezó el día');
    });

    test('solo con saldo inicial de cuenta (sin global): hay datos desde ese día', () {
      final book = AccountBook(openings: {'yape': Opening(cents: 5000, setAt: at(4))});
      expect(firstDay(const [], today: today, book: book), day(2026, 10, 4));
      expect(runway(const [], today: today, book: book).status, RunwayStatus.noSpending);
      expect(runwaySeries([out(100, 13, acc: 'yape')], today: today, book: book), hasLength(10), reason: 'del 4 al 13');
    });

    test('gastado hoy cuenta según el saldo inicial DE SU cuenta', () {
      final yape = Opening(cents: 10000, setAt: at(13, 12));
      final book = AccountBook(openings: {'yape': yape});
      final today2 = [out(300, 13, acc: 'yape', h: 9), out(200, 13, acc: 'yape', h: 15), out(100, 13, h: 9)];
      final a = dailyAllowance(today2, today: today, days: 1, opening: opening, book: book)!;
      expect(a.spentTodayCents, 200 + 100, reason: 'el gasto de Yape antes de su saldo ya estaba incluido');
    });
  });

  test('transferencias con fecha futura se ignoran', () {
    final ts = [tr(999, 20, from: 'yape', to: 'efectivo')];
    expect(accountBalance('yape', const [], ts, today: today), 0);
    expect(accountBalance('efectivo', const [], ts, today: today), 0);
  });
}
