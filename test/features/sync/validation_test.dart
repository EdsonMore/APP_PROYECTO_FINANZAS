import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/features/sync/auth_gateway.dart';
import 'package:saldo_claro/features/sync/remote.dart';
import 'package:saldo_claro/features/sync/validation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('validación', () {
    test('correo', () {
      expect(emailError('ana@correo.com'), isNull);
      expect(emailError('  ana@correo.pe  '), isNull, reason: 'trim');
      // Solo formato, sin consultar DNS: sirven los usuarios de prueba creados a mano.
      expect(emailError('edson@saldoclaro.local'), isNull);
      expect(emailError('qa+1@dominio-que-no-existe.test'), isNull);
      for (final bad in ['', 'ana', 'ana@', '@correo.com', 'ana@correo', 'ana correo@x.com', 'ana@correo.c']) {
        expect(emailError(bad), isNotNull, reason: bad);
      }
    });

    test('contraseña: 6 o más', () {
      expect(passwordError('123456'), isNull);
      expect(passwordError('12345'), 'Mínimo 6 caracteres.');
      expect(passwordError(''), 'Mínimo 6 caracteres.');
    });

    test('repetir contraseña', () {
      expect(repeatError('abcdef', 'abcdef'), isNull);
      expect(repeatError('abcdef', 'abcdeg'), 'Las contraseñas no coinciden.');
    });

    test('código: exactamente 6 dígitos', () {
      expect(codeError('481902'), isNull);
      expect(codeError(' 481902 '), isNull);
      for (final bad in ['', '48190', '4819022', '48a902', '48 902']) {
        expect(codeError(bad), isNotNull, reason: bad);
      }
    });
  });

  group('errores de auth → mensaje', () {
    test('códigos de Supabase', () {
      AuthFailureKind k(String code) => authFailureFrom(AuthException('x', code: code)).kind;
      expect(k('user_already_exists'), AuthFailureKind.alreadyExists);
      expect(k('email_exists'), AuthFailureKind.alreadyExists);
      expect(k('invalid_credentials'), AuthFailureKind.invalidCredentials);
      expect(k('email_not_confirmed'), AuthFailureKind.emailNotConfirmed);
      expect(k('otp_expired'), AuthFailureKind.invalidCode);
      expect(k('over_email_send_rate_limit'), AuthFailureKind.rateLimited);
      expect(k('over_request_rate_limit'), AuthFailureKind.rateLimited);
      expect(k('weak_password'), AuthFailureKind.weakPassword);
      expect(k('same_password'), AuthFailureKind.samePassword);
      expect(k('lo_que_sea'), AuthFailureKind.unknown);
    });

    test('red y timeout', () {
      expect(authFailureFrom(TimeoutException('t')).kind, AuthFailureKind.timeout);
      expect(authFailureFrom(const SocketException('x')).kind, AuthFailureKind.offline);
      expect(authFailureFrom(AuthRetryableFetchException()).kind, AuthFailureKind.offline);
      expect(authFailureFrom(const AuthFailure(AuthFailureKind.invalidCode)).kind, AuthFailureKind.invalidCode);
    });

    test('mensajes en español, sin datos técnicos', () {
      expect(const AuthFailure(AuthFailureKind.alreadyExists).message,
          "Ya existe una cuenta con ese correo. Usa 'Ya tengo cuenta'.");
      expect(const AuthFailure(AuthFailureKind.timeout).message, 'La conexión está tardando demasiado. Intenta de nuevo.');
      for (final k in AuthFailureKind.values) {
        expect(AuthFailure(k).message, isNot(contains('Exception')), reason: k.name);
        expect(AuthFailure(k).message, isNot(contains('—')));
      }
    });

    test('C3: withAuthTimeout corta una operación que no responde', () async {
      final never = Completer<void>().future;
      await expectLater(withAuthTimeout(never, timeout: const Duration(milliseconds: 20)),
          throwsA(isA<AuthFailure>().having((f) => f.kind, 'kind', AuthFailureKind.timeout)));
      expect(authTimeout, const Duration(seconds: 15));
    });
  });

  group('errores de sync → red o datos', () {
    test('red: corta el push', () {
      expect(syncFailureFrom(TimeoutException('t')), isA<NetworkFailure>());
      expect(syncFailureFrom(const SocketException('x')), isA<NetworkFailure>());
      for (final code in ['500', '502', '503', '429']) { // 401 y JWT: AuthExpiredFailure (remote_test)
        expect(syncFailureFrom(PostgrestException(message: 'x', code: code)), isA<NetworkFailure>(), reason: code);
      }
    });

    test('datos: la fila queda pendiente y se sigue', () {
      for (final code in ['23503', '23514', '23502', '42501', '22P02']) {
        final f = syncFailureFrom(PostgrestException(message: 'm', code: code));
        expect(f, isA<DataFailure>(), reason: code);
        expect((f as DataFailure).code, code);
      }
    });
  });
}
