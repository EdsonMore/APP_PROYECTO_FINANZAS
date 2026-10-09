import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/features/entry/amount_input.dart';

AmountInput type(String keys) {
  var a = const AmountInput();
  for (final k in keys.split('')) {
    a = a.press(k) ?? a;
  }
  return a;
}

void main() {
  group('centavos (enteros, nunca double)', () {
    for (final (keys, cents) in [
      ('', 0),
      ('0', 0),
      ('12', 1200),
      ('12.5', 1250),
      ('12.50', 1250),
      ('12.05', 1205),
      ('.05', 5),
      ('0.99', 99),
      ('999999.99', 99999999),
    ]) {
      test('"$keys" → $cents', () => expect(type(keys).cents, cents));
    }

    test('0.1 + 0.2 no tiene error de flotante: 0.30 → 30', () {
      expect(type('0.3').cents, 30);
    });
  });

  group('reglas de tecleo', () {
    test('"." con monto vacío escribe "0."', () => expect(type('.').text, '0.'));

    test('un solo "."', () {
      expect(type('1.').press('.'), isNull);
      expect(type('1.2.3').text, '1.23');
    });

    test('máximo 2 decimales', () {
      expect(type('1.25').press('9'), isNull);
      expect(type('1.259').text, '1.25');
    });

    test('máximo 6 dígitos enteros', () {
      expect(type('999999').press('9'), isNull);
      expect(type('9999999').text, '999999');
      expect(type('999999.99').cents, 99999999);
    });

    test('sin ceros a la izquierda', () {
      expect(type('05').text, '5');
      expect(type('0').press('0'), isNull);
      expect(type('00').text, '0');
      expect(type('0.5').text, '0.5');
    });

    test('tecla inválida lanza ArgumentError', () {
      expect(() => const AmountInput().press('a'), throwsArgumentError);
    });
  });

  group('backspace', () {
    test('borra el último carácter, incluido el "."', () {
      expect(type('12.5').backspace().text, '12.');
      expect(type('12.').backspace().text, '12');
    });

    test('vacío se queda vacío', () => expect(const AmountInput().backspace().isEmpty, isTrue));
  });

  group('display (tecleado + guía)', () {
    for (final (keys, typed, ghost) in [
      ('', '', '0.00'),
      ('12', '12', '.00'),
      ('12.', '12.', '00'),
      ('12.5', '12.5', '0'),
      ('12.50', '12.50', ''),
      ('1250', '1,250', '.00'),
      ('999999.9', '999,999.9', '0'),
    ]) {
      test('"$keys" → "$typed" + "$ghost"', () {
        expect(type(keys).display, (typed: typed, ghost: ghost));
      });
    }
  });
}
