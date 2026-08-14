import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/models/transaction_type.dart';
import 'package:saldo_claro/core/network/supabase_client.dart';

/// Repositorio de transacciones (persistencia en Supabase).
class TransactionRepository {
  final SupabaseClient _client = supabase;
  static const _uuid = Uuid();

  /// Inserta una transacción y actualiza el balance de la cuenta.
  ///
  /// Devuelve la transacción persistida. Se ejecuta en una transacción RPC
  /// del lado del servidor (`insert_transaction`) si existe; de lo contrario
  /// hace un insert + update de balance de forma secuencial.
  Future<Transaction> insert({
    required String accountId,
    required double amount,
    required TransactionType type,
    String? categoryId,
    required String rawText,
    String? merchantOrPerson,
    required String sourceApp,
    required TransactionSource source,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuario no autenticado.');
    }

    final id = _uuid.v4();
    final createdAt = DateTime.now().toUtc().toIso8601String();

    final row = {
      'id': id,
      'user_id': userId,
      'account_id': accountId,
      'category_id': categoryId,
      'amount': amount,
      'type': type.badge,
      'raw_text': rawText,
      'merchant_or_person': merchantOrPerson,
      'source_app': sourceApp,
      'source': source.dbValue,
      'created_at': createdAt,
    };

    // Intenta usar la RPC transaccional si existe en la BD.
    try {
      await _client.rpc('insert_transaction', params: row);
    } on PostgrestException catch (e) {
      if (e.message.contains('insert_transaction')) {
        // RPC no creada: fallback al método secuencial.
        await _sequentialInsert(row);
      } else {
        rethrow;
      }
    } catch (_) {
      // Cualquier otro error de RPC -> fallback secuencial.
      await _sequentialInsert(row);
    }

    return Transaction(
      id: id,
      userId: userId,
      accountId: accountId,
      categoryId: categoryId,
      amount: amount,
      type: type,
      rawText: rawText,
      merchantOrPerson: merchantOrPerson,
      sourceApp: sourceApp,
      source: source,
      createdAt: DateTime.parse(createdAt),
    );
  }

  Future<void> _sequentialInsert(Map<String, dynamic> row) async {
    final inserted = await _client.from('transactions').insert(row).select();

    if (inserted.isNotEmpty) {
      // Ajusta el balance de la cuenta correspondiente.
      final accountId = row['account_id'] as String;
      final isIncome = row['type'] == 'INCOME';
      final amount = (row['amount'] as num).toDouble();

      final accountRow = await _client
          .from('accounts')
          .select('balance')
          .eq('id', accountId)
          .maybeSingle();
      if (accountRow != null) {
        final current = (accountRow['balance'] as num?)?.toDouble() ?? 0;
        final delta = isIncome ? amount : -amount;
        await _client
            .from('accounts')
            .update({'balance': current + delta})
            .eq('id', accountId);
      }
    }
  }

  /// Lista las transacciones del usuario ordenadas de más reciente a más antigua.
  Future<List<Transaction>> fetchRecent({int limit = 50}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _client
        .from('transactions')
        .select('*, accounts(name), categories(name)')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit);
    return rows.map(Transaction.fromMap).toList();
  }

  /// Escucha en tiempo real las nuevas transacciones del usuario.
  Stream<List<Transaction>> watchRecent({int limit = 50}) {
    final userId = _client.auth.currentUser?.id ?? '';
    return _client
        .from('transactions')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(limit)
        .map((rows) => rows.map(Transaction.fromMap).toList());
  }

  /// Lista todas las transacciones (para el motor de insights).
  Future<List<Transaction>> fetchAll() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _client
        .from('transactions')
        .select('*, accounts(name), categories(name)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    return rows.map(Transaction.fromMap).toList();
  }

  /// Total de gastos agrupados por categoría (para el gráfico).
  Future<Map<String, double>> expensesByCategory() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return {};

    final rows = await _client
        .from('transactions')
        .select('category_id, amount, categories(name)')
        .eq('user_id', userId)
        .eq('type', 'EXPENSE');

    final result = <String, double>{};
    for (final row in rows) {
      final category = (row['categories'] as Map?)?.values.firstOrNull;
      final name = category is String
          ? category
          : 'Sin categoría';
      result[name] = (result[name] ?? 0) + (row['amount'] as num).toDouble();
    }
    return result;
  }
}

extension _FirstOrNull on Iterable {
  dynamic get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
