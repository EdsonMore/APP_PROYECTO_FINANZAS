import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_gateway.dart';

/// [AuthGateway] con Supabase Auth. Correo + contraseña; confirmación y
/// recuperación con código de 6 dígitos (plantillas con {{ .Token }}, ver
/// supabase/plantillas/). Cada operación con el límite de 15 s (C3).
class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway(this._client);
  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  @override
  String? get currentEmail => _auth.currentSession?.user.email;

  @override
  Stream<String?> get emailChanges => _auth.onAuthStateChange.map((s) => s.session?.user.email);

  @override
  Future<SignUpOutcome> signUp(String email, String password) => withAuthTimeout(() async {
        final res = await _auth.signUp(email: email.trim(), password: password);
        // Con "Confirm email" activo, un correo ya registrado no da error (para
        // no revelar cuentas): vuelve un usuario sin identidades.
        if (res.user?.identities?.isEmpty ?? false) throw const AuthFailure(AuthFailureKind.alreadyExists);
        return res.session == null ? SignUpOutcome.codeSent : SignUpOutcome.signedIn;
      }());

  @override
  Future<void> verifySignupCode(String email, String code) => withAuthTimeout(
      _auth.verifyOTP(type: OtpType.signup, email: email.trim(), token: code.trim()));

  @override
  Future<void> resendSignupCode(String email) =>
      withAuthTimeout(_auth.resend(type: OtpType.signup, email: email.trim()));

  @override
  Future<void> signIn(String email, String password) =>
      withAuthTimeout(_auth.signInWithPassword(email: email.trim(), password: password));

  @override
  Future<void> sendRecoveryCode(String email) => withAuthTimeout(_auth.resetPasswordForEmail(email.trim()));

  @override
  Future<void> verifyRecoveryCode(String email, String code) => withAuthTimeout(
      _auth.verifyOTP(type: OtpType.recovery, email: email.trim(), token: code.trim()));

  @override
  Future<void> updatePassword(String password) =>
      withAuthTimeout(_auth.updateUser(UserAttributes(password: password)));

  @override
  Future<void> signOut() => withAuthTimeout(_auth.signOut());

  @override
  Future<RefreshOutcome> refreshSession() async {
    try {
      await withAuthTimeout(_auth.refreshSession());
      return RefreshOutcome.ok;
    } on AuthFailure catch (f) {
      return f.kind == AuthFailureKind.offline || f.kind == AuthFailureKind.timeout
          ? RefreshOutcome.offline
          : RefreshOutcome.invalid;
    }
  }

  @override
  Future<void> signOutLocal() async {
    try {
      await _auth.signOut(scope: SignOutScope.local);
    } catch (_) {
      // Local: no depende de la red; si algo falla igual no queda sesión útil.
    }
  }

  @override
  Future<void> deleteAccount() => withAuthTimeout(() async {
        await _client.rpc<void>('delete_account');
        // La cuenta ya no existe: cerrar solo la sesión local.
        await _auth.signOut(scope: SignOutScope.local);
      }());
}
