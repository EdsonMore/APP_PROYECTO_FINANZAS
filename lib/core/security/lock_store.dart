import 'package:shared_preferences/shared_preferences.dart';

/// Persistencia en disco de las preferencias de seguridad y privacidad.
///
/// - `biometricLockEnabled`: si el bloqueo biométrico está activo (permite
///   que SaldoClaro pida huella/FaceID/PIN al abrir o al volver a la app).
/// - `balanceHidden`: si el "modo incógnito" (ocultar saldos) está activo.
///
/// La preferencia se guarda en SharedPreferences para mantener el estado al
/// reiniciar la app y por usuario/instalación.
class LockStore {
  LockStore._();

  static final LockStore instance = LockStore._();

  static const String _biometricKey = 'saldo_claro.biometric_lock';
  static const String _balanceHiddenKey = 'saldo_claro.balance_hidden';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// ¿Está activo el bloqueo biométrico en los ajustes de la app?
  Future<bool> isBiometricLockEnabled() async {
    final prefs = await _prefs;
    return prefs.getBool(_biometricKey) ?? false;
  }

  Future<void> setBiometricLockEnabled(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_biometricKey, value);
  }

  /// ¿Está activo el modo incógnito (ocultar saldos)?
  Future<bool> isBalanceHidden() async {
    final prefs = await _prefs;
    return prefs.getBool(_balanceHiddenKey) ?? false;
  }

  Future<void> setBalanceHidden(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool(_balanceHiddenKey, value);
  }
}