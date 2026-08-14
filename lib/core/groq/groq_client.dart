import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../ai/ai_model_client.dart';
import '../config/app_config.dart';
import '../utils/ai_response_parser.dart';

/// Cliente para la API de Groq (proveedor de respaldo).
///
/// Usa un endpoint compatible con OpenAI (`/chat/completions`) con modelos
/// open source rápidos. Degrada suavemente (devuelve null) si no hay clave,
/// si el servidor satura o si la respuesta no es válida.
class GroqClient implements AiModelClient {
  GroqClient({
    http.Client? httpClient,
    String? apiKey,
    String baseUrl = AppConfig.groqBaseUrl,
    String model = AppConfig.groqModel,
    int maxRetries = 2,
  })  : _http = httpClient ?? http.Client(),
        _apiKey = apiKey?.isNotEmpty == true ? apiKey! : AppConfig.groqApiKey,
        _baseUrl = baseUrl,
        _model = model,
        _maxRetries = maxRetries;

  final http.Client _http;
  final String _apiKey;
  final String _baseUrl;
  final String _model;
  final int _maxRetries;

  /// Instrucciones de sistema comunes para mantener respuestas en español y
  /// JSON válido cuando se pide (Groq exige la palabra "json" en el prompt
  /// para activar el modo `json_object`).
  static const String _systemPrompt = '''
Eres un asistente de la app SaldoClaro (finanzas personales del Perú).
Respondes SIEMPRE en español.
Si se te pide JSON, devuelve SOLO un objeto JSON válido, sin markdown ni texto extra.
''';

  @override
  bool get available => _apiKey.isNotEmpty;

  @override
  String get providerName => 'groq';

  @override
  Future<String?> generate({
    required String prompt,
    bool jsonMode = false,
    double temperature = 0.3,
  }) async {
    if (!available) return null;

    final uri = Uri.parse('$_baseUrl/chat/completions');

    final body = <String, dynamic>{
      'model': _model,
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': prompt},
      ],
      'temperature': temperature,
      if (jsonMode) 'response_format': {'type': 'json_object'},
    };

    try {
      var attempt = 0;
      while (true) {
        final res = await _http
            .post(
              uri,
              headers: {
                'Authorization': 'Bearer $_apiKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(body),
            )
            .timeout(const Duration(seconds: 30));

        // Errores transitorios (cuota / servidor) -> reintentar con backoff.
        if (_isTransient(res.statusCode) && attempt < _maxRetries) {
          attempt++;
          final delay = Duration(milliseconds: 500 * (1 << (attempt - 1)));
          developer.log(
            '[SaldoClaro] Groq HTTP ${res.statusCode} (intento $attempt/$_maxRetries), '
            'reintentando en ${delay.inMilliseconds}ms',
            name: 'SaldoClaro.Groq',
          );
          await Future<void>.delayed(delay);
          continue;
        }

        if (res.statusCode != 200) {
          developer.log(
            '[SaldoClaro] Groq HTTP ${res.statusCode}: ${res.body}',
            name: 'SaldoClaro.Groq',
            error: Exception('Groq respondió con HTTP ${res.statusCode}'),
          );
          return null;
        }

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>?;
        if (choices == null || choices.isEmpty) {
          developer.log(
            '[SaldoClaro] Groq sin choices: ${res.body}',
            name: 'SaldoClaro.Groq',
          );
          return null;
        }

        final content =
            (choices.first as Map<String, dynamic>)['message']?['content'] as String?;
        return content?.trim();
      }
    } catch (e, st) {
      developer.log(
        '[SaldoClaro] Falló la petición a Groq',
        name: 'SaldoClaro.Groq',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  @override
  Future<T?> generateJson<T>({
    required String prompt,
    required T Function(Map<String, dynamic> json) fromJson,
  }) async {
    final raw = await generate(prompt: prompt, jsonMode: true);
    if (raw == null) return null;

    try {
      final cleaned = extractJsonObject(raw);
      final map = jsonDecode(cleaned) as Map<String, dynamic>;
      return fromJson(map);
    } catch (e, st) {
      developer.log(
        '[SaldoClaro] JSON inválido de Groq: $raw',
        name: 'SaldoClaro.Groq',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Códigos transitorios: 429 (rate limit) y 500/502/503/504 (servidor).
  static bool _isTransient(int statusCode) {
    return statusCode == 429 ||
        (statusCode >= 500 && statusCode <= 504);
  }

  @override
  void dispose() => _http.close();
}
