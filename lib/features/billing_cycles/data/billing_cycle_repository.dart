import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:saldo_claro/core/network/supabase_client.dart';
import 'package:saldo_claro/features/billing_cycles/models/billing_cycle_model.dart';

/// Repositorio de ciclos de facturación (persistencia en Supabase).
class BillingCycleRepository {
  BillingCycleRepository({SupabaseClient? client})
      : _client = client ?? supabase;

  static const _uuid = Uuid();

  final SupabaseClient _client;

  /// Todos los ciclos del usuario ordenados por próxima fecha de vencimiento.
  Future<List<BillingCycle>> fetchAll() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _client
        .from('billing_cycles')
        .select()
        .eq('user_id', userId)
        .order('due_date', ascending: true);
    return rows.map(BillingCycle.fromMap).toList();
  }

  /// Ciclos activos con estado 'pending' (objetivo del Auto-Match).
  Future<List<BillingCycle>> fetchPendingActive() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _client
        .from('billing_cycles')
        .select()
        .eq('user_id', userId)
        .eq('is_active', true)
        .eq('status', 'pending');
    return rows.map(BillingCycle.fromMap).toList();
  }

  /// Crea un nuevo ciclo y devuelve la entidad persistida.
  Future<BillingCycle> insert({
    required String title,
    required BillingCategory category,
    required double amount,
    required DateTime dueDate,
    required BillingFrequency frequency,
    String? supplyNumber,
    List<String> keywords = const [],
    bool isAutoPay = false,
    bool isActive = true,
    BillingStatus status = BillingStatus.pending,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('Usuario no autenticado.');
    }

    final id = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();
    final row = {
      'id': id,
      'user_id': userId,
      'title': title.trim(),
      'category': category.dbValue,
      'amount': amount,
      'due_date': dueDate.toIso8601String().split('T').first,
      'frequency': frequency.dbValue,
      'supply_number': supplyNumber?.trim().isEmpty ?? true
          ? null
          : supplyNumber!.trim(),
      'keywords': keywords,
      'is_auto_pay': isAutoPay,
      'is_active': isActive,
      'status': status.dbValue,
      'created_at': now,
      'updated_at': now,
    };

    await _client.from('billing_cycles').insert(row);

    return BillingCycle(
      id: id,
      userId: userId,
      title: row['title'] as String,
      category: category,
      amount: amount,
      dueDate: dueDate,
      frequency: frequency,
      supplyNumber: row['supply_number'] as String?,
      keywords: keywords,
      isAutoPay: isAutoPay,
      isActive: isActive,
      status: status,
      createdAt: DateTime.parse(now),
      updatedAt: DateTime.parse(now),
    );
  }

  /// Actualiza los campos editables de un ciclo existente.
  Future<BillingCycle> update(BillingCycle cycle) async {
    final row = {
      'title': cycle.title.trim(),
      'category': cycle.category.dbValue,
      'amount': cycle.amount,
      'due_date': cycle.dueDate.toIso8601String().split('T').first,
      'frequency': cycle.frequency.dbValue,
      'supply_number': cycle.supplyNumber?.trim().isEmpty ?? true
          ? null
          : cycle.supplyNumber!.trim(),
      'keywords': cycle.keywords,
      'is_auto_pay': cycle.isAutoPay,
    };

    await _client
        .from('billing_cycles')
        .update(row)
        .eq('id', cycle.id);

    return cycle;
  }

  /// Elimina un ciclo (con sus notificaciones programadas).
  Future<void> delete(String id) async {
    await _client.from('billing_cycles').delete().eq('id', id);
  }

  /// Pausa o reanuda un ciclo sin borrarlo.
  Future<void> setActive(String id, bool isActive) async {
    await _client
        .from('billing_cycles')
        .update({'is_active': isActive})
        .eq('id', id);
  }

  /// Marca el ciclo como pagado y avanza a la siguiente fecha según su
  /// frecuencia, dejando el nuevo ciclo en estado 'pending'.
  ///
  /// Devuelve el nuevo ciclo (con la due_date recalculada) o null si no existe.
  Future<BillingCycle?> settleAndAdvance(String id) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final row = await _client
        .from('billing_cycles')
        .select()
        .eq('id', id)
        .eq('user_id', userId)
        .maybeSingle();
    if (row == null) return null;

    final current = BillingCycle.fromMap(row);
    final nextDate = current.nextDueDate();
    final updated = current.copyWith(
      dueDate: nextDate,
      status: BillingStatus.pending,
    );

    await _client
        .from('billing_cycles')
        .update({
          'status': 'pending',
          'due_date': nextDate.toIso8601String().split('T').first,
        })
        .eq('id', id);

    return updated;
  }
}
