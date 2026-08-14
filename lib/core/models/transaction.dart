import 'transaction_type.dart';

/// Origen del registro de una transacción.
enum TransactionSource { auto, manual }

extension TransactionSourceX on TransactionSource {
  String get dbValue => name;
  String get badge => this == TransactionSource.auto
      ? 'Auto-Capturado'
      : 'Manual';

  static TransactionSource fromDb(String value) {
    return value == 'auto' ? TransactionSource.auto : TransactionSource.manual;
  }
}

/// Entidad de una transacción financiera.
class Transaction {
  const Transaction({
    required this.id,
    required this.userId,
    required this.accountId,
    this.categoryId,
    this.categoryName,
    required this.amount,
    required this.type,
    required this.rawText,
    this.merchantOrPerson,
    required this.sourceApp,
    required this.source,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String accountId;
  final String? categoryId;

  /// Nombre de la categoría (venido de la relación con `categories`).
  final String? categoryName;
  final double amount;
  final TransactionType type;
  final String rawText;
  final String? merchantOrPerson;
  final String sourceApp;
  final TransactionSource source;
  final DateTime createdAt;

  factory Transaction.fromMap(Map<String, dynamic> map) {
    // Soporta `select('*, categories(name)')` -> row['categories']['name'].
    String? categoryName;
    final cat = map['categories'];
    if (cat is Map<String, dynamic>) {
      categoryName = cat['name'] as String?;
    } else if (map['merchant_or_person'] is String && map['category_id'] != null) {
      categoryName = map['category_id'].toString();
    }

    return Transaction(
      id: map['id'] as String,
      userId: map['user_id'] as String,
      accountId: map['account_id'] as String,
      categoryId: map['category_id'] as String?,
      categoryName: categoryName,
      amount: (map['amount'] as num).toDouble(),
      type: TransactionTypeX.fromDb(map['type'] as String),
      rawText: (map['raw_text'] as String?) ?? '',
      merchantOrPerson: map['merchant_or_person'] as String?,
      sourceApp: (map['source_app'] as String?) ?? 'Manual',
      source: TransactionSourceX.fromDb(map['source'] as String? ?? 'manual'),
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '')
          ?? DateTime.now(),
    );
  }

  bool get isIncome => type.isIncome;
}
