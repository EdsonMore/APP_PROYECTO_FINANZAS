import 'transaction_type.dart';

/// Entidad de una categoría de gasto/ingreso.
class Category {
  const Category({
    required this.id,
    required this.userId,
    required this.name,
    required this.type,
    required this.icon,
    this.colorHex,
    this.keywords = const [],
    this.budget,
  });

  final String id;
  final String userId;
  final String name;
  final TransactionType type;
  final String icon;
  final String? colorHex;

  /// Palabras clave / comercios asociados para la categorización automática
  /// (ej. ["cine", "restaurante", "cinemark"]).
  final List<String> keywords;

  /// Presupuesto mensual opcional para esta categoría (p. ej. presupuesto
  /// de la categoría "Enamorada / Pareja").
  final double? budget;

  factory Category.fromMap(Map<String, dynamic> map) {
    final rawKeywords = map['keywords'];
    return Category(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      name: map['name'] as String,
      type: TransactionTypeX.fromDb(map['type'] as String),
      icon: (map['icon'] as String?) ?? 'category',
      colorHex: map['color_hex'] as String?,
      keywords: (rawKeywords is List)
          ? rawKeywords.map((e) => e.toString()).toList()
          : const [],
      budget: (map['budget'] as num?)?.toDouble(),
    );
  }

  int get resolvedColor {
    final hex = colorHex?.replaceAll('#', '') ?? '';
    if (hex.length == 6) {
      final value = int.tryParse(hex, radix: 16);
      if (value != null) return 0xFF000000 | value;
    }
    return 0xFF8E44AD;
  }

  Map<String, dynamic> toMap() => {
        'user_id': userId,
        'name': name,
        'type': type.badge,
        'icon': icon,
        'color_hex': colorHex,
        'keywords': keywords,
        'budget': budget,
      };

  Category copyWith({
    String? name,
    TransactionType? type,
    String? icon,
    String? colorHex,
    List<String>? keywords,
    double? budget,
  }) {
    return Category(
      id: id,
      userId: userId,
      name: name ?? this.name,
      type: type ?? this.type,
      icon: icon ?? this.icon,
      colorHex: colorHex ?? this.colorHex,
      keywords: keywords ?? this.keywords,
      budget: budget ?? this.budget,
    );
  }
}

/// Categorías por defecto (expense + income) creadas para cada usuario nuevo.
///
/// Incluye categorías predeterminadas creativas.
const List<Map<String, dynamic>> kDefaultCategories = [
  {
    'name': 'Alimentos',
    'type': 'EXPENSE',
    'icon': 'restaurant',
    'color_hex': 'E67E22',
    'keywords': ['restaurante', 'supermercado', 'plaza vea', 'wong', 'tambo', 'metro'],
  },
  {
    'name': 'Transporte',
    'type': 'EXPENSE',
    'icon': 'directions_bus',
    'color_hex': '3498DB',
    'keywords': ['taxi', 'uber', 'cabify', 'metro', 'corredor', 'pump'],
  },
  {
    'name': 'Compras',
    'type': 'EXPENSE',
    'icon': 'shopping_cart',
    'color_hex': '9B59B6',
    'keywords': ['tienda', 'falabella', 'ripley', 'saga', 'amazon', 'mercadolibre'],
  },
  {
    'name': 'Enamorada / Pareja',
    'type': 'EXPENSE',
    'icon': 'favorite',
    'color_hex': 'E91E63',
    'keywords': ['cine', 'cinemark', 'cineplanet', 'restaurante', 'flores', 'gift', 'regalo', 'pareja'],
  },
  {
    'name': 'Gasto Hormiga / Antojos',
    'type': 'EXPENSE',
    'icon': 'icecream',
    'color_hex': '8E44AD',
    'keywords': ['antojos', 'helado', 'cafe', 'starbucks', 'snack', 'golosina', 'chucheria'],
  },
  {
    'name': 'Gusto Culpable',
    'type': 'EXPENSE',
    'icon': 'whatshot',
    'color_hex': 'C0392B',
    'keywords': ['juego', 'steam', 'netflix', 'spotify', 'gaming', 'consola', 'suscripcion'],
  },
  {
    'name': 'Servicios',
    'type': 'EXPENSE',
    'icon': 'receipt',
    'color_hex': '16A085',
    'keywords': ['luz', 'agua', 'internet', 'telefono', 'claro', 'movistar', 'bitel'],
  },
  {
    'name': 'Salud',
    'type': 'EXPENSE',
    'icon': 'healing',
    'color_hex': '2ECC71',
    'keywords': ['farmacia', 'inkafarma', 'mifarma', 'medico', 'clinica', 'sana sana'],
  },
  {
    'name': 'Otros gastos',
    'type': 'EXPENSE',
    'icon': 'more_horiz',
    'color_hex': '7F8C8D',
    'keywords': [],
  },
  {'name': 'Ingresos', 'type': 'INCOME', 'icon': 'payments', 'color_hex': '27AE60', 'keywords': []},
];
