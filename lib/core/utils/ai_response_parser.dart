/// Utilidades para interpretar respuestas de modelos de IA.
library;

/// Extrae el primer objeto JSON de un texto (tolera markdown y texto extra).
String extractJsonObject(String raw) {
  final stripped = raw
      .replaceAll(RegExp(r'^```[a-zA-Z]*\s*'), '')
      .replaceAll(RegExp(r'\s*```$'), '')
      .trim();
  final start = stripped.indexOf('{');
  final end = stripped.lastIndexOf('}');
  if (start >= 0 && end > start) {
    return stripped.substring(start, end + 1);
  }
  return stripped;
}
