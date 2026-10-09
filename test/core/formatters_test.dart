import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/core/utils/formatters.dart';

void main() {
  for (final (cents, text) in [
    (0, 'S/ 0.00'),
    (5, 'S/ 0.05'),
    (2500, 'S/ 25.00'),
    (125050, 'S/ 1,250.50'),
    (99999999, 'S/ 999,999.99'),
    (-350, '-S/ 3.50'),
  ]) {
    test('soles($cents) → "$text"', () => expect(Formatters.soles(cents), text));
  }

  test('currency(double) usa el mismo formato', () {
    expect(Formatters.currency(25), 'S/ 25.00');
    expect(Formatters.currency(0.1 + 0.2), 'S/ 0.30');
  });
}
