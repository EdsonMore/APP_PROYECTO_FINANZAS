import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/domain/recurrence.dart';
import 'package:saldo_claro/features/ai/ai_client.dart';
import 'package:saldo_claro/features/ai/facts.dart';

Movement out(int soles, DateTime d, [String cat = 'comida']) =>
    Movement(kind: EntryKind.expense, cents: soles * 100, day: d, categoryId: cat);
Movement inc(int soles, DateTime d) => Movement(kind: EntryKind.income, cents: soles * 100, day: d);

ReminderFact rem(String cat, int cents, DateTime due, [Frequency f = Frequency.monthly]) =>
    (categoryId: cat, cents: cents, frequency: f, due: due);

const names = {'comida': 'Comida', 'ocio': 'Ocio', 'vivienda': 'Vivienda', 'salud': 'Salud'};

FactsSource src(List<Movement> ms, DateTime today, {List<ReminderFact> reminders = const []}) =>
    FactsSource(movements: ms, today: today, mode: Mode.variable, reminders: reminders, categoryNames: names);

void main() {
  final oct14 = day(2026, 10, 14);

  test('base: saldo, días del mes, sugerencia diaria y el mes', () {
    expect(baseFacts(src([inc(900, day(2026, 10, 1))], oct14)), {
      'mode': 'variable',
      'balanceCents': 90000,
      'daysLeft': 18,
      'dailyCents': 5000,
      'monthIncomeCents': 90000,
      'monthSpentCents': 0,
    });
  });

  test('can_spend: lo que queda tras X, por día, runway simulado y pendientes del mes', () {
    final s = src([inc(900, day(2026, 10, 1))], oct14, reminders: [
      rem('vivienda', 4500, day(2026, 10, 16)),
      rem('vivienda', 8700, day(2026, 10, 23)),
      rem('salud', 35000, day(2027, 3, 4), Frequency.yearly), // fuera del mes
    ]);
    final f = factsFor(AiQuestion.canSpend, s, amountCents: 12000);
    expect(f['amountCents'], 12000);
    expect(f['balanceAfterCents'], 78000);
    expect(f['dailyAfterCents'], 4333, reason: '78000 / 18 días');
    expect(f.containsKey('runwayDays'), isFalse, reason: 'sin gasto todavía no hay runway');
    expect(f['runwayAfterDays'], 91, reason: '78000 · 14 / 12000');
    expect(f['pending'], [
      {'category': 'Vivienda', 'amountCents': 4500, 'daysToDue': 2},
      {'category': 'Vivienda', 'amountCents': 8700, 'daysToDue': 9},
    ]);
    expect((f['pendingTotalCents'], f['balanceAfterPendingCents']), (13200, 64800));
  });

  test('what_if: neto mensual y runway, con y sin el extra', () {
    final s = src([inc(3000, day(2026, 10, 1)), out(900, day(2026, 10, 1))], day(2026, 10, 30));
    final f = factsFor(AiQuestion.whatIf, s, amountCents: 30000);
    expect(
        [for (final k in ['avgIncome30Cents', 'avgExpense30Cents', 'expenseWithExtraCents', 'monthlyNetCents',
            'monthlyNetWithExtraCents', 'runwayDays', 'runwayWithExtraDays']) f[k]],
        [300000, 90000, 120000, 210000, 180000, 70, 52]);
  });

  group('break_even', () {
    test('fijos llevados a mes (semanal ×52/12, anual /12), variables y meta +10%', () {
      final s = src([out(900, day(2026, 10, 1))], day(2026, 10, 30), reminders: [
        rem('ocio', 2000, day(2026, 11, 2), Frequency.weekly),
        rem('salud', 35000, day(2027, 3, 4), Frequency.yearly),
        rem('vivienda', 4500, day(2026, 11, 17)),
      ]);
      final f = factsFor(AiQuestion.breakEven, s);
      expect(f['fixed'], [
        {'category': 'Ocio', 'monthlyCents': 8667},
        {'category': 'Salud', 'monthlyCents': 2917},
        {'category': 'Vivienda', 'monthlyCents': 4500},
      ]);
      expect([for (final k in ['avgExpense30Cents', 'fixedMonthlyCents', 'variableMonthlyCents', 'targetCents', 'targetComfortCents']) f[k]],
          [90000, 16084, 73916, 90000, 99000]);
    });

    test('los variables nunca son negativos; trae el ingreso de los meses cerrados', () {
      final s = src([inc(1000, day(2026, 8, 1)), inc(1200, day(2026, 9, 3)), out(50, day(2026, 10, 1))], day(2026, 10, 15),
          reminders: [rem('vivienda', 90000, day(2026, 11, 1))]);
      final f = factsFor(AiQuestion.breakEven, s);
      expect(f['variableMonthlyCents'], 0);
      expect(f['incomeByMonth'], [
        {'month': '2026-08', 'incomeCents': 100000},
        {'month': '2026-09', 'incomeCents': 120000},
      ]);
    });

    test('incomeByMonth: el primer mes cuenta aunque empiece a mitad (partial), como en save', () {
      // Caso real: empezó a usar la app el 10 de septiembre; hoy es 17 de octubre.
      final s = src([inc(2500, day(2026, 9, 10)), out(300, day(2026, 9, 12)), inc(2500, day(2026, 10, 5))], day(2026, 10, 17));
      expect(factsFor(AiQuestion.breakEven, s)['incomeByMonth'], [
        {'month': '2026-09', 'incomeCents': 250000, 'partial': true},
      ]);
    });

    test('incomeByMonth: como mucho los 3 últimos meses cerrados; el viejo no lleva partial', () {
      final s = src([
        inc(100, day(2026, 5, 20)),
        for (var m = 6; m <= 9; m++) inc(m * 100, day(2026, m, 3)),
      ], day(2026, 10, 17));
      expect(factsFor(AiQuestion.breakEven, s)['incomeByMonth'], [
        {'month': '2026-07', 'incomeCents': 70000},
        {'month': '2026-08', 'incomeCents': 80000},
        {'month': '2026-09', 'incomeCents': 90000},
      ]);
    });
  });

  test('cut: 30 días por categoría, de mayor a menor, con la mitad y si es fija', () {
    final today = day(2026, 10, 15);
    final s = src([
      for (var i = 0; i < 3; i++) out(20, today.subtract(Duration(days: i))),
      out(150, day(2026, 10, 10), 'ocio'),
      out(45, day(2026, 10, 5), 'vivienda'),
      out(999, day(2026, 9, 1), 'ocio'), // hace más de 30 días
    ], today, reminders: [rem('vivienda', 4500, day(2026, 11, 5))]);
    expect(factsFor(AiQuestion.cut, s)['categories'], [
      {'category': 'Ocio', 'totalCents': 15000, 'count': 1, 'avgTicketCents': 15000, 'halfCents': 7500, 'fixed': false},
      {'category': 'Comida', 'totalCents': 6000, 'count': 3, 'avgTicketCents': 2000, 'halfCents': 3000, 'fixed': false},
      {'category': 'Vivienda', 'totalCents': 4500, 'count': 1, 'avgTicketCents': 4500, 'halfCents': 2250, 'fixed': true},
    ]);
  });

  test('cut: máximo 6 categorías', () {
    final today = day(2026, 10, 15);
    final s = src([for (var i = 0; i < 8; i++) out(10 + i, today, 'c$i')], today);
    expect((factsFor(AiQuestion.cut, s)['categories'] as List).length, 6);
  });

  test('save: meses cerrados, sobrante promedio de los meses en verde, meses en rojo y 10% del ingreso', () {
    final s = src([
      inc(1000, day(2026, 8, 1)), out(800, day(2026, 8, 20)), // desde el día 1: agosto cuenta (como Tus meses)
      inc(1000, day(2026, 9, 2)), out(1200, day(2026, 9, 20)),
      inc(5000, day(2026, 10, 2)), // mes en curso: no cuenta
    ], day(2026, 10, 15));
    final f = factsFor(AiQuestion.save, s);
    expect(f['months'], [
      {'month': '2026-08', 'incomeCents': 100000, 'expenseCents': 80000, 'netCents': 20000},
      {'month': '2026-09', 'incomeCents': 100000, 'expenseCents': 120000, 'netCents': -20000},
    ]);
    expect((f['avgSurplusCents'], f['surplusMonths'], f['redMonths'], f['tenPercentIncomeCents']), (20000, 1, 1, 10000));
  });

  test('save: el primer mes cuenta aunque empiece a mitad (marcado partial); el bug era months vacío', () {
    // Caso real: empezó a usar la app el 10 de septiembre; hoy es 17 de octubre.
    final s = src([
      inc(2500, day(2026, 9, 10)), out(300, day(2026, 9, 12)), out(400, day(2026, 9, 25)),
      inc(2500, day(2026, 10, 5)), out(200, day(2026, 10, 8)),
    ], day(2026, 10, 17));
    final f = factsFor(AiQuestion.save, s);
    expect(f['months'], [
      {'month': '2026-09', 'incomeCents': 250000, 'expenseCents': 70000, 'netCents': 180000, 'partial': true},
    ]);
    expect((f['avgSurplusCents'], f['surplusMonths'], f['redMonths']), (180000, 1, 0));
  });

  test('save: sin meses cerrados igual lleva los promedios de 30 días', () {
    final s = src([inc(2500, day(2026, 10, 5)), out(200, day(2026, 10, 8))], day(2026, 10, 17));
    final f = factsFor(AiQuestion.save, s);
    expect(f['months'], isEmpty);
    expect((f['avgIncome30Cents'], f['avgExpense30Cents'], f['net30Cents']), (576923, 46154, 530769),
        reason: '13 días desde el 5: 2500 · 30 / 13 y 200 · 30 / 13');
    expect(f.containsKey('avgSurplusCents'), isFalse);
  });

  group('can_afford_installment', () {
    // Ingreso 2500 y gasto 1800 en los últimos 30 días (del 1 al 30 de octubre).
    final s = src([inc(2500, day(2026, 10, 1)), out(1800, day(2026, 10, 1))], day(2026, 10, 30));

    test('cuota de 100: sobran 600 (2500 - 1800 - 100)', () {
      final f = factsFor(AiQuestion.installment, s, amountCents: 10000);
      expect([for (final k in ['amountCents', 'avgIncome30Cents', 'avgExpense30Cents', 'monthlyNetCents', 'leftoverCents']) f[k]],
          [10000, 250000, 180000, 70000, 60000]);
      expect(f.containsKey('shortfallCents'), isFalse);
    });

    test('cuota de 800: faltan 100', () {
      final f = factsFor(AiQuestion.installment, s, amountCents: 80000);
      expect(f['shortfallCents'], 10000);
      expect(f.containsKey('leftoverCents'), isFalse);
    });

    test('cuota justa: sobra 0 (alcanza)', () {
      expect(factsFor(AiQuestion.installment, s, amountCents: 70000)['leftoverCents'], 0);
    });
  });

  test('pay_first: vencidos y a 7 días o menos (como "Por pagar"), total y lo que falta', () {
    final s = src([inc(100, day(2026, 10, 1))], day(2026, 10, 15), reminders: [
      rem('salud', 8700, day(2026, 10, 20)),
      rem('vivienda', 4500, day(2026, 10, 10)),
      rem('ocio', 2000, day(2026, 10, 30)), // a 15 días: no
    ]);
    final f = factsFor(AiQuestion.payFirst, s);
    expect(f['pending'], [
      {'category': 'Vivienda', 'amountCents': 4500, 'daysToDue': -5},
      {'category': 'Salud', 'amountCents': 8700, 'daysToDue': 5},
    ]);
    expect((f['pendingTotalCents'], f['shortfallCents']), (13200, 3200));
    expect(duePendingCount(s), 2);
  });

  test('pay_first: si el saldo alcanza, no falta nada', () {
    final s = src([inc(1000, day(2026, 10, 1))], day(2026, 10, 15), reminders: [rem('vivienda', 4500, day(2026, 10, 16))]);
    expect(factsFor(AiQuestion.payFirst, s)['shortfallCents'], 0);
  });

  test('free: base y resumen, menos de 8 KB aun con muchos datos', () {
    final today = day(2026, 10, 15);
    final s = src([
      for (var i = 0; i < 90; i++) out(10 + i % 7, today.subtract(Duration(days: i)), 'cat${i % 20}'),
      inc(3000, day(2026, 10, 1)),
    ], today, reminders: [for (var i = 0; i < 30; i++) rem('vivienda', 1000 + i, today.add(Duration(days: i % 8)))]);
    final f = factsFor(AiQuestion.free, s);
    expect((f['topCategories'] as List).length, 4);
    expect(f.keys, containsAll(['balanceCents', 'daysLeft', 'pending', 'avgIncome30Cents', 'avgExpense30Cents']));
    expect(utf8.encode(jsonEncode(f)).length, lessThan(8192));
  });

  test('C3: ningún paquete lleva notas, correo, ids ni fechas sueltas', () {
    final today = day(2026, 10, 15);
    final s = src([inc(900, day(2026, 9, 1)), out(30, day(2026, 10, 10), 'ocio')], today,
        reminders: [rem('vivienda', 4500, day(2026, 10, 16))]);
    void walk(Object? v) {
      if (v is Map) {
        for (final MapEntry(:key, :value) in v.entries) {
          expect(['note', 'notes', 'email', 'id', 'userId', 'day', 'date'].contains(key), isFalse, reason: '$key');
          walk(value);
        }
      } else if (v is List) {
        v.forEach(walk);
      }
    }
    for (final q in AiQuestion.values) {
      walk(factsFor(q, s, amountCents: 1000));
    }
  });
}
