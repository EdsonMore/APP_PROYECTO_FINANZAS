import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../ai/ai_model_client.dart';
import '../config/app_config.dart';
import '../utils/ai_response_parser.dart';

/// Cliente ligero para la API de Google Gemini (Generative Language API).
///
/// Se inyecta la [apiKey]; si está vacía, [available] devuelve false y los
/// métodos con IA degradan suavemente (sin romper el flujo).
class GeminiClient implements AiModelClient {
  GeminiClient({
    http.Client? httpClient,
    String? apiKey,
    String baseUrl = AppConfig.geminiBaseUrl,
    String model = AppConfig.geminiModel,
    int maxRetries = 3,
  })  : _http = httpClient ?? http.Client(),
        _apiKey = apiKey?.isNotEmpty == true ? apiKey! : AppConfig.geminiApiKey,
        _baseUrl = baseUrl,
        _model = model,
        _maxRetries = maxRetries;

  final http.Client _http;
  final String _apiKey;
  final String _baseUrl;
  final String _model;
  final int _maxRetries;

  /// Indica si hay una clave configurada para usar la IA.
  @override
  bool get available => _apiKey.isNotEmpty;

  @override
  String get providerName => 'gemini';

  /// Envía un prompt y devuelve el texto de la respuesta del modelo.
  ///
  /// [jsonMode]: si es true, se fuerza una respuesta JSON válida.
  @override
  Future<String?> generate({
    required String prompt,
    bool jsonMode = false,
    double temperature = 0.3,
  }) async {
    if (!available) return null;

    final uri = Uri.parse('$_baseUrl/$_model:generateContent'
        '?key=$_apiKey');

    final body = <String, dynamic>{
      'contents': [
        {'parts': [{'text': prompt}]}
      ],
      'generationConfig': {
        'temperature': temperature,
        if (jsonMode) 'responseMimeType': 'application/json',
      },
    };

    try {
      var attempt = 0;
      while (true) {
        final res = await _http
            .post(uri, headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
            .timeout(const Duration(seconds: 30));

        // Errores transitorios (modelo saturado / servidor) → reintentar con
        // backoff exponencial. Todo lo demás (4xx) falla de una vez.
        if (_isTransient(res.statusCode) && attempt < _maxRetries) {
          attempt++;
          final delay = Duration(milliseconds: 500 * (1 << (attempt - 1)));
          developer.log(
            '[SaldoClaro] Gemini HTTP ${res.statusCode} (intento $attempt/$_maxRetries), '
            'reintentando en ${delay.inMilliseconds}ms',
            name: 'SaldoClaro.Gemini',
          );
          await Future<void>.delayed(delay);
          continue;
        }

        if (res.statusCode != 200) {
          developer.log(
            '[SaldoClaro] Gemini HTTP ${res.statusCode}: ${res.body}',
            name: 'SaldoClaro.Gemini',
            error: Exception('Gemini respondió con HTTP ${res.statusCode}'),
          );
          return null;
        }

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final candidates = data['candidates'] as List<dynamic>?;
        if (candidates == null || candidates.isEmpty) {
          developer.log(
            '[SaldoClaro] Gemini sin candidates: ${res.body}',
            name: 'SaldoClaro.Gemini',
          );
          return null;
        }

        final parts = (candidates.first as Map<String, dynamic>)['content']?['parts'] as List<dynamic>?;
        if (parts == null || parts.isEmpty) return null;

        final text = (parts.first as Map<String, dynamic>)['text'] as String?;
        return text?.trim();
      }
    } catch (e, st) {
      developer.log(
        '[SaldoClaro] Falló la petición a Gemini',
        name: 'SaldoClaro.Gemini',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// Códigos de estado que Google marca como transitorios y vale la pena
  /// reintentar: 429 (rate limit) y 500/502/503/504 (servidor saturado).
  static bool _isTransient(int statusCode) {
    return statusCode == 429 ||
        (statusCode >= 500 && statusCode <= 504);
  }

  /// Versión con generics para campo de tipo:
  /// fuerza al modelo a devolver JSON y lo decodifica con [fromJson].
  @override
  Future<T?> generateJson<T>({
    required String prompt,
    required T Function(Map<String, dynamic> json) fromJson,
  }) async {
    final raw = await generate(prompt: prompt, jsonMode: true);
    if (raw == null) return null;

    try {
      // El modelo puede enviar JSON entre ``` ``` o con texto extra.
      final cleaned = extractJsonObject(raw);
      final map = jsonDecode(cleaned) as Map<String, dynamic>;
      return fromJson(map);
    } catch (e, st) {
      developer.log(
        '[SaldoClaro] JSON inválido de Gemini: $raw',
        name: 'SaldoClaro.Gemini',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  @override
  void dispose() => _http.close();
}
