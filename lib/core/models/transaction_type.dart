/// Tipo de transacción financiera.
enum TransactionType { income, expense }

extension TransactionTypeX on TransactionType {
  String get dbValue => name; // 'income' | 'expense'
  bool get isIncome => this == TransactionType.income;

  static TransactionType fromDb(String value) {
    return value == 'INCOME' || value == 'income'
        ? TransactionType.income
        : TransactionType.expense;
  }

  String get label => isIncome ? 'Ingreso' : 'Gasto';
  String get badge => isIncome ? 'INCOME' : 'EXPENSE';
}
