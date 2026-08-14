import 'package:flutter_test/flutter_test.dart';

import 'package:saldo_claro/core/utils/regex_parser.dart';

void main() {
  group('RegexParser', () {
    test('Yape - Enviaste', () {
      final result = RegexParser.parse(
        title: 'Yape',
        text: 'Enviaste S/ 25.50 a Maria Perez',
        packageName: 'com.bcp.innovacxion.yapeApp',
      );
      expect(result, isNotNull);
      expect(result!.amount, 25.50);
      expect(result.isExpense, isTrue);
      expect(result.merchantOrPerson, contains('Maria'));
    });

    test('Yape - Te yapeó', () {
      final result = RegexParser.parse(
        title: 'Yape',
        text: 'Te yapeó S/ 100.00 Juan Carlos',
        packageName: 'com.bcp.innovacxion.yapeApp',
      );
      expect(result, isNotNull);
      expect(result!.amount, 100.00);
      expect(result.isExpense, isFalse);
    });

    test('BCP - Transferencia efectuada', () {
      final result = RegexParser.parse(
        title: 'BCP',
        text: 'Transferencia efectuada por S/ 320.00 a Restaurante Donde Rosa',
        packageName: 'com.bcp.bank.bcp',
      );
      expect(result, isNotNull);
      expect(result!.amount, 320.00);
      expect(result.isExpense, isTrue);
    });

    test('BCP - Compra con tarjeta', () {
      final result = RegexParser.parse(
        title: 'BCP',
        text: 'Compra con tarjeta BCP por S/ 12,450.00 en Plaza Vea',
        packageName: 'com.bcp.bank.bcp',
      );
      expect(result, isNotNull);
      expect(result!.amount, 12450.00);
    });

    test('Yape INGRESO real: te envió un pago por S/ (con código de seguridad)', () {
      final result = RegexParser.parse(
        title: 'Confirmación de Pago',
        text: 'Amelia Ant* te envió un pago por S/ 1. El cód. de seguridad es: 557',
        packageName: 'com.bcp.innovacxion.yapeApp',
      );
      expect(result, isNotNull);
      expect(result!.amount, 1.0);
      expect(result.isExpense, isFalse);
      expect(result.merchantOrPerson, contains('Amelia'));
    });

    test('Lemon INGRESO real: Recibiste S/ + remitente del texto (con emoji)', () {
      final result = RegexParser.parse(
        title: 'Recibiste S/ 2 🙌',
        text: 'EDSON DUBERLY MORE ANTON te envió dinero. Ya lo puedes encontrar en tu cuenta.',
        packageName: 'com.lemon.lemoncash',
      );
      expect(result, isNotNull);
      expect(result!.amount, 2.0);
      expect(result.isExpense, isFalse);
      expect(result.merchantOrPerson, contains('EDSON'));
    });

    test('Agora/Sip INGRESO real: te pagó S/ (pe.agora.app)', () {
      final result = RegexParser.parse(
        title: 'Tarjeta de Débito | Recibiste un pago',
        text: 'Edson Duberly More Anton te pagó S/1.60',
        packageName: 'pe.agora.app',
      );
      expect(result, isNotNull);
      expect(result!.amount, closeTo(1.60, 0.001));
      expect(result.isExpense, isFalse);
      expect(result.merchantOrPerson, contains('Edson'));
    });

    test('Agora/Sip INGRESO real: package alternativo com.agora.app', () {
      final result = RegexParser.parse(
        title: 'Tarjeta de Débito | Recibiste un pago',
        text: 'Edson Duberly More Anton te pagó S/1.60',
        packageName: 'com.agora.app',
      );
      expect(result, isNotNull);
      expect(result!.amount, closeTo(1.60, 0.001));
      expect(result.isExpense, isFalse);
      expect(result.merchantOrPerson, contains('Edson'));
    });

    test('Limpieza: emojis y espacios extra no rompen el parseo', () {
      final result = RegexParser.parse(
        title: 'Recibiste  S/  3  💸 🎉',
        text: 'JUANA   PEREZ  te envió dinero. Ya acreditado.',
        packageName: 'com.lemon.lemoncash',
      );
      expect(result, isNotNull);
      expect(result!.amount, 3.0);
      expect(result.isExpense, isFalse);
      expect(result.merchantOrPerson, contains('JUANA'));
    });

    test('Retorna null si no hay coincidencia', () {
      final result = RegexParser.parse(
        title: 'Noticia',
        text: 'El clima hoy estará soleado',
        packageName: 'com.bcp.bank.bcp',
      );
      expect(result, isNull);
    });
  });
}
