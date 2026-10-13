import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/domain/metrics.dart';

final today = day(2026, 10, 13);

Movement out(int cents, DateTime d, {DateTime? at}) =>
    Movement(kind: EntryKind.expense, cents: cents, day: d, categoryId: 'comida', createdAt: at);
Movement inc(int cents, DateTime d, {DateTime? at}) => Movement(kind: EntryKind.income, cents: cents, day: d, createdAt: at);

void main() {
  // Empezó el día con S/ 300 (saldo inicial de ayer), hoy gastó S/ 20.
  final opening = Opening(cents: 30000, setAt: DateTime(2026, 10, 12, 9));
  final spent20 = [out(2000, today, at: DateTime(2026, 10, 13, 10))];

  test('el ejemplo de la ficha: límite S/ 21.43, te quedan hoy S/ 1.43', () {
    final a = dailyAllowance(spent20, today: today, days: 14, opening: opening)!;
    expect(a.limitCents, 2142, reason: 'floor(30000 / 14) = 2142');
    expect(a.leftTodayCents, 142);
    expect(a.spentTodayCents, 2000);
    expect(a.overCents, 0);
  });

  test('sin gasto hoy: te queda todo el límite', () {
    final a = dailyAllowance(const [], today: today, days: 10, opening: opening)!;
    expect(a.limitCents, 3000);
    expect(a.leftTodayCents, 3000);
  });

  test('gasto de hoy mayor que el límite: 0 y cuánto se pasó', () {
    final a = dailyAllowance([out(5000, today, at: DateTime(2026, 10, 13, 10))], today: today, days: 14, opening: opening)!;
    expect(a.limitCents, 2142);
    expect(a.leftTodayCents, 0);
    expect(a.overCents, 5000 - 2142);
  });

  test('saldo ≤ 0: sin reserva (null)', () {
    expect(dailyAllowance([out(30000, today, at: DateTime(2026, 10, 13, 10))], today: today, days: 7, opening: opening),
        isNull, reason: 'saldo justo 0');
    expect(dailyAllowance([out(500, today)], today: today, days: 7), isNull, reason: 'sin saldo inicial, negativo');
  });

  test('días = 1: puedes gastar todo el saldo de hoy', () {
    final a = dailyAllowance(spent20, today: today, days: 1, opening: opening)!;
    expect(a.limitCents, 30000);
    expect(a.leftTodayCents, 28000);
  });

  test('redondea hacia abajo al centavo', () {
    final a = dailyAllowance(const [], today: today, days: 3, opening: Opening(cents: 1000, setAt: DateTime(2026, 10, 12)))!;
    expect(a.limitCents, 333);
  });

  test('saldo inicial fijado HOY: un gasto de hoy anterior no cuenta (ya estaba en el saldo)', () {
    final o = Opening(cents: 30000, setAt: DateTime(2026, 10, 13, 12));
    final before = out(4000, today, at: DateTime(2026, 10, 13, 8)); // ya reflejado en los 300
    final after = out(2000, today, at: DateTime(2026, 10, 13, 15));
    final a = dailyAllowance([before, after], today: today, days: 14, opening: o)!;
    expect(a.spentTodayCents, 2000);
    expect(a.limitCents, 2142, reason: 'el día empezó (para la app) con 300');
  });

  test('fechas futuras se ignoran; un ingreso de hoy suma al saldo, no es gasto', () {
    final a = dailyAllowance([
      ...spent20,
      out(9999, day(2026, 10, 20)),
      inc(10000, today, at: DateTime(2026, 10, 13, 11)),
    ], today: today, days: 10, opening: opening)!;
    expect(a.spentTodayCents, 2000);
    expect(a.limitCents, 4000, reason: '(300 − 20 + 100 + 20) / 10');
  });

  test('días hasta una fecha: hoy y esa fecha inclusive', () {
    expect(daysUntil(day(2026, 10, 14), today: today), 2);
    expect(daysUntil(today, today: today), 1);
    expect(daysUntil(day(2026, 10, 31), today: today), 19);
  });
}
