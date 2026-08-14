import 'package:shared_preferences/shared_preferences.dart';

/// Registro del consentimiento de los Términos y Condiciones y de la
/// Política de Privacidad (exigido por la Ley N.º 29733 / Reglamento 017-2013-JUS
/// de protección de datos personales del Perú y por las políticas de Google Play).
///
/// Se guarda por instalación. Cuando se actualizan los documentos legales se
/// incrementa [kCurrentVersion]; si la versión aceptada es menor, la app vuelve
/// a pedir el consentimiento.
class LegalAcceptanceStore {
  LegalAcceptanceStore._();

  static final LegalAcceptanceStore instance = LegalAcceptanceStore._();

  /// Versión vigente de los documentos legales. Subir este número cuando los
  /// T&C o la Política de Privacidad cambien: los usuarios deberán aceptarlos
  /// de nuevo.
  static const String kCurrentVersion = '2026-08-13-v1';

  static const String _acceptedVersionKey = 'saldo_claro.legal_accepted_version';
  static const String _acceptedAtKey = 'saldo_claro.legal_accepted_at';

  Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  /// ¿El usuario aceptó la versión vigente de los documentos legales?
  Future<bool> hasAccepted() async {
    final prefs = await _prefs;
    return prefs.getString(_acceptedVersionKey) == kCurrentVersion;
  }

  /// Persiste la aceptación del usuario con la fecha/hora actual (UTC).
  Future<void> accept() async {
    final prefs = await _prefs;
    await prefs.setString(_acceptedVersionKey, kCurrentVersion);
    await prefs.setString(_acceptedAtKey, DateTime.now().toUtc().toIso8601String());
  }

  /// Fecha (ISO 8601 UTC) en que se aceptaron por última vez, o null.
  Future<String?> lastAcceptedAt() async {
    final prefs = await _prefs;
    return prefs.getString(_acceptedAtKey);
  }
}