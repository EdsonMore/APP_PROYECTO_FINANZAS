/// Entidad de una cuenta financiera (Yape, BCP, Agora, Lemon, Interbank, etc.).
class Account {
  const Account({
    required this.id,
    required this.userId,
    required this.name,
    required this.balance,
    this.bank,
    this.icon,
    this.colorHex,
    this.sortOrder = 0,
  });

  final String id;
  final String userId;
  final String name;

  /// Saldo actual de la cuenta.
  final double balance;

  /// Banco/App al que pertenece (libre). Ej: "Yape", "BBVA", "Plin".
  final String? bank;

  /// Nombre de icono de Material (ej. "account_balance_wallet").
  final String? icon;

  /// Color en formato Hex sin "#" (ej. "7B1FA2").
  final String? colorHex;

  /// Orden de visualización.
  final int sortOrder;

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      name: map['name'] as String,
      balance: (map['balance'] as num?)?.toDouble() ?? 0,
      bank: map['bank'] as String?,
      icon: map['icon'] as String?,
      colorHex: map['color_hex'] as String?,
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  /// Resuelve el color (int) a partir de `colorHex`, con un color por defecto.
  int get resolvedColor {
    final hex = colorHex?.replaceAll('#', '') ?? '';
    if (hex.length == 6) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null) return 0xFF000000 | value;
    }
    return 0xFF444A55;
  }

  /// Icono Material resuelto (con fallback).
  String get resolvedIcon {
    final name = icon?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return switch (this.name.toLowerCase()) {
      'yape' => 'phone_android',
      'bcp' => 'account_balance',
      'agora' => 'bolt',
      'lemon' => 'local_cafe',
      _ => 'account_balance_wallet',
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'name': name,
      'balance': balance,
      'bank': bank,
      'icon': icon,
      'color_hex': colorHex,
      'sort_order': sortOrder,
    };
  }

  Account copyWith({
    String? name,
    double? balance,
    String? bank,
    String? icon,
    String? colorHex,
    int? sortOrder,
  }) {
    return Account(
      id: id,
      userId: userId,
      name: name ?? this.name,
      balance: balance ?? this.balance,
      bank: bank ?? this.bank,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}

/// Mapeo entre un package de app (ej. "com.interbank") y una cuenta del usuario.
///
/// Se usa para reconocer automáticamente nuevas apps (Interbank, BBVA, Plin)
/// a partir de la captura de una notificación de prueba.
class AccountSourceMapping {
  const AccountSourceMapping({
    required this.id,
    required this.userId,
    required this.accountId,
    required this.packageName,
    required this.appName,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String accountId;
  final String packageName;
  final String appName;
  final DateTime? createdAt;

  factory AccountSourceMapping.fromMap(Map<String, dynamic> map) {
    return AccountSourceMapping(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      accountId: map['account_id'] as String,
      packageName: map['package_name'] as String,
      appName: (map['app_name'] as String?) ?? '',
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'account_id': accountId,
      'package_name': packageName,
      'app_name': appName,
      'created_at':
          (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }
}

/// Mapa de packages de apps conocidas (nombre de app -> package).
/// Se usa como sugerencias al mapear nuevas cuentas.
const Map<String, String> kKnownAppPackages = {
  'Interbank': 'com.interbank.bond',
  'BBVA': 'pe.com.bbva.bbvacontigo',
  'Plin': 'pe.plin.app',
  'Banco de la Nación': 'pe.gob.bn.android',
  'Scotiabank': 'pe.com.scotiabank',
  'BanBif': 'com.banbif.mobileapp',
};

/// Devuelve el package sugerido para un nombre de app conocido, si existe.
String? knownAppPackageFor(String appName) {
  final lower = appName.toLowerCase();
  for (final entry in kKnownAppPackages.entries) {
    if (entry.key.toLowerCase() == lower) return entry.value;
  }
  return null;
}
