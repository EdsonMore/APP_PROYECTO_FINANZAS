/// Contrato común de un proveedor de modelos de IA (Gemini, Groq, ...).
///
/// Todos los clientes de IA de SaldoClaro implementan esta interfaz para que
/// [AIService] pueda intercalar proveedores (fallback) de forma transparente.
abstract interface class AiModelClient {
  /// Indica si hay clave configurada para usar el proveedor.
  bool get available;

  /// Nombre corto del proveedor ('gemini', 'groq') para logs y telemetría.
  String get providerName;

  /// Envía un prompt y devuelve el texto de la respuesta (null si falló).
  Future<String?> generate({
    required String prompt,
    bool jsonMode = false,
    double temperature = 0.3,
  });

  /// Fuerza una respuesta JSON válida y la decodifica con [fromJson].
  Future<T?> generateJson<T>({
    required String prompt,
    required T Function(Map<String, dynamic> json) fromJson,
  });

  void dispose();
}
