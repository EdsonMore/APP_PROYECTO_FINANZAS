import 'package:saldo_claro/core/models/category.dart';
import 'package:saldo_claro/core/models/transaction_type.dart';

/// Resultado de la categorización automática.
class CategorizationResult {
  const CategorizationResult({
    required this.category,
    required this.method,
    this.confidence = 1.0,
  });

  final Category category;

  /// Método usado: 'rules' (regex/local) o 'ai' (Gemini).
  final String method;
  final double confidence;

  bool get usedAi => method == 'ai';
}

/// Motor local de categorización por reglas (keywords).
///
/// Busca palabras clave del comercio/persona dentro de las categorías del
/// usuario (se priorizan las más específicas). Es rápido, offline y privado.
class RuleCategorizer {
  const RuleCategorizer._();

  /// Clasifica [text] (merchant/person + raw) entre [categories].
  ///
  /// - Busca coincidencia de keywords (insensible mayúsculas, solo para
  ///   categorías de tipo [fallbackType]).
  /// - Devuelve null si ninguna categoría coincide.
  static Category? classify({
    required String text,
    required List<Category> categories,
    required TransactionType fallbackType,
  }) {
    final lower = text.toLowerCase();
    Category? best;
    var bestScore = 0;

    for (final category in categories) {
      if (category.type != fallbackType) continue;
      for (final keyword in category.keywords) {
        final kw = keyword.toLowerCase().trim();
        if (kw.isEmpty) continue;
        if (lower.contains(kw)) {
          // Cuanto más larga la keyword, más específica -> mayor prioridad.
          if (kw.length > bestScore) {
            bestScore = kw.length;
            best = category;
          }
        }
      }
    }
    return best;
  }
}
