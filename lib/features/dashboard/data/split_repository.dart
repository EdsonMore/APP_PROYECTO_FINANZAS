import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:saldo_claro/core/models/split.dart';
import 'package:saldo_claro/core/network/supabase_client.dart';

/// Repositorio de divisiones de gasto (splits) en Supabase.
class SplitRepository {
  SplitRepository({SupabaseClient? client})
      : _client = client ?? supabase;

  final SupabaseClient _client;
  static const _uuid = Uuid();

  /// Lista todos los splits del usuario, pendientes primero.
  Future<List<Split>> fetchAll() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _client
        .from('splits')
        .select('*, transactions(merchant_or_person, amount, created_at)')
        .eq('user_id', userId)
        .order('is_paid', ascending: true)
        .order('created_at', ascending: false);
    return rows.map(Split.fromMap).toList();
  }

  /// Crea un split (cuenta por cobrar a [debtorName]).
  Future<Split> create({
    required String transactionId,
    required String debtorName,
    required double amount,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Usuario no autenticado.');

    final id = _uuid.v4();
    await _client.from('splits').insert({
      'id': id,
      'user_id': userId,
      'transaction_id': transactionId,
      'debtor_name': debtorName,
      'amount': amount,
      'is_paid': false,
    });

    return Split(
      id: id,
      userId: userId,
      transactionId: transactionId,
      debtorName: debtorName,
      amount: amount,
    );
  }

  /// Marca un split como pagado o pendiente.
  Future<void> setPaid(String splitId, bool value) async {
    await _client
        .from('splits')
        .update({'is_paid': value})
        .eq('id', splitId);
  }

  /// Elimina un split.
  Future<void> delete(String splitId) async {
    await _client.from('splits').delete().eq('id', splitId);
  }
}