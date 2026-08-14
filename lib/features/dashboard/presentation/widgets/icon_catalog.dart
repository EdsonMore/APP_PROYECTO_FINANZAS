import 'package:flutter/material.dart';

/// Mapa de iconos de Material disponibles para cuentas y categorías,
/// junto con su nombre (string) para persistir.
class IconCatalog {
  static const Map<String, IconData> items = {
    'account_balance': Icons.account_balance,
    'account_balance_wallet': Icons.account_balance_wallet,
    'account_box': Icons.account_box,
    'auto_awesome': Icons.auto_awesome,
    'bolt': Icons.bolt,
    'bug_report': Icons.bug_report,
    'cake': Icons.cake,
    'credit_card': Icons.credit_card,
    'directions_bus': Icons.directions_bus,
    'fastfood': Icons.fastfood,
    'favorite': Icons.favorite,
    'healing': Icons.healing,
    'icecream': Icons.icecream,
    'insights': Icons.insights,
    'local_cafe': Icons.local_cafe,
    'local_mall': Icons.local_mall,
    'movie': Icons.movie,
    'payments': Icons.payments,
    'phone_android': Icons.phone_android,
    'receipt': Icons.receipt,
    'restaurant': Icons.restaurant,
    'shopping_cart': Icons.shopping_cart,
    'savings': Icons.savings,
    'whatshot': Icons.whatshot,
    'redeem': Icons.redeem,
    'flight': Icons.flight,
    'shield': Icons.shield_outlined,
    'speed': Icons.speed,
    'military_tech': Icons.military_tech,
    'record_voice_over': Icons.record_voice_over,
    'account_balance_wallet_outlined': Icons.account_balance_wallet_outlined,
  };

  static const IconData fallback = Icons.account_balance_wallet;

  /// Devuelve el [IconData] para un nombre, con [fallback] si no existe.
  static IconData iconFor(String? name) {
    if (name == null) return fallback;
    return items[name] ?? fallback;
  }

  /// Nombre de icono preferido para una cuenta por defecto.
  static String defaultForAccount(String accountName) {
    switch (accountName.toLowerCase()) {
      case 'yape':
        return 'phone_android';
      case 'bcp':
        return 'account_balance';
      case 'agora':
        return 'bolt';
      case 'lemon':
        return 'local_cafe';
      default:
        return 'account_balance_wallet';
    }
  }
}
