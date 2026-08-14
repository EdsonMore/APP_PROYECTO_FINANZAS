import '../models/transaction_type.dart';

/// Resultado del parseo de una notificación.
class ParsedTransaction {
  const ParsedTransaction({
    required this.amount,
    required this.type,
    this.merchantOrPerson,
    this.sourceApp,
    this.confidence = 1.0,
  });

  final double amount;
  final TransactionType type;
  final String? merchantOrPerson;
  final String? sourceApp;
  final double confidence;

  bool get isExpense => type == TransactionType.expense;

  @override
  String toString() =>
      'ParsedTransaction(amount: $amount, type: $type, '
      'merchant: $merchantOrPerson, app: $sourceApp)';
}

/// Motor de parseo basado en expresiones regulares.
///
/// Extrae monto, contraparte (persona/comercio) y tipo de transacción
/// a partir del título y texto de una notificación financiera.
class RegexParser {
  const RegexParser._();

  // ------------------------------------------------------------------
  // Utilidades de moneda: "S/ 123,45" | "S/123" | "123.45" | "1,234.56"
  // ------------------------------------------------------------------

  static final RegExp _penPattern = RegExp(
    r'S/\s?\s?([0-9]{1,3}(?:[.,][0-9]{3})*(?:[.,][0-9]{1,2})?)',
    caseSensitive: false,
  );

  static final RegExp _penPlainPattern = RegExp(
    r'(?<![0-9A-Za-z/])([0-9]{1,3}(?:[.,][0-9]{3})*(?:[.,][0-9]{1,2})?)\s*(?:soles|s\/\.?|pen)',
    caseSensitive: false,
  );

  /// Convierte un fragmento monetario ("1,234.56" | "123,45") a double.
  static double _toDouble(String raw) {
    var cleaned = raw.trim().replaceAll(RegExp(r'[^\d.,]'), '');
    if (cleaned.isEmpty) return 0;

    // Si hay punto y coma, el último separador es el decimal.
    if (cleaned.contains('.') && cleaned.contains(',')) {
      final lastDot = cleaned.lastIndexOf('.');
      final lastComma = cleaned.lastIndexOf(',');
      if (lastDot > lastComma) {
        cleaned = cleaned.replaceAll(',', '');
      } else {
        cleaned = cleaned.replaceAll('.', '').replaceAll(',', '.');
      }
    } else if (cleaned.contains(',')) {
      // Formato europeo: 1.234,56 -> puede ser miles o decimales.
      final commaPos = cleaned.indexOf(',');
      final after = cleaned.substring(commaPos + 1);
      if (after.length == 2) {
        cleaned = cleaned.replaceAll(',', '.');
      } else {
        cleaned = cleaned.replaceAll(',', '');
      }
    }
    return double.tryParse(cleaned) ?? 0;
  }

  static double? _extractAmount(String text) {
    final match = _penPattern.firstMatch(text);
    if (match != null) {
      final value = _toDouble(match.group(1)!);
      if (value > 0) return value;
    }
    final plain = _penPlainPattern.firstMatch(text);
    if (plain != null) {
      final value = _toDouble(plain.group(1)!);
      if (value > 0) return value;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // Reglas por aplicación
  // ------------------------------------------------------------------

  static final List<AppRule> _rules = [
    // ---------------- YAPE ----------------
    AppRule(
      package: 'com.bcp.innovacxion.yapeApp',
      matchers: [
        // GASTO: "Enviaste S/ 25.00 a María"
        RuleMatcher(
          regex: RegExp(
            r'enviaste\s+S/\s*([0-9.,]+)\s+a\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // GASTO: "Yapeaste S/ 10.00 a Juan"
        RuleMatcher(
          regex: RegExp(
            r'yapeaste\s+S/\s*([0-9.,]+)\s+(?:a|para)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // GASTO: "Tu pago ha sido enviado a [nombre] por S/ 4.07"
        RuleMatcher(
          regex: RegExp(
            r'pago\s+ha\s+sido\s+enviado\s+a\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+?)\s+por\s+S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
          personGroup: 1,
        ),
        // GASTO: "Tu yape de S/ 5.00 a [nombre]"
        RuleMatcher(
          regex: RegExp(
            r'tu\s+yape\s+de\s+S/\s*([0-9.,]+)\s+a\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // INGRESO: "Te yapeó S/ 100.00 Juan Carlos"
        RuleMatcher(
          regex: RegExp(
            r'te\s+yape[oó]\s+S/\s*([0-9.,]+)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO: "¡Te yapearon! S/ 20.00"
        RuleMatcher(
          regex: RegExp(
            r'yapearon\S*\s+S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO: "Recibiste un yape de S/ 15.00 de [nombre]"
        RuleMatcher(
          regex: RegExp(
            r'recibiste\s+un\s+yape\s+de\s+S/\s*([0-9.,]+)\s+(?:de\s+parte\s+de|de|desde)\s*([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)?',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO: "Recibiste S/ 45.00 de [nombre]"
        RuleMatcher(
          regex: RegExp(
            r'recibiste\s+S/\s*([0-9.,]+)\s+(?:de|desde)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO REAL (producción): el nombre del remitente seguido de
        // "te envió un pago por S/ X" (Amelia Ant*) o "te ha enviado un pago
        // de S/ X" (Yape! Bienvenida). La regex NO asume que una palabra es un
        // saludo ("Bienvenida" puede ser un nombre propio de la persona).
        // Se ignora explícitamente el prefijo de marca "Yape" (con o sin "!")
        // para que jamás se incluya dentro del nombre de la persona.
        RuleMatcher(
          regex: RegExp(
            r'te\s+(?:ha\s+)?env[ií](?:ado|[íi]?[oó])\s+(?:un\s+pago\s+)?(?:por|de)\s+S/\s*([\d.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
          personRegex: RegExp(
            r'(?:yape\s*!?\s*)?([A-Za-zÁÉÍÓÚÑáéíóúñ][A-Za-zÁÉÍÓÚÑáéíóúñ\s\*\.]*?)\s+te\s+(?:ha\s+)?env[ií](?:ado|[íi]?[oó])\s+(?:un\s+pago\s+)?(?:por|de)\s+S/\s*[\d.,]+',
            caseSensitive: false,
          ),
          personGroup: 1,
        ),
      ],
    ),
    // ---------------- BCP ----------------
    AppRule(
      package: 'com.bcp.bank.bcp',
      matchers: [
        RuleMatcher(
          regex: RegExp(
            r'transferencia\s+efectuada\s+(?:por\s+)?S/\s*([0-9.,]+)\s+a\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        RuleMatcher(
          regex: RegExp(
            r'compra\s+con\s+tarjeta\s+(?:bcp\s+)?(?:d[eé]bito|cr[eé]dito)?\s+por\s+S/\s*([0-9.,]+)\s+(?:en\s+)?([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        RuleMatcher(
          regex: RegExp(
            r'pago\s+realizado\s+(?:con\s+tarjeta\s+)?por\s+S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // GASTO: "Transferencia efectuada por S/ [monto]"
        RuleMatcher(
          regex: RegExp(
            r'transferencia\s+(?:efectuada|realizada|enviada)\s+por\s+S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // INGRESO: "Abono / transferencia recibida por S/ [monto]"
        RuleMatcher(
          regex: RegExp(
            r'(?:abono|transferencia)\s+recibid[oa]\s+.{0,25}?S/\s*([0-9.,]+)\s+(?:de|desde)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)?',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        RuleMatcher(
          regex: RegExp(
            r'transferencia\s+recibida\s+(?:por\s+)?S/\s*([0-9.,]+)\s+(?:de|desde)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        RuleMatcher(
          regex: RegExp(
            r'dep[ió]sito\s+(?:en\s+cuenta|recibido)\s+(?:por\s+)?S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO: "Recibiste S/ [monto]"
        RuleMatcher(
          regex: RegExp(
            r'recibiste\s+.{0,15}?S/\s*([0-9.,]+)\s+(?:de|desde)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)?',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
      ],
    ),
    // ---------------- AGORA (Movistar Money) / SIP ----------------
    AppRule(
      package: 'pe.agora.app',
      matchers: [
        RuleMatcher(
          regex: RegExp(
            r'(?:pago|compra)\s+con\s+tarjeta\s+(?:agora\s+)?(?:por|de)\s+S/\s*([0-9.,]+)\s+(?:en\s+)?([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        RuleMatcher(
          regex: RegExp(
            r'recarga\s+realizada\s+(?:por\s+)?S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // GASTO: "Has enviado el monto de S/ 1.50" (Sip/Agora).
        RuleMatcher(
          regex: RegExp(
            r'has\s+enviado\s+el\s+monto\s+de\s+S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        RuleMatcher(
          regex: RegExp(
            r'(?:transferencia|abono)\s+(?:recibido|recibida)\s+(?:por\s+)?S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        RuleMatcher(
          regex: RegExp(
            r'(?:transferencia|env[ií]o)\s+(?:realizada|realizado)\s+(?:por\s+)?S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // INGRESO REAL (producción): "Edson Duberly More Anton te pagó S/1.60"
        RuleMatcher(
          regex: RegExp(
            r'(.+?)\s+te\s+pagó\s+S/\s*([\d.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
          personGroup: 1,
        ),
      ],
    ),
    // ---------------- SIP / AGORA (package alternativo) ----------------
    AppRule(
      package: 'com.agora.app',
      matchers: [
        // INGRESO REAL (producción): "Edson Duberly More Anton te pagó S/1.60"
        RuleMatcher(
          regex: RegExp(
            r'(.+?)\s+te\s+pagó\s+S/\s*([\d.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
          personGroup: 1,
        ),
        // GASTO: "Pago con tu tarjeta por/de S/ ..." (Sip/Agora)
        RuleMatcher(
          regex: RegExp(
            r'(?:pago|compra)\s+con\s+tarjeta\s+(?:sip\s+|agora\s+)?(?:por|de)\s+S/\s*([0-9.,]+)\s+(?:en\s+)?([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // INGRESO: "Recibiste un pago por S/ ..." (título "Tarjeta de Débito |
        // Recibiste un pago")
        RuleMatcher(
          regex: RegExp(
            r'recibiste\s+un\s+pago\s+(?:por\s+)?S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
      ],
    ),
    // ---------------- LEMON CASH ----------------
    AppRule(
      package: 'com.lemon.lemoncash',
      matchers: [
        RuleMatcher(
          regex: RegExp(
            r'compra\s+(?:con\s+tu\s+tarjeta\s+)?(?:por|de)\s+S/\s*([0-9.,]+)\s+(?:en\s+)?([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        RuleMatcher(
          regex: RegExp(
            r'(?:pago|recarga)\s+(?:realizado|realizada)\s+(?:por\s+)?S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        RuleMatcher(
          regex: RegExp(
            r'recibiste\s+(?:un\s+)?(?:pago|abono)\s+(?:de\s+)?S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO REAL (producción): Título "Recibiste S/ 2 🙌" +
        // Texto "EDSON DUBERLY MORE ANTON te envió dinero. Ya lo puedes..."
        // o "EDSON DUBERLY MORE ANTON te envío un dinero. Ya lo puedes..."
        // El monto se extrae del título; el remitente del texto.
        RuleMatcher(
          regex: RegExp(
            r'recibiste\s+S/\s*([\d.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
          personRegex: RegExp(
            r'(.+?)\s+te\s+env[ií](?:ado|[íi]?[oó])\s+(?:un\s+)?dinero',
            caseSensitive: false,
          ),
          personGroup: 1,
        ),
        // INGRESO: "Recibiste S/ [monto] de [nombre]"
        RuleMatcher(
          regex: RegExp(
            r'recibiste\s+S/\s*([0-9.,]+)\s+(?:de|desde)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
      ],
    ),
    // ---------------- PLIN ----------------
    AppRule(
      package: 'pe.plin.app',
      matchers: [
        // GASTO: "Le enviaste S/ 10.00 a María" | "Enviaste S/ 10.00 a María"
        RuleMatcher(
          regex: RegExp(
            r'(?:le\s+)?enviaste\s+S/\s*([0-9.,]+)\s+(?:a|para)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // GASTO: "Pequeños envios: S/ ..."
        RuleMatcher(
          regex: RegExp(
            r'(?:pago|compra)\s+(?:realizado|realizada)\s+.{0,20}?S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // INGRESO: "Recibiste S/ 25.00 de Pedro"
        RuleMatcher(
          regex: RegExp(
            r'recibiste\s+S/\s*([0-9.,]+)\s+(?:de|desde)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO: "Te pagó S/ ..." | "Te envió S/ ..."
        RuleMatcher(
          regex: RegExp(
            r'te\s+(?:pag[oó]|env[ií](?:ado|[íi]?[oó]))\s+S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO: "¡Recibiste un plin de S/ 10.00!"
        RuleMatcher(
          regex: RegExp(
            r'recibiste\s+un\s+plin\s+de\s+S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO: "Juan te envió un plin de S/ ..."
        RuleMatcher(
          regex: RegExp(
            r'te\s+(?:env[ií](?:ado|[íi]?[oó])|mando)\s+un\s+plin\s+(?:de\s+)?S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // GASTO: "Enviaste un plin de S/ ... a [nombre]"
        RuleMatcher(
          regex: RegExp(
            r'(?:le\s+)?enviaste\s+un\s+plin\s+de\s+S/\s*([0-9.,]+)\s+(?:a|para)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
      ],
    ),
    // ---------------- BBVA ----------------
    AppRule(
      package: 'pe.com.bbva.bbvacontigo',
      matchers: [
        // GASTO: "Transferencia realizada por S/ 200.00 a Carlos"
        RuleMatcher(
          regex: RegExp(
            r'transferencia\s+(?:realizada|enviada)\s+.{0,40}?S/\s*([0-9.,]+)\s+(?:a|a favor de)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // GASTO: "Le enviaste S/ ... a [nombre]"
        RuleMatcher(
          regex: RegExp(
            r'(?:le\s+)?enviaste\s+S/\s*([0-9.,]+)\s+(?:a|para)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // GASTO: "Compra/pago realizado por S/ ..."
        RuleMatcher(
          regex: RegExp(
            r'(?:compra|pago)\s+.{0,20}?por\s+S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // INGRESO: "Recibiste S/ ... de [nombre]"
        RuleMatcher(
          regex: RegExp(
            r'recibiste\s+S/\s*([0-9.,]+)\s+(?:de|desde)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO: "Transferencia recibida por S/ ..."
        RuleMatcher(
          regex: RegExp(
            r'transferencia\s+(?:recibida|recibiste)\s+.{0,40}?S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO: "Abono en cuenta por S/ ..."
        RuleMatcher(
          regex: RegExp(
            r'abono\s+(?:en\s+cuenta|recibido)\s+.{0,25}?S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
      ],
    ),
    // ---------------- INTERBANK ----------------
    AppRule(
      package: 'com.interbank.bond',
      matchers: [
        // GASTO: "Transferencia interbancaria realizada por S/ ... a favor de [nombre]"
        RuleMatcher(
          regex: RegExp(
            r'transferencia\s+.{0,30}?(?:realizada|enviada)\s+.{0,30}?S/\s*([0-9.,]+)\s+(?:a|a favor de)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // GASTO: "Consumo/compra por S/ ..."
        RuleMatcher(
          regex: RegExp(
            r'(?:consumo|compra|pago)\s+.{0,20}?por\s+S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.expense,
        ),
        // INGRESO: "Recibiste X transferencia de S/ ... de [nombre]"
        RuleMatcher(
          regex: RegExp(
            r'(?:recibiste|has recibido)\s+(?:una\s+)?transferencia\s+.{0,30}?S/\s*([0-9.,]+)\s+(?:de|desde)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO: "Recibiste S/ ... de [nombre]"
        RuleMatcher(
          regex: RegExp(
            r'recibiste\s+S/\s*([0-9.,]+)\s+(?:de|desde)\s+([A-Za-zÁÉÍÓÚÑáéíóúñ\s]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
        // INGRESO: "Depósito por ventanilla/agente de S/ ..."
        RuleMatcher(
          regex: RegExp(
            r'dep[oó]sito\s+.{0,25}?S/\s*([0-9.,]+)',
            caseSensitive: false,
          ),
          type: TransactionType.income,
        ),
      ],
    ),
  ];

  // ------------------------------------------------------------------
  // Sanidad del texto: emojis, espacios y caracteres de control.
  // ------------------------------------------------------------------

  static final RegExp _emojiPattern = RegExp(
    r'[\u{1F000}-\u{1FAFF}\u{1F1E6}-\u{1F1FF}\u{2600}-\u{27BF}'
    r'\u{2B00}-\u{2BFF}\u{2190}-\u{21FF}\u{2300}-\u{23FF}\u{FE0F}]',
    unicode: true,
  );

  /// Normaliza una cadena antes de pasarla por las Regex:
  /// - Elimina emojis y símbolos misceláneos.
  /// - Elimina caracteres de control.
  /// - Colapsa múltiples espacios en uno solo.
  static String _sanitize(String input) {
    var value = input.replaceAll(_emojiPattern, ' ');
    value = value.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), ' ');
    return value.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ------------------------------------------------------------------
  // API pública
  // ------------------------------------------------------------------

  /// Parsea la notificación de una app financiera concreta.
  /// Si [packageName] es null se prueban todas las reglas.
  /// Antes de parsear, el texto se limpia (emojis + espacios) para
  /// maximizar la precisión con notificaciones reales del Perú.
  static ParsedTransaction? parse({
    required String title,
    required String text,
    String? packageName,
  }) {
    final cleanTitle = _sanitize(title);
    final cleanText = _sanitize(text);
    final body = '$cleanTitle\n$cleanText';

    final candidates = packageName != null
        ? _rules.where((r) => r.package == packageName)
        : _rules;

    for (final rule in candidates) {
      for (final matcher in rule.matchers) {
        final match = matcher.regex.firstMatch(body);
        if (match == null) continue;

        final amount = _extractAmount(body);
        if (amount == null || amount <= 0) continue;

        final counterparty = _extractPerson(
          matcher: matcher,
          match: match,
          title: cleanTitle,
          text: cleanText,
        );

        return ParsedTransaction(
          amount: amount,
          type: matcher.type,
          merchantOrPerson: _cleanName(counterparty),
          sourceApp: rule.appName,
        );
      }
    }

    // Fallback genérico: monto + tipo inferido por palabras clave.
    return _genericFallback(body, packageName);
  }

  /// Extrae la persona/contraparte de la transacción.
  ///
  /// Si el matcher define [RuleMatcher.personRegex], se busca la persona en
  /// el título y texto por separado (caso Lemon Cash: monto en el título,
  /// remitente en el texto). En caso contrario se usa el grupo capturado en
  /// [RuleMatcher.personGroup] de la propia regex del matcher.
  static String? _extractPerson({
    required RuleMatcher matcher,
    required RegExpMatch match,
    required String title,
    required String text,
  }) {
    if (matcher.personRegex != null) {
      final personMatch = matcher.personRegex!.firstMatch(title) ??
          matcher.personRegex!.firstMatch(text);
      if (personMatch != null && personMatch.groupCount >= matcher.personGroup) {
        return personMatch.group(matcher.personGroup);
      }
    }
    if (match.groupCount >= matcher.personGroup) {
      return match.group(matcher.personGroup);
    }
    return null;
  }

  /// Fallback para apps no listadas explícitamente (genérico y extensible).
  static ParsedTransaction? _genericFallback(String body, String? packageName) {
    final amount = _extractAmount(body);
    if (amount == null || amount <= 0) return null;

    final lower = body.toLowerCase();
    TransactionType type;
    String? person;

    if (lower.contains('recibido') ||
        lower.contains('recibida') ||
        lower.contains('recibiste') ||
        lower.contains('abono') ||
        lower.contains('deposito') ||
        lower.contains('crédito por') ||
        lower.contains('credito por') ||
        lower.contains('yapeó') ||
        lower.contains('te yapearon') ||
        lower.contains('yapearon') ||
        lower.contains('te envió un pago') ||
        lower.contains('te envió dinero') ||
        lower.contains('te pagó') ||
        lower.contains('recibiste un pago') ||
        lower.contains('pago recibido') ||
        lower.contains('transferencia recibida') ||
        lower.contains('recarga recibida')) {
      type = TransactionType.income;
    } else if (lower.contains('pagaste') ||
        lower.contains('enviaste') ||
        lower.contains('yapeaste') ||
        lower.contains('compra') ||
        lower.contains('pago realizado') ||
        lower.contains('transferencia efectuada') ||
        lower.contains('transferencia realizada') ||
        lower.contains('debitado') ||
        lower.contains('consumo') ||
        lower.contains('retiro')) {
      type = TransactionType.expense;
    } else {
      type = TransactionType.expense;
    }

    // Intento de extraer contraparte tras "a " o "en " o "de ".
    // Se usa un grupo de captura para el nombre y un lookbehind negativo para
    // no matchear dentro de palabras (ej. el "EN " dentro de "PEN").
    final personMatch = RegExp(
      r'(?<![A-Za-zÁÉÍÓÚÑáéíóúñ])(?:a|en|de)\s+'
      r'([A-Za-zÁÉÍÓÚÑáéíóúñ]{2,}(?:\s+[A-Za-zÁÉÍÓÚÑáéíóúñ]{2,})?)',
      caseSensitive: false,
    ).firstMatch(body);
    if (personMatch != null) {
      person = personMatch.group(1)!.trim();
    }

    return ParsedTransaction(
      amount: amount,
      type: type,
      merchantOrPerson: _cleanName(person),
      sourceApp: packageName,
      confidence: 0.6,
    );
  }

  /// Limpia nombres de comercios/personas.
  static String? _cleanName(String? raw) {
    if (raw == null) return null;
    var value = raw
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[.,\n]+$'), '')
        .trim();
    if (value.length > 40) value = value.substring(0, 40);
    return value.isEmpty ? null : value;
  }
}

/// Regla de parseo para una aplicación concreta.
class AppRule {
  const AppRule({
    required this.package,
    required this.matchers,
  });

  final String package;
  final List<RuleMatcher> matchers;

  String get appName => _appNameFor(package);

  static String _appNameFor(String package) {
    switch (package) {
      case 'com.bcp.innovacxion.yapeApp':
        return 'Yape';
      case 'com.bcp.bank.bcp':
        return 'BCP';
      case 'pe.agora.app':
        return 'Agora';
      case 'com.agora.app':
        return 'Sip/Agora';
      case 'com.lemon.lemoncash':
        return 'Lemon';
      case 'pe.plin.app':
        return 'Plin';
      case 'pe.com.bbva.bbvacontigo':
        return 'BBVA';
      case 'com.interbank.bond':
        return 'Interbank';
      default:
        return package;
    }
  }
}

/// Asociación entre una expresión regular y el tipo de transacción.
class RuleMatcher {
  const RuleMatcher({
    required this.regex,
    required this.type,
    this.personRegex,
    this.personGroup = 2,
  });

  final RegExp regex;
  final TransactionType type;

  /// Regex (opcional) para extraer la persona cuando no está en [regex]
  /// (p. ej. Lemon Cash: el monto va en el título y el remitente en el texto).
  final RegExp? personRegex;

  /// Grupo de captura de la persona dentro de [personRegex] o de [regex].
  final int personGroup;
}
