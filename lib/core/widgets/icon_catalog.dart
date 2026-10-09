import 'package:flutter/material.dart';

/// Íconos de Material para categorías y fuentes. Se persiste el nombre
/// (`categories.icon`), nunca el codePoint.
abstract final class IconCatalog {
  static const Map<String, IconData> items = {
    'account_balance': Icons.account_balance,
    'account_balance_wallet': Icons.account_balance_wallet,
    'bolt': Icons.bolt,
    'cake': Icons.cake,
    'credit_card': Icons.credit_card,
    'directions_bus': Icons.directions_bus,
    'fastfood': Icons.fastfood,
    'favorite': Icons.favorite,
    'flight': Icons.flight,
    'healing': Icons.healing,
    'home': Icons.home,
    'icecream': Icons.icecream,
    'local_cafe': Icons.local_cafe,
    'local_mall': Icons.local_mall,
    'movie': Icons.movie,
    'payments': Icons.payments,
    'phone_android': Icons.phone_android,
    'receipt': Icons.receipt,
    'redeem': Icons.redeem,
    'restaurant': Icons.restaurant,
    'savings': Icons.savings,
    'school': Icons.school,
    'shopping_cart': Icons.shopping_cart,
  };

  static Iterable<IconData> get all => items.values;

  static const IconData fallback = Icons.category_outlined;

  /// Nombre desconocido (p. ej. guardado por otra versión) → [fallback], nunca crash.
  static IconData iconFor(String? name) => items[name] ?? fallback;
}
