import 'dart:async';
import 'dart:developer' as developer;

import '../ai/ai_model_client.dart';

/// Orquestador central de IA: intercala proveedores en cascada.
///
/// Estrategia de producción:
///   1. [primary] (p. ej. Gemini) — intento principal.
///   2. [backup] (p. ej. Groq)   — salta aquí si el principal satura (HTTP 429)
///      o se cuelga (timeout).
///   3. Si ambos fallan, devuelve null para que el llamador use su fallback
///      local (keywords / resumen calculado) sin romper el flujo.
///
/// Cada proveedor recibe un [requestTimeout] acotado para no dejar al usuario
/// esperando en pantalla; si se agota, se cae al siguiente proveedor.
class AIService {
  AIService({
    required AiModelClient primary,
    required AiModelClient backup,
    this.requestTimeout = const Duration(seconds: 6),
  })  : _primary = primary,
        _backup = backup;

  final AiModelClient _primary;
  final AiModelClient _backup;
  final Duration requestTimeout;

  String? _lastProvider;

  /// Proveedor que respondió en la última llamada (null si ninguna).
  String? get lastProvider => _lastProvider;

  /// Hay IA utilizable si al menos un proveedor está configurado.
  bool get available => _primary.available || _backup.available;

  /// Envía el prompt al primer proveedor disponible que responda.
  Future<String?> generate({
    required String prompt,
    bool jsonMode = false,
    double temperature = 0.3,
  }) {
    return _runAcrossProviders(
      operation: (provider) => provider.generate(
        prompt: prompt,
        jsonMode: jsonMode,
        temperature: temperature,
      ),
    );
  }

  /// Versión JSON: igual que [generate] pero decodificando con [fromJson].
  Future<T?> generateJson<T>({
    required String prompt,
    required T Function(Map<String, dynamic> json) fromJson,
  }) {
    return _runAcrossProviders(
      operation: (provider) => provider.generateJson(
        prompt: prompt,
        fromJson: fromJson,
      ),
    );
  }

  Future<T?> _runAcrossProviders<T>({
    required Future<T?> Function(AiModelClient provider) operation,
  }) async {
    for (final provider in [_primary, _backup]) {
      if (!provider.available) continue;
      try {
        final result =
            await operation(provider).timeout(requestTimeout);
        if (result != null) {
          _lastProvider = provider.providerName;
          return result;
        }
      } catch (e, st) {
        developer.log(
          '[SaldoClaro] IA "${provider.providerName}" falló ($e). '
          'Saltando al siguiente proveedor...',
          name: 'SaldoClaro.AI',
          error: e,
          stackTrace: st,
        );
      }
    }
    return null;
  }
}
