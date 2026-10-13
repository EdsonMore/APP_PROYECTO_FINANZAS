import 'dart:async';

import 'auth_gateway.dart';

/// [AuthGateway] en memoria, para tests y para la app sin Supabase
/// configurado. Cuentas por correo; el código válido es siempre [code].
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({this.code = '123456', this.confirmEmail = true});

  final String code;

  /// Si es false, crear cuenta deja la sesión abierta sin pedir código.
  final bool confirmEmail;

  final _accounts = <String, String>{}; // correo → contraseña
  final _confirmed = <String>{};
  final _changes = StreamController<String?>.broadcast();
  String? _email;
  String? _recovering;

  /// Llamadas recibidas, en orden (sin contraseñas).
  final calls = <String>[];

  /// Si no es null, la próxima operación falla con este error.
  AuthFailure? nextFailure;

  /// Lo que devuelve refreshSession().
  RefreshOutcome refreshOutcome = RefreshOutcome.ok;

  /// Se llama en cada refreshSession() (p. ej. para "arreglar" el servidor falso).
  void Function()? onRefresh;

  /// Agrega una cuenta ya confirmada (para "Ya tengo cuenta").
  void addAccount(String email, String password) {
    _accounts[email] = password;
    _confirmed.add(email);
  }

  bool hasAccount(String email) => _accounts.containsKey(email);

  void _check(String call) {
    calls.add(call);
    final f = nextFailure;
    if (f != null) {
      nextFailure = null;
      throw f;
    }
  }

  void _setEmail(String? email) {
    _email = email;
    _changes.add(email);
  }

  @override
  String? get currentEmail => _email;

  @override
  Stream<String?> get emailChanges => _changes.stream;

  @override
  Future<SignUpOutcome> signUp(String email, String password) async {
    _check('signUp');
    email = email.trim();
    if (_accounts.containsKey(email)) throw const AuthFailure(AuthFailureKind.alreadyExists);
    _accounts[email] = password;
    if (!confirmEmail) {
      _confirmed.add(email);
      _setEmail(email);
      return SignUpOutcome.signedIn;
    }
    return SignUpOutcome.codeSent;
  }

  @override
  Future<void> verifySignupCode(String email, String code) async {
    _check('verifySignupCode');
    if (code.trim() != this.code) throw const AuthFailure(AuthFailureKind.invalidCode);
    _confirmed.add(email.trim());
    _setEmail(email.trim());
  }

  @override
  Future<void> resendSignupCode(String email) async => _check('resendSignupCode');

  @override
  Future<void> signIn(String email, String password) async {
    _check('signIn');
    email = email.trim();
    if (_accounts[email] != password) throw const AuthFailure(AuthFailureKind.invalidCredentials);
    if (!_confirmed.contains(email)) throw const AuthFailure(AuthFailureKind.emailNotConfirmed);
    _setEmail(email);
  }

  @override
  Future<void> sendRecoveryCode(String email) async {
    _check('sendRecoveryCode');
    _recovering = email.trim();
  }

  @override
  Future<void> verifyRecoveryCode(String email, String code) async {
    _check('verifyRecoveryCode');
    if (code.trim() != this.code || _recovering != email.trim()) throw const AuthFailure(AuthFailureKind.invalidCode);
    _setEmail(email.trim());
  }

  @override
  Future<void> updatePassword(String password) async {
    _check('updatePassword');
    final email = _email;
    if (email == null) throw const AuthFailure(AuthFailureKind.unknown);
    if (_accounts[email] == password) throw const AuthFailure(AuthFailureKind.samePassword);
    _accounts[email] = password;
  }

  @override
  Future<void> signOut() async {
    _check('signOut');
    _setEmail(null);
  }

  @override
  Future<RefreshOutcome> refreshSession() async {
    calls.add('refreshSession');
    onRefresh?.call();
    return refreshOutcome;
  }

  @override
  Future<void> signOutLocal() async {
    calls.add('signOutLocal');
    _setEmail(null);
  }

  @override
  Future<void> deleteAccount() async {
    _check('deleteAccount');
    final email = _email;
    if (email != null) {
      _accounts.remove(email);
      _confirmed.remove(email);
    }
    _setEmail(null);
  }
}
