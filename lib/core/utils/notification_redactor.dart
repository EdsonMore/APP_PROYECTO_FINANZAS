/// Redactor de datos sensibles de notificaciones financieras.
///
/// Yape y otras billeteras incluyen códigos de seguridad (OTP) dentro del
/// texto de la notificación ("El código de seguridad es: 557"). Estos códigos
/// NO deben persistirse en Supabase ni enviarse a la IA: solo se usan para
/// parsear el monto/contraparte y luego se eliminan de lo que se guarda.
class NotificationRedactor {
  const NotificationRedactor._();

  /// Marcador de reemplazo. NO contiene "código de seguridad" para que el
  /// marcador no vuelva a casar con los patrones de redacción.
  static const String _placeholder = '[CÓDIGO_OCULTO]';

  /// Patrones que identifican códigos de seguridad en el texto.
  ///
  /// Cubre las variantes reales observadas:
  ///  - "El código de seguridad es: 557"
  ///  - "El cód. de seguridad es: 557"
  ///  - "Código de seguridad: 557"
  static final List<RegExp> _codePatterns = [
    // Con valor: "código de seguridad es: 557" / "cód. de seguridad es: 557"
    // / "código de seguridad: 557". El valor puede ser numérico, alfanumérico
    // o con separadores, y puede quedar pegado a puntuación.
    RegExp(
      r'c[oó]d(?:\.|igo)?\s+de\s+seguridad\s*(?:es\s*)?:?\s*[\w*.#\-]{1,12}',
      caseSensitive: false,
    ),
    // Sin valor: "código de seguridad" / "cód. de seguridad" a secas.
    RegExp(
      r'c[oó]d(?:\.|igo)?\s+de\s+seguridad\b',
      caseSensitive: false,
    ),
  ];

  /// Reemplaza los códigos de seguridad por un marcador que no se persiste.
  ///
  /// Nota: `String.replaceAll(RegExp, String)` trata el reemplazo como texto
  /// literal (los `$n` NO son referencias), así que el marcador es seguro.
  static String redactSecurityCodes(String input) {
    if (input.isEmpty) return input;
    var value = input;
    for (final pattern in _codePatterns) {
      value = value.replaceAll(pattern, _placeholder);
    }
    return value
        .replaceAll('$_placeholder.', _placeholder)
        .replaceAll('$_placeholder,', _placeholder)
        .trim();
  }

  /// Versión compacta para logs: recorta a [maxLength] caracteres.
  static String redactForLog(String input, {int maxLength = 200}) {
    final redacted = redactSecurityCodes(input);
    if (redacted.length <= maxLength) return redacted;
    return '${redacted.substring(0, maxLength)}…';
  }
}