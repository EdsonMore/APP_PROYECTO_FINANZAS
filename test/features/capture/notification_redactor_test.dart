import 'package:flutter_test/flutter_test.dart';

import 'package:saldo_claro/core/utils/notification_redactor.dart';

/// Pruebas del redactor de datos sensibles: los códigos de seguridad (OTP)
/// que Yape y otras billeteras incluyen en las notificaciones NO deben
/// persistirse ni exponerse.
void main() {
  group('NotificationRedactor', () {
    test('Redacta "código de seguridad es: X"', () {
      const input = 'Juan Pérez te envió un pago por S/ 1. '
          'El código de seguridad es: 88342';
      final out = NotificationRedactor.redactSecurityCodes(input);

      expect(out, isNot(contains('88342')));
      expect(out, contains('[CÓDIGO_OCULTO]'));
      expect(out, contains('Juan Pérez te envió un pago por S/ 1.'));
    });

    test('Redacta la variante corta "cód. de seguridad es: X"', () {
      const input = 'Amelia Ant* te envió un pago por S/ 1. '
          'El cód. de seguridad es: 557';
      final out = NotificationRedactor.redactSecurityCodes(input);

      expect(out, isNot(contains('557')));
      expect(out, contains('[CÓDIGO_OCULTO]'));
    });

    test('Redacta "código de seguridad: X" sin "es"', () {
      const input = 'Código de seguridad: 42';
      final out = NotificationRedactor.redactSecurityCodes(input);
      expect(out, isNot(contains('42')));
      expect(out, contains('[CÓDIGO_OCULTO]'));
    });

    test('No altera texto sin código de seguridad', () {
      const input = 'Recibiste S/ 45.00 de María Fernanda Quispe';
      expect(
        NotificationRedactor.redactSecurityCodes(input),
        input,
      );
    });

    test('Redacta emojis o números residuales junto al placeholder', () {
      const input = 'Te envió un pago por S/ 1. Código de seguridad: 123. ✔';
      final out = NotificationRedactor.redactSecurityCodes(input);
      expect(out, isNot(contains('123')));
      expect(out, contains('[CÓDIGO_OCULTO]'));
    });

    test('redactForLog recorta el texto largo', () {
      final long = List.filled(50, 'abcdefghij').join();
      final out = NotificationRedactor.redactForLog(long, maxLength: 100);
      expect(out.length, lessThanOrEqualTo(101));
      expect(out, endsWith('…'));
    });
  });
}