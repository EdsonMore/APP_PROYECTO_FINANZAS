import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saldo_claro/features/dashboard/data/account_repository.dart';
import 'package:saldo_claro/features/dashboard/data/category_repository.dart';
import 'package:saldo_claro/features/dashboard/data/settings_repository.dart';
import 'package:saldo_claro/features/dashboard/data/split_repository.dart';
import 'package:saldo_claro/features/dashboard/data/transaction_repository.dart';

// Repositorios del módulo dashboard (instancias únicas compartidas).
final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  return AccountRepository();
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository();
});

final transactionRepositoryProvider = Provider<TransactionRepository>((ref) {
  return TransactionRepository();
});

final splitRepositoryProvider = Provider<SplitRepository>((ref) {
  return SplitRepository();
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});
