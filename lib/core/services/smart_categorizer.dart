import 'package:saldo_claro/core/models/category.dart';
import 'package:saldo_claro/core/models/transaction_type.dart';
import 'package:saldo_claro/core/services/ai_service.dart';
import 'package:saldo_claro/core/services/rule_categorizer.dart';

/// Resultado completo de la clasificación de una transacción.
class SmartCategoryResult {
  const SmartCategoryResult({
    required this.categoryId,
    required this.categoryName,
    required this.method,
    required this.confidence,
  });

  final String? categoryId;
  final String? categoryName;
  final String method; // 'rules' | 'ai'
  final double confidence;

  bool get classified => categoryId != null;
}

/// Categorizador "inteligente": combina reglas locales (rápidas/offline) con
/// IA cuando la regla local no es concluyente.
///
/// La IA solo se consulta cuando las reglas locales no resuelven (última
/// instancia), para no gastar cuota en el 90% de las capturas normales.
class SmartCategorizer {
  SmartCategorizer({required AIService ai}) : _ai = ai;

  final AIService _ai;

  /// Clasifica una transacción.
  ///
  /// 1. Reglas locales (keywords del usuario).
  /// 2. Si no hay regla local y hay IA disponible, pregunta a la IA.
  ///
  /// [merchant] es el nombre del comercio/persona; [rawText] es el texto
  /// completo de la notificación (contexto adicional).
  Future<SmartCategoryResult> classify({
    required String merchant,
    required String rawText,
    required TransactionType type,
    required List<Category> categories,
  }) async {
    // --- Fase 1: reglas locales ---
    final local = RuleCategorizer.classify(
      text: '$merchant\n$rawText',
      categories: categories,
      fallbackType: type,
    );

    if (local != null) {
      return SmartCategoryResult(
        categoryId: local.id,
        categoryName: local.name,
        method: 'rules',
        confidence: 0.85,
      );
    }

    // --- Fase 2: IA (Gemini -> Groq -> local) ---
    if (_ai.available) {
      final ai = await _classifyWithAi(
        merchant: merchant,
        rawText: rawText,
        type: type,
        categories: categories,
      );
      if (ai != null) {
        return SmartCategoryResult(
          categoryId: ai.id,
          categoryName: ai.name,
          method: 'ai',
          confidence: 0.9,
        );
      }
    }

    // --- Sin conclusión: se deja sin categoría (null) ---
    return const SmartCategoryResult(
      categoryId: null,
      categoryName: null,
      method: 'none',
      confidence: 0,
    );
  }

  Future<_AiChoice?> _classifyWithAi({
    required String merchant,
    required String rawText,
    required TransactionType type,
    required List<Category> categories,
  }) async {
    final catList = categories
        .where((c) => c.type == type)
        .map((c) =>
            '${c.name} (keywords: ${c.keywords.isEmpty ? 'ninguna' : c.keywords.join(', ')})')
        .join('; ');

    final prompt = '''
Eres un asistente de categorización financiera. Dado el comercio/persona y el
texto de una transacción, elige UNA categoría de la lista que mejor se ajuste.
Devuelve SOLO un objeto JSON con las claves "name" y "confidence" (0-1).

Comercio/persona: "$merchant"
Texto de la notificación: "$rawText"
Tipo: ${type.badge}

Categorías disponibles:
$catList

Si ninguna encaja, devuelve {"name": null, "confidence": 0}.
''';

    final result = await _ai.generateJson<Map<String, dynamic>>(
      prompt: prompt,
      fromJson: (json) => json,
    );

    if (result == null) return null;
    final name = result['name'] as String?;
    if (name == null) return null;

    for (final c in categories) {
      if (c.name.toLowerCase() == name.toLowerCase()) {
        return _AiChoice(id: c.id, name: c.name);
      }
    }
    return null;
  }
}

class _AiChoice {
  const _AiChoice({required this.id, required this.name});
  final String id;
  final String name;
}
