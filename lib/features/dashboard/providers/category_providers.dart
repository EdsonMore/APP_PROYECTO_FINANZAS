import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saldo_claro/core/models/category.dart';
import 'package:saldo_claro/core/models/transaction_type.dart';
import 'package:saldo_claro/features/dashboard/providers/repository_providers.dart';

/// Categorías del usuario (expense e income).
final categoriesProvider = FutureProvider<List<Category>>((ref) async {
  return ref.watch(categoryRepositoryProvider).fetchAll();
});

/// Categorías de un tipo concreto.
final categoriesByTypeProvider =
    FutureProvider.family<List<Category>, TransactionType>((ref, type) async {
  return ref.watch(categoryRepositoryProvider).fetchAll(type: type);
});
