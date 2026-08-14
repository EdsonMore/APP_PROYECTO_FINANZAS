/// Categoría de un ciclo de facturación.
enum BillingCategory { utilityService, subscription }

extension BillingCategoryX on BillingCategory {
  String get dbValue => this == BillingCategory.utilityService
      ? 'utility_service'
      : 'subscription';
  String get label => this == BillingCategory.utilityService
      ? 'Servicio público'
      : 'Suscripción';

  String get emoji => this == BillingCategory.utilityService ? '🧾' : '🔁';

  static BillingCategory fromDb(String value) {
    return value == 'subscription'
        ? BillingCategory.subscription
        : BillingCategory.utilityService;
  }
}

/// Frecuencia con la que se repite el pago de un servicio.
enum BillingFrequency { monthly, bimonthly, yearly }

extension BillingFrequencyX on BillingFrequency {
  String get dbValue => name; // 'monthly' | 'bimonthly' | 'yearly'
  String get label => switch (this) {
        BillingFrequency.monthly => 'Mensual',
        BillingFrequency.bimonthly => 'Bimestral',
        BillingFrequency.yearly => 'Anual',
      };

  /// Meses que se suman a la próxima fecha de vencimiento.
  int get months => switch (this) {
        BillingFrequency.monthly => 1,
        BillingFrequency.bimonthly => 2,
        BillingFrequency.yearly => 12,
      };

  static BillingFrequency fromDb(String value) {
    return switch (value) {
      'bimonthly' => BillingFrequency.bimonthly,
      'yearly' => BillingFrequency.yearly,
      _ => BillingFrequency.monthly,
    };
  }
}

/// Estado actual del ciclo de facturación.
enum BillingStatus { pending, paid, overdue }

extension BillingStatusX on BillingStatus {
  String get dbValue => name; // 'pending' | 'paid' | 'overdue'

  static BillingStatus fromDb(String value) {
    return switch (value) {
      'paid' => BillingStatus.paid,
      'overdue' => BillingStatus.overdue,
      _ => BillingStatus.pending,
    };
  }
}

/// Nivel de urgencia visual de una tarjeta de servicio.
enum BillingUrgency {
  ok, // 🟢 > 5 días
  warning, // 🟡 2 a 5 días
  urgent, // 🔴 ≤ 1 día o vencido
}

/// Entidad de un ciclo de facturación/servicio recurrente.
///
/// Ej: "ENOSA - Luz", "EPS Grau", "Netflix".
class BillingCycle {
  const BillingCycle({
    required this.id,
    required this.userId,
    required this.title,
    required this.category,
    required this.amount,
    required this.dueDate,
    required this.frequency,
    this.supplyNumber,
    this.keywords = const [],
    this.isAutoPay = false,
    this.isActive = true,
    this.status = BillingStatus.pending,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String title;
  final BillingCategory category;
  final double amount;
  final DateTime dueDate;
  final BillingFrequency frequency;
  final String? supplyNumber;
  final List<String> keywords;
  final bool isAutoPay;
  final bool isActive;
  final BillingStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Solo la parte de fecha (evita bugs por la hora actual).
  DateTime get dateOnly => DateTime(dueDate.year, dueDate.month, dueDate.day);

  /// Días que faltan para el vencimiento. Negativo => vencido.
  int get daysUntilDue {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    return dateOnly.difference(todayOnly).inDays;
  }

  /// Nivel de urgencia según la fecha de vencimiento.
  BillingUrgency get urgency {
    final days = daysUntilDue;
    if (days <= 1) return BillingUrgency.urgent;
    if (days <= 5) return BillingUrgency.warning;
    return BillingUrgency.ok;
  }

  /// Siguiente fecha de vencimiento según la frecuencia.
  DateTime nextDueDate() {
    return DateTime(
      dateOnly.year,
      dateOnly.month + frequency.months,
      dateOnly.day,
    );
  }

  /// Ícono dinámico por categoría/keywords de coincidencia.
  ///
  /// Luz 💡, Agua 💧, Internet 🌐, Streaming 🎬 y fallback por categoría.
  String get emoji {
    final text = '$title ${keywords.join(' ')}'.toLowerCase();
    if (text.contains('luz') ||
        text.contains('enosa') ||
        text.contains('distriluz') ||
        text.contains('hidrandina') ||
        text.contains('electro')) {
      return '💡';
    }
    if (text.contains('agua') ||
        text.contains('sedapal') ||
        text.contains('eps') ||
        text.contains('grau') ||
        text.contains('saneamiento')) {
      return '💧';
    }
    if (text.contains('internet') ||
        text.contains('wifi') ||
        text.contains('movistar') ||
        text.contains('entel') ||
        text.contains('claro') ||
        text.contains('fiber') ||
        text.contains('telefonia') ||
        text.contains('cable')) {
      return '🌐';
    }
    if (text.contains('netflix') ||
        text.contains('spotify') ||
        text.contains('disney') ||
        text.contains('prime') ||
        text.contains('hbo') ||
        text.contains('streaming') ||
        text.contains('youtube') ||
        text.contains('apple music')) {
      return '🎬';
    }
    return category.emoji;
  }

  factory BillingCycle.fromMap(Map<String, dynamic> map) {
    return BillingCycle(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      title: (map['title'] as String?) ?? '',
      category: BillingCategoryX.fromDb(map['category'] as String? ?? ''),
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      dueDate: DateTime.tryParse(map['due_date'] as String? ?? '') ??
          DateTime.now(),
      frequency: BillingFrequencyX.fromDb(map['frequency'] as String? ?? ''),
      supplyNumber: map['supply_number'] as String?,
      keywords: _stringList(map['keywords']),
      isAutoPay: (map['is_auto_pay'] as bool?) ?? false,
      isActive: (map['is_active'] as bool?) ?? true,
      status: BillingStatusX.fromDb(map['status'] as String? ?? 'pending'),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) {
      return value.whereType<String>().toList();
    }
    return const [];
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'title': title,
      'category': category.dbValue,
      'amount': amount,
      'due_date': dueDate.toIso8601String().split('T').first,
      'frequency': frequency.dbValue,
      'supply_number': supplyNumber,
      'keywords': keywords,
      'is_auto_pay': isAutoPay,
      'is_active': isActive,
      'status': status.dbValue,
      'created_at': createdAt.toUtc().toIso8601String(),
      'updated_at': updatedAt.toUtc().toIso8601String(),
    };
  }

  BillingCycle copyWith({
    String? title,
    BillingCategory? category,
    double? amount,
    DateTime? dueDate,
    BillingFrequency? frequency,
    String? supplyNumber,
    List<String>? keywords,
    bool? isAutoPay,
    bool? isActive,
    BillingStatus? status,
  }) {
    return BillingCycle(
      id: id,
      userId: userId,
      title: title ?? this.title,
      category: category ?? this.category,
      amount: amount ?? this.amount,
      dueDate: dueDate ?? this.dueDate,
      frequency: frequency ?? this.frequency,
      supplyNumber: supplyNumber ?? this.supplyNumber,
      keywords: keywords ?? this.keywords,
      isAutoPay: isAutoPay ?? this.isAutoPay,
      isActive: isActive ?? this.isActive,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}
