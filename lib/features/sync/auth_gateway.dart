import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' show AuthException, AuthRetryableFetchException, PostgrestException;

/// C3: ninguna operación de cuenta deja al usuario más de 15 s con el spinner.
const authTimeout = Duration(seconds: 15);

/// Resultado de crear cuenta.
enum SignUpOutcome {
  /// Supabase mandó el código de 6 dígitos al correo (confirmación activa).
  codeSent,

  /// Confirmación desactivada en el proyecto: ya hay sesión.
  signedIn,
}

enum AuthFailureKind {
  alreadyExists,
  invalidCredentials,
  emailNotConfirmed,
  invalidCode,
  rateLimited,
  weakPassword,
  samePassword,
  timeout,
  offline,
  unknown,
}

/// Error de cuenta ya traducido para la UI: nunca muestra texto técnico.
class AuthFailure implements Exception {
  const AuthFailure(this.kind);
  final AuthFailureKind kind;

  String get message => switch (kind) {
        AuthFailureKind.alreadyExists => "Ya existe una cuenta con ese correo. Usa 'Ya tengo cuenta'.",
        AuthFailureKind.invalidCredentials => 'Correo o contraseña incorrectos.',
        AuthFailureKind.emailNotConfirmed => 'Confirma tu correo con el código que te enviamos.',
        AuthFailureKind.invalidCode => 'El código no es válido o venció. Pide uno nuevo.',
        AuthFailureKind.rateLimited => 'Espera un momento antes de pedir otro código.',
        AuthFailureKind.weakPassword => 'Esa contraseña es muy débil. Prueba con otra más larga.',
        AuthFailureKind.samePassword => 'La contraseña nueva tiene que ser distinta de la anterior.',
        AuthFailureKind.timeout => 'La conexión está tardando demasiado. Intenta de nuevo.',
        AuthFailureKind.offline => 'No hay conexión. Tus datos siguen guardados en el teléfono.',
        AuthFailureKind.unknown => 'Algo salió mal. Intenta de nuevo en un momento.',
      };

  @override
  String toString() => 'AuthFailure(${kind.name})';
}

/// Traduce cualquier error de autenticación a [AuthFailure].
AuthFailure authFailureFrom(Object error) {
  if (error is AuthFailure) return error;
  if (error is TimeoutException) return const AuthFailure(AuthFailureKind.timeout);
  if (error is SocketException || error is AuthRetryableFetchException) return const AuthFailure(AuthFailureKind.offline);
  if (error is AuthException) {
    return AuthFailure(switch (error.code) {
      'user_already_exists' || 'email_exists' => AuthFailureKind.alreadyExists,
      'invalid_credentials' => AuthFailureKind.invalidCredentials,
      'email_not_confirmed' => AuthFailureKind.emailNotConfirmed,
      'otp_expired' => AuthFailureKind.invalidCode,
      'over_email_send_rate_limit' || 'over_request_rate_limit' => AuthFailureKind.rateLimited,
      'weak_password' => AuthFailureKind.weakPassword,
      'same_password' => AuthFailureKind.samePassword,
      _ => AuthFailureKind.unknown,
    });
  }
  if (error is PostgrestException) return const AuthFailure(AuthFailureKind.unknown);
  return const AuthFailure(AuthFailureKind.offline);
}

/// Corre [operation] con el límite de C3 y traduce sus errores.
Future<T> withAuthTimeout<T>(Future<T> operation, {Duration timeout = authTimeout}) async {
  try {
    return await operation.timeout(timeout);
  } catch (e) {
    throw authFailureFrom(e);
  }
}

/// Lo que la app necesita de la autenticación (Fase 3B). Real:
/// SupabaseAuthGateway; tests: FakeAuthGateway. Todo error sale como
/// [AuthFailure]. Nunca expone tokens.
abstract interface class AuthGateway {
  /// Correo de la sesión actual; null = sin cuenta.
  String? get currentEmail;

  /// Cambios de sesión (correo o null).
  Stream<String?> get emailChanges;

  Future<SignUpOutcome> signUp(String email, String password);
  Future<void> verifySignupCode(String email, String code);
  Future<void> resendSignupCode(String email);
  Future<void> signIn(String email, String password);
  Future<void> sendRecoveryCode(String email);

  /// Con el código correcto queda una sesión para poner la contraseña nueva.
  Future<void> verifyRecoveryCode(String email, String code);
  Future<void> updatePassword(String password);
  Future<void> signOut();

  /// Borra la cuenta y sus datos en el servidor (RPC delete_account) y cierra
  /// la sesión. Los datos del teléfono no se tocan.
  Future<void> deleteAccount();
}
