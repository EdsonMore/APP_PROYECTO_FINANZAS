/// Monto tecleado en el teclado propio. Inmutable y sin Flutter: el texto es la
/// fuente de verdad y los centavos se derivan de él con aritmética entera.
library;

const maxIntegerDigits = 6; // S/ 999,999.99
const maxDecimals = 2;

class AmountInput {
  const AmountInput([this.text = '']);

  /// Lo que el usuario tecleó, sin formato: '', '0.', '12', '12.5', '1250.05'.
  final String text;

  bool get isEmpty => text.isEmpty;

  String get _int => text.split('.').first;
  String? get _dec => text.contains('.') ? text.split('.').last : null;

  /// Aplica una tecla ('0'–'9' o '.'). null = tecla rechazada (la UI vibra).
  AmountInput? press(String key) {
    if (key == '.') {
      if (text.contains('.')) return null;
      return AmountInput(text.isEmpty ? '0.' : '$text.');
    }
    if (key.length != 1 || !'0123456789'.contains(key)) {
      throw ArgumentError.value(key, 'key', 'solo 0-9 o "."');
    }
    final dec = _dec;
    if (dec != null) {
      return dec.length >= maxDecimals ? null : AmountInput('$text$key');
    }
    if (text == '0') return key == '0' ? null : AmountInput(key); // sin ceros a la izquierda
    if (text.length >= maxIntegerDigits) return null;
    return AmountInput('$text$key');
  }

  AmountInput backspace() => isEmpty ? this : AmountInput(text.substring(0, text.length - 1));

  /// Centavos exactos: '12.5' → 1250, '0.05' → 5, '' → 0.
  int get cents {
    if (isEmpty) return 0;
    final whole = _int.isEmpty ? 0 : int.parse(_int);
    final dec = (_dec ?? '').padRight(maxDecimals, '0');
    return whole * 100 + int.parse(dec);
  }

  /// Partes para pintar "S/ " + tecleado (ink) + completado guía (inkMuted).
  /// '' → ('', '0.00') · '12' → ('12', '.00') · '1250.5' → ('1,250.5', '0').
  ({String typed, String ghost}) get display {
    if (isEmpty) return (typed: '', ghost: '0.00');
    final dec = _dec;
    final typed = dec == null ? _group(_int) : '${_group(_int)}.$dec';
    final ghost = dec == null ? '.00' : '0' * (maxDecimals - dec.length);
    return (typed: typed, ghost: ghost);
  }

  /// Separador de miles con coma (formato es_PE): 1250 → 1,250.
  static String _group(String digits) {
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
      b.write(digits[i]);
    }
    return b.toString();
  }

  @override
  bool operator ==(Object other) => other is AmountInput && other.text == text;

  @override
  int get hashCode => text.hashCode;
}
