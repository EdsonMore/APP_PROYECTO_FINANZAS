import 'dart:convert';

import 'package:saldo_claro/core/models/account.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/services/ai_service.dart';
import 'package:saldo_claro/core/utils/formatters.dart';

/// Mensaje de una conversación del chat.
class ChatTurn {
  const ChatTurn({required this.role, required this.text});

  final String role; // 'user' | 'assistant'
  final String text;
}

/// "CFO de bolsillo": chat financiero personal conectado a la IA.
///
/// Construye un contexto anónimo (JSON) con los movimientos y saldos del
/// usuario y se lo pasa al [AIService] (Gemini -> Groq -> resumen local) para
/// que responda con análisis, cifras y recomendaciones en lenguaje natural.
class CfoChatService {
  CfoChatService({required AIService ai}) : _ai = ai;

  final AIService _ai;

  bool get available => _ai.available;

  /// Construye el contexto JSON (anónimo) con datos del usuario.
  String buildContextJson({
    required List<Transaction> transactions,
    required List<Account> accounts,
    int maxTransactions = 40,
  }) {
    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    final weekStart = now.subtract(Duration(days: now.weekday - 1));

    var monthExpense = 0.0;
    var weekExpense = 0.0;
    final byMerchant = <String, double>{};
    final recent = <Map<String, dynamic>>[];

    for (final t in transactions.take(maxTransactions)) {
      if (!t.isIncome) {
        if (!t.createdAt.isBefore(monthStart)) monthExpense += t.amount;
        if (!t.createdAt.isBefore(weekStart)) weekExpense += t.amount;
        final key = t.merchantOrPerson ?? 'Sin nombre';
        byMerchant[key] = (byMerchant[key] ?? 0) + t.amount;
      }
      recent.add({
        'fecha': Formatters.date(t.createdAt),
        'tipo': t.isIncome ? 'ingreso' : 'gasto',
        'monto': t.amount,
        'comercio': t.merchantOrPerson ?? t.sourceApp,
        'categoria': t.categoryName ?? (t.categoryId != null ? 'id-${t.categoryId}' : 'sin categoría'),
      });
    }

    final topMerchants = byMerchant.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final context = <String, dynamic>{
      'saldos': {for (final a in accounts) a.name: a.balance},
      'resumen_mes': {'gastos': monthExpense},
      'resumen_semana': {'gastos': weekExpense},
      'top_comercios': topMerchants
          .take(8)
          .map((e) => {'nombre': e.key, 'total': e.value})
          .toList(),
      'movimientos_recientes': recent,
    };

    return jsonEncode(context);
  }

  /// Envía una pregunta al modelo con el contexto y el historial previo.
  Future<String> ask({
    required String question,
    required String contextJson,
    List<ChatTurn> history = const [],
  }) async {
    if (!_ai.available) {
      return '⚠️ La función de chat no está disponible: agrega tu clave de '
          'IA (GEMINI_API_KEY o GROQ_API_KEY) o el archivo secrets.dart.';
    }

    final conversation = history
        .map((m) => '${m.role == 'user' ? 'Usuario' : 'Asistente'}: ${m.text}')
        .join('\n');

    final prompt = '''
Eres el "CFO de bolsillo" de la app SaldoClaro: un asesor financiero personal,
cercano e inteligente, especializado en finanzas personales del Perú (soles S/).

Contexto real y actualizado del usuario (JSON, anónimo):
$contextJson

$conversation

Pregunta del usuario: "$question"

Reglas de respuesta:
- Respondé en español, en 3 a 7 líneas, con tono amigable y directo.
- Usá los datos del JSON para dar cifras concretas (montos en S/).
- Si hace falta, da una recomendación accionable y realista.
- Si la pregunta no tiene relación con las finanzas, reconducela amablemente.
''';

    final reply = await _ai.generate(prompt: prompt, temperature: 0.6);
    if (reply != null) return reply;

    // Fallback estructurado: ante cualquier fallo de red/formato, en lugar de
    // responder un mensaje genérico, se entrega un resumen local del usuario.
    return _fallbackSummary(contextJson);
  }

  /// Respuesta estructurada calculada localmente cuando Gemini no responde.
  String _fallbackSummary(String contextJson) {
    String monthExpense = '';
    String balances = '';

    try {
      final data = jsonDecode(contextJson) as Map<String, dynamic>;
      final monthExpenseValue =
          (data['resumen_mes'] as Map<String, dynamic>?)?['gastos'];
      if (monthExpenseValue is num) {
        monthExpense = '• Gastado este mes: S/ ${monthExpenseValue.toStringAsFixed(2)}\n';
      }
      final balancesMap = data['saldos'] as Map<String, dynamic>?;
      if (balancesMap != null && balancesMap.isNotEmpty) {
        final items = balancesMap.entries
            .map((e) => '${e.key}: ${_currency(e.value)}')
            .join(', ');
        balances = '• Saldos actuales: $items\n';
      } else {
        balances = '• Saldos actuales: sin cuentas registradas.\n';
      }
    } catch (_) {
      // El contexto no era JSON: no se puede mostrar resumen local.
    }

    return '📊 La IA no respondió en este momento (revisa tu conexión). '
        'Mientras tanto, esto tengo de tus datos:\n'
        '$monthExpense$balances'
        '→ Reintenta tu consulta en unos segundos. 🤖';
  }

  static String _currency(dynamic value) {
    final amount = value is num ? value : 0;
    return 'S/ ${amount.toStringAsFixed(2)}';
  }
}