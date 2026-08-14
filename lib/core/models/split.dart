/// Entidad de una división de gasto (Split) con otra persona/pareja.
///
/// Cuando el usuario paga una cuenta compartida (ej. una cena de S/ 100),
/// puede marcar el 50% como "cuenta por cobrar" a su pareja.
class Split {
  const Split({
    required this.id,
    required this.userId,
    required this.transactionId,
    required this.debtorName,
    required this.amount,
    this.isPaid = false,
    this.createdAt,
  });

  final String id;
  final String userId;
  final String transactionId;

  /// Nombre de la persona que debe parte del gasto (ej. "Mi pareja").
  final String debtorName;

  /// Monto que se le cobra (p. ej. la mitad del gasto).
  final double amount;

  /// `true` cuando la deuda ya fue saldada.
  final bool isPaid;
  final DateTime? createdAt;

  factory Split.fromMap(Map<String, dynamic> map) {
    return Split(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      transactionId: map['transaction_id'] as String,
      debtorName: (map['debtor_name'] as String?) ?? 'Mi pareja',
      amount: (map['amount'] as num).toDouble(),
      isPaid: (map['is_paid'] as bool?) ?? false,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? ''),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'transaction_id': transactionId,
      'debtor_name': debtorName,
      'amount': amount,
      'is_paid': isPaid,
      'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
    };
  }

  Split copyWith({bool? isPaid, String? debtorName, double? amount}) {
    return Split(
      id: id,
      userId: userId,
      transactionId: transactionId,
      debtorName: debtorName ?? this.debtorName,
      amount: amount ?? this.amount,
      isPaid: isPaid ?? this.isPaid,
      createdAt: createdAt,
    );
  }
}