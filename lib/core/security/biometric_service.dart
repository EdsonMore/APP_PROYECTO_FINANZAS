import 'package:local_auth/local_auth.dart';

/// Servicio de autenticación biométrica (huella, FaceID, PIN/patrón del sistema).
///
/// Envuelve `local_auth` y degrada de forma segura (nunca lanza) cuando el
/// dispositivo no soporta biometría o el plugin no está disponible, por
/// ejemplo en pruebas o plataformas sin soporte nativo.
class BiometricService {
  BiometricService({LocalAuthentication? localAuth})
      : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  /// ¿El dispositivo declara soporte para autenticación biométrica?
  Future<bool> isSupported() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// ¿Hay biometría inscrita (huella/FaceID) disponible?
  Future<bool> hasEnrolledBiometrics() async {
    try {
      return await _localAuth.isDeviceSupported() &&
          await _localAuth.canCheckBiometrics &&
          await _localAuth.getAvailableBiometrics().then((b) => b.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// ¿Se puede autenticar con biometría o credencial del dispositivo?
  Future<bool> canAuthenticate() async {
    try {
      return await _localAuth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Pide autenticación al usuario.
  ///
  /// Con `biometricOnly: false` se permite el fallback al PIN/patrón/contraseña
  /// del sistema cuando la biometría falla o no está inscrita.
  Future<bool> authenticate({required String reason}) async {
    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: false,
        sensitiveTransaction: true,
        // Si la app se minimiza durante el diálogo, la autenticación continúa
        // al volver a primer plano en lugar de fallar.
        persistAcrossBackgrounding: true,
      );
    } catch (_) {
      return false;
    }
  }
}