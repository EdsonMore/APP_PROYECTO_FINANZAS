import 'package:flutter_test/flutter_test.dart';

import 'package:saldo_claro/core/models/transaction_type.dart';
import 'package:saldo_claro/core/utils/regex_parser.dart';

/// Pruebas exhaustivas del motor RegexParser con copys reales de
/// notificaciones de apps financieras peruanas (Yape, BCP, Plin, Agora/Sip,
/// Lemon Cash, Interbank y fallback genérico).
void main() {
  group('RegexParser Peru Financial Apps Tests', () {
    group('Yape', () {
      test('Yape - Recepción de dinero (copy real: "te ha enviado un pago")', () {
        // Copy real de Yape: "Yape! [Nombre del remitente] te ha enviado un
        // pago de S/ X". "Bienvenida" es el nombre de la persona, no un saludo.
        final input = 'Yape! Bienvenida te ha enviado un pago de S/ 4.07';
        final result = RegexParser.parse(
          title: 'Yape',
          text: input,
          packageName: 'com.bcp.innovacxion.yapeApp',
        );

        expect(result, isNotNull);
        expect(result!.amount, 4.07);
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, 'Bienvenida');
        expect(result.sourceApp, 'Yape');
      });

      test('Yape - "Bienvenida" es el nombre de la persona y el prefijo '
          '"Yape" NUNCA se cuela en el nombre', () {
        // El copy real trae el prefijo de marca antes del nombre.
        final withBang = RegexParser.parse(
          title: 'Yape',
          text: 'Yape! Bienvenida te ha enviado un pago de S/ 4.07',
          packageName: 'com.bcp.innovacxion.yapeApp',
        );
        expect(withBang, isNotNull);
        expect(withBang!.merchantOrPerson, 'Bienvenida');

        // Aunque la marca viniera sin "!" (variante defensiva), la persona
        // sigue siendo solo el nombre.
        final noBang = RegexParser.parse(
          title: 'Yape',
          text: 'Yape Bienvenida te ha enviado un pago de S/ 4.07',
          packageName: 'com.bcp.innovacxion.yapeApp',
        );
        expect(noBang, isNotNull);
        expect(noBang!.merchantOrPerson, 'Bienvenida');
      });

      test('Yape - "te ha enviado un pago de" con nombre compuesto completo', () {
        final result = RegexParser.parse(
          title: 'Yape',
          text: 'Yape! Juan Carlos Quispe Rojas te ha enviado un pago de S/ 12.50',
          packageName: 'com.bcp.innovacxion.yapeApp',
        );
        expect(result, isNotNull);
        expect(result!.amount, 12.50);
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, 'Juan Carlos Quispe Rojas');
      });

      test('Yape - copy completa en el TÍTULO y texto vacío', () {
        final result = RegexParser.parse(
          title: 'Yape! Bienvenida te ha enviado un pago de S/ 4.07',
          text: '',
          packageName: 'com.bcp.innovacxion.yapeApp',
        );
        expect(result, isNotNull);
        expect(result!.amount, 4.07);
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, 'Bienvenida');
      });

      test('Yape - Recepción con código de seguridad ("te envió un pago por")',
          () {
        final result = RegexParser.parse(
          title: 'Confirmación de Pago',
          text: 'Amelia Ant* te envió un pago por S/ 1. El cód. '
              'de seguridad es: 557',
          packageName: 'com.bcp.innovacxion.yapeApp',
        );
        expect(result, isNotNull);
        expect(result!.amount, 1.0);
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, contains('Amelia'));
      });

      test('Yape - Copy oficial: título "Confirmación de pago" + '
          '"El código de seguridad es: x"', () {
        // Formato real que manda Yape al recibir un pago.
        final result = RegexParser.parse(
          title: 'Confirmación de pago',
          text: 'Juan Pérez te envió un pago por S/ 1. '
              'El código de seguridad es: 88342',
          packageName: 'com.bcp.innovacxion.yapeApp',
        );
        expect(result, isNotNull);
        expect(result!.amount, 1.0);
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, 'Juan Pérez');
        expect(result.sourceApp, 'Yape');
      });

      test('Yape - Copy oficial con monto con decimales', () {
        final result = RegexParser.parse(
          title: 'Confirmación de pago',
          text: 'Marta Quispe te envió un pago por S/ 12.50. '
              'El código de seguridad es: 123',
          packageName: 'com.bcp.innovacxion.yapeApp',
        );
        expect(result, isNotNull);
        expect(result!.amount, 12.50);
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, contains('Marta'));
      });

      test('Yape - Envió pago', () {
        final input =
            '¡Genial! Tu pago ha sido enviado a Edson Duberly por S/ 4.07';
        final result = RegexParser.parse(
          title: 'Yape',
          text: input,
          packageName: 'com.bcp.innovacxion.yapeApp',
        );

        expect(result, isNotNull);
        expect(result!.amount, 4.07);
        expect(result.type, TransactionType.expense);
        expect(result.merchantOrPerson, 'Edson Duberly');
      });

      test('Yape - Recibiste S/ de una persona', () {
        final result = RegexParser.parse(
          title: 'Yape',
          text: 'Recibiste S/ 45.00 de María Fernanda Quispe',
          packageName: 'com.bcp.innovacxion.yapeApp',
        );
        expect(result, isNotNull);
        expect(result!.amount, 45.00);
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, contains('María'));
      });

      test('Yape - Te yapeó', () {
        final result = RegexParser.parse(
          title: 'Yape',
          text: 'Te yapeó S/ 100.00 Juan Carlos',
          packageName: 'com.bcp.innovacxion.yapeApp',
        );
        expect(result, isNotNull);
        expect(result!.amount, 100.00);
        expect(result.type, TransactionType.income);
      });
    });

    group('Sip / Agora', () {
      test('Sip / Agora - Envío de monto', () {
        final input = 'Has enviado el monto de S/ 1.50';
        final result = RegexParser.parse(
          title: 'Tarjeta de Débito',
          text: input,
          packageName: 'pe.agora.app',
        );

        expect(result, isNotNull);
        expect(result!.amount, 1.50);
        expect(result.type, TransactionType.expense);
      });

      test('Sip / Agora - Te pagó (paquete pe.agora.app)', () {
        final result = RegexParser.parse(
          title: 'Tarjeta de Débito | Recibiste un pago',
          text: 'Edson Duberly More Anton te pagó S/1.60',
          packageName: 'pe.agora.app',
        );
        expect(result, isNotNull);
        expect(result!.amount, closeTo(1.60, 0.001));
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, contains('Edson'));
      });

      test('Sip / Agora - Te pagó (paquete alternativo com.agora.app)', () {
        final result = RegexParser.parse(
          title: 'Tarjeta de Débito | Recibiste un pago',
          text: 'Edson Duberly More Anton te pagó S/1.60',
          packageName: 'com.agora.app',
        );
        expect(result, isNotNull);
        expect(result!.amount, closeTo(1.60, 0.001));
        expect(result.type, TransactionType.income);
      });
    });

    group('Lemon Cash', () {
      test('Lemon Cash - Pago en comercio (formato PEN con coma)', () {
        final input = 'Pagaste 0,93 PEN en Google';
        final result = RegexParser.parse(
          title: 'Lemon Cash',
          text: input,
          packageName: 'com.lemon.lemoncash',
        );

        expect(result, isNotNull);
        expect(result!.amount, 0.93);
        expect(result.type, TransactionType.expense);
        expect(result.merchantOrPerson, 'Google');
      });

      test('Lemon Cash - Recepción con remitente en el texto', () {
        final result = RegexParser.parse(
          title: 'Recibiste S/ 2 🙌',
          text:
              'EDSON DUBERLY MORE ANTON te envió dinero. Ya lo puedes '
              'encontrar en tu cuenta.',
          packageName: 'com.lemon.lemoncash',
        );
        expect(result, isNotNull);
        expect(result!.amount, 2.0);
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, contains('EDSON'));
      });
    });

    group('BCP / Plin / Interbank / BBVA - formato con coma y punto', () {
      test('Plin - Recibiste S/ con punto decimal', () {
        final input = 'Plin: Recibiste S/ 100.50 de Carlos Mendoza';
        final result = RegexParser.parse(
          title: 'Plin',
          text: input,
          packageName: 'pe.plin.app',
        );

        expect(result, isNotNull);
        expect(result!.amount, 100.50);
        expect(result.type, TransactionType.income);
      });

      test('BCP - Transferencia efectuada', () {
        final result = RegexParser.parse(
          title: 'BCP',
          text: 'Transferencia efectuada por S/ 320.00 a Restaurante Donde Rosa',
          packageName: 'com.bcp.bank.bcp',
        );
        expect(result, isNotNull);
        expect(result!.amount, 320.00);
        expect(result.type, TransactionType.expense);
      });

      test('BCP - Compra con tarjeta (miles con coma y punto)', () {
        final result = RegexParser.parse(
          title: 'BCP',
          text: 'Compra con tarjeta BCP por S/ 12,450.00 en Plaza Vea',
          packageName: 'com.bcp.bank.bcp',
        );
        expect(result, isNotNull);
        expect(result!.amount, 12450.00);
        expect(result.type, TransactionType.expense);
      });

      test('Interbank - Pago a comercio', () {
        final result = RegexParser.parse(
          title: 'Interbank',
          text: 'Realizaste un pago por S/ 45.00 en Plaza Vea',
          packageName: 'com.interbank.bond',
        );
        expect(result, isNotNull);
        expect(result!.amount, 45.00);
        expect(result.type, TransactionType.expense);
      });

      test('BBVA - Transferencia recibida', () {
        final result = RegexParser.parse(
          title: 'BBVA',
          text: 'Recibiste un abono de S/ 600.00 de Carlos Gomez',
          packageName: 'pe.com.bbva.bbvacontigo',
        );
        expect(result, isNotNull);
        expect(result!.amount, 600.00);
        expect(result.type, TransactionType.income);
      });
    });

    group('Fallback genérico', () {
      test('Fallback genérico cuando el copy no coincide exactamente', () {
        final input = 'Cobro procesado de S/ 80.00 en RESTAURANTE';
        final result = RegexParser.parse(
          title: 'Cobro',
          text: input,
        );

        expect(result, isNotNull);
        expect(result!.amount, 80.00);
        // Inferido por palabras clave: sin señal de ingreso -> gasto.
        expect(result.type, TransactionType.expense);
        expect(result.confidence, lessThan(1.0));
      });

      test('Fallback - ingreso inferido por "recibiste"', () {
        final result = RegexParser.parse(
          title: 'Banco X',
          text: 'Recibiste una transferencia de S/ 250.00',
        );
        expect(result, isNotNull);
        expect(result!.amount, 250.00);
        expect(result.type, TransactionType.income);
      });

      test('Fallback - monto en soles sin símbolo S/', () {
        final result = RegexParser.parse(
          title: 'Billetera X',
          text: 'Te enviaron 12.75 soles',
        );
        expect(result, isNotNull);
        expect(result!.amount, 12.75);
      });

      test('Retorna null si no hay monto ni coincidencia', () {
        final result = RegexParser.parse(
          title: 'Noticia',
          text: 'El clima hoy estará soleado',
          packageName: 'com.bcp.bank.bcp',
        );
        expect(result, isNull);
      });
    });

    group('Sanidad del texto', () {
      test('Limpieza: emojis y espacios extra no rompen el parseo', () {
        final result = RegexParser.parse(
          title: 'Recibiste  S/  3  💸 🎉',
          text: 'JUANA   PEREZ  te envió dinero. Ya acreditado.',
          packageName: 'com.lemon.lemoncash',
        );
        expect(result, isNotNull);
        expect(result!.amount, 3.0);
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, contains('JUANA'));
      });
    });

    group('Copias EXACTAS de producción (las que manda cada app hoy)', () {
      test('Yape/BCP - pago recibido: "Yape! [Nombre] te envío un pago por S/"',
          () {
        // Copy: Agora/SIP o Lemon Cash -> Yape/BCP.
        final result = RegexParser.parse(
          title: 'Confirmación de Pago',
          text: 'Yape! Juan Pérez Alzamora te envío un pago por S/ 20.00',
          packageName: 'com.bcp.innovacxion.yapeApp',
        );
        expect(result, isNotNull);
        expect(result!.amount, 20.00);
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, 'Juan Pérez Alzamora');
      });

      test('Yape a Yape - "Amelia Ant** te envío un pago por S/ 1" + OTP', () {
        final result = RegexParser.parse(
          title: 'Confirmación de Pago',
          text: 'Amelia Ant** te envío un pago por S/ 1. '
              'El cód. de seguridad es: 853',
          packageName: 'com.bcp.innovacxion.yapeApp',
        );
        expect(result, isNotNull);
        expect(result!.amount, 1.0);
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, contains('Amelia'));
      });

      test('Agora/SIP - envía un pago: "Has enviado el monto de S/ x.xx"', () {
        final result = RegexParser.parse(
          title: '¡Genial! Tú pago ha sido enviado exitosamente',
          text: 'Has enviado el monto de S/ 1.50 💸',
          packageName: 'pe.agora.app',
        );
        expect(result, isNotNull);
        expect(result!.amount, closeTo(1.50, 0.001));
        expect(result.type, TransactionType.expense);
      });

      test('Agora/SIP - recibe un pago: "[Nombre] te pagó S/ x.xx"', () {
        final result = RegexParser.parse(
          title: 'Tarjeta Débito | Recibiste un pago',
          text: 'Juan Carlos Pérez te pagó S/ 1.60',
          packageName: 'com.agora.app',
        );
        expect(result, isNotNull);
        expect(result!.amount, closeTo(1.60, 0.001));
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, 'Juan Carlos Pérez');
      });

      test('Lemon - recibe un pago: "Recibiste S/ x.xx 🙌" + "te envío un dinero"',
          () {
        final result = RegexParser.parse(
          title: 'Recibiste S/ 2 🙌',
          text: 'EDSON DUBERLY MORE ANTON te envío un dinero. '
              'Ya lo puedes encontrar en tu cuenta.',
          packageName: 'com.lemon.lemoncash',
        );
        expect(result, isNotNull);
        expect(result!.amount, 2.0);
        expect(result.type, TransactionType.income);
        expect(result.merchantOrPerson, contains('EDSON'));
      });

      test('Verbos sin tilde ni variantes: "te envio" / "te envió" / "te envío"',
          () {
        for (final verb in ['envio', 'envió', 'envío']) {
          final result = RegexParser.parse(
            title: 'Confirmación de pago',
            text: 'Carlos Ruiz te $verb un pago por S/ 5.00',
            packageName: 'com.bcp.innovacxion.yapeApp',
          );
          expect(result, isNotNull,
              reason: 'debería parsear con el verbo "te $verb"');
          expect(result!.amount, 5.0);
          expect(result.type, TransactionType.income);
          expect(result.merchantOrPerson, 'Carlos Ruiz');
        }
      });
    });
  });
}