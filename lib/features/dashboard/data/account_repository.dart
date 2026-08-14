import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:saldo_claro/core/models/account.dart';
import 'package:saldo_claro/core/network/supabase_client.dart';

/// Repositorio de cuentas financieras (persistencia en Supabase).
class AccountRepository {
  AccountRepository({SupabaseClient? client})
      : _client = client ?? supabase;

  final SupabaseClient _client;
  static const _uuid = Uuid();

  /// Cuentas iniciales sugeridas para un usuario nuevo.
  /// (Ya no es un "hardcodeo rígido": solo son sugerencias que el usuario
  ///  puede editar, eliminar o ampliar libremente desde "Gestión de Cuentas".)
  static const List<Map<String, dynamic>> kStarterAccounts = [
    {'name': 'Yape', 'bank': 'Yape/BCP', 'icon': 'phone_android', 'color_hex': '7B1FA2', 'sort_order': 0},
    {'name': 'BCP', 'bank': 'BCP', 'icon': 'account_balance', 'color_hex': '002A8F', 'sort_order': 1},
    {'name': 'Agora', 'bank': 'Agora', 'icon': 'bolt', 'color_hex': 'EF3340', 'sort_order': 2},
    {'name': 'Lemon', 'bank': 'Lemon Cash', 'icon': 'local_cafe', 'color_hex': '00A859', 'sort_order': 3},
  ];

  /// Devuelve la cuenta por su id.
  Future<Account?> findById(String accountId) async {
    final rows = await _client
        .from('accounts')
        .select()
        .eq('id', accountId)
        .maybeSingle();
    if (rows == null) return null;
    return Account.fromMap(rows);
  }

  /// Devuelve la cuenta por nombre (case-insensitive) del usuario actual.
  Future<Account?> findByName(String name) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final rows = await _client
        .from('accounts')
        .select()
        .eq('user_id', userId)
        .eq('name', name)
        .maybeSingle();
    if (rows == null) return null;
    return Account.fromMap(rows);
  }

  /// Lista todas las cuentas del usuario actual, ordenadas.
  Future<List<Account>> fetchAll() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _client
        .from('accounts')
        .select()
        .eq('user_id', userId)
        .order('sort_order', ascending: true)
        .order('name', ascending: true);
    return rows.map(Account.fromMap).toList();
  }

  /// Crea una cuenta nueva. Devuelve la cuenta persistida.
  Future<Account> create({
    required String name,
    double balance = 0,
    String? bank,
    String? icon,
    String? colorHex,
    int sortOrder = 99,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Usuario no autenticado.');

    final id = _uuid.v4();
    await _client.from('accounts').insert({
      'id': id,
      'user_id': userId,
      'name': name,
      'balance': balance,
      'bank': bank,
      'icon': icon,
      'color_hex': colorHex,
      'sort_order': sortOrder,
    });

    return Account(
      id: id,
      userId: userId,
      name: name,
      balance: balance,
      bank: bank,
      icon: icon,
      colorHex: colorHex,
      sortOrder: sortOrder,
    );
  }

  /// Actualiza los datos de una cuenta (incluyendo saldo si se indica).
  Future<void> update(Account account, {double? newBalance}) async {
    await _client.from('accounts').update({
      'balance': ?newBalance,
      'name': account.name,
      'bank': account.bank,
      'icon': account.icon,
      'color_hex': account.colorHex,
      'sort_order': account.sortOrder,
    }).eq('id', account.id);
  }

  /// Actualiza solo el saldo de una cuenta.
  Future<void> updateBalance(String accountId, double newBalance) async {
    await _client
        .from('accounts')
        .update({'balance': newBalance})
        .eq('id', accountId);
  }

  /// Ajusta el balance de una cuenta en [delta] usando la RPC
  /// `adjust_account_balance` (atómica, del lado del servidor).
  ///
  /// Se usa al editar el saldo inicial de una cuenta existente para fijar el
  /// saldo base sin generar duplicar movimientos en el historial.
  Future<void> adjustBalance(String accountId, double delta) async {
    if (delta.abs() < 0.0001) return;
    await _client.rpc('adjust_account_balance', params: {
      'p_account_id': accountId,
      'p_delta': delta,
    });
  }

  /// Registra el "Saldo inicial" de una cuenta como una transacción especial
  /// de tipo INCOME con categoría `'Saldo Inicial'`.
  ///
  /// Usa la RPC transaccional `insert_transaction` para insertar el movimiento
  /// y ajustar el saldo de forma atómica (la cuenta debe partir de 0.00).
  Future<void> registerInitialBalance({
    required String accountId,
    required double amount,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null || amount <= 0) return;

    final categoryId = await _ensureSaldoInicialCategory(userId);
    await _client.rpc('insert_transaction', params: {
      'p_id': _uuid.v4(),
      'p_user_id': userId,
      'p_account_id': accountId,
      'p_category_id': categoryId,
      'p_amount': amount,
      'p_type': 'INCOME',
      'p_raw_text': 'Saldo inicial de la cuenta',
      'p_merchant_or_person': 'Saldo Inicial',
      'p_source_app': 'Manual',
      'p_source': 'manual',
      'p_created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Busca o crea la categoría `'Saldo Inicial'` (INCOME) del usuario.
  Future<String> _ensureSaldoInicialCategory(String userId) async {
    final existing = await _client
        .from('categories')
        .select('id')
        .eq('user_id', userId)
        .eq('name', 'Saldo Inicial')
        .eq('type', 'INCOME')
        .maybeSingle();
    if (existing != null) return existing['id'] as String;

    final id = _uuid.v4();
    await _client.from('categories').insert({
      'id': id,
      'user_id': userId,
      'name': 'Saldo Inicial',
      'type': 'INCOME',
      'icon': 'savings',
      'color_hex': '27AE60',
      'keywords': <String>[],
    });
    return id;
  }

  /// Elimina una cuenta. Las transacciones asociadas se borran (cascade).
  Future<void> delete(String accountId) async {
    await _client.from('accounts').delete().eq('id', accountId);
  }

  /// Crea las cuentas iniciales sugeridas si el usuario aún no tiene ninguna.
  Future<void> ensureDefaults() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final userId = user.id;

    final existing = await _client
        .from('accounts')
        .select('id')
        .eq('user_id', userId)
        .limit(1);
    if (existing.isNotEmpty) return; // ya creó o personalizó sus cuentas

    for (final (index, starter) in kStarterAccounts.indexed) {
      await _client.from('accounts').insert({
        ...starter,
        'id': _uuid.v4(),
        'user_id': userId,
        'balance': 0,
        'sort_order': starter['sort_order'] ?? index,
      });
    }
  }

  // ------------------------------------------------------------------
  // Mapeo de packages de apps -> cuentas (reconocimiento automático)
  // ------------------------------------------------------------------

  /// Registra o actualiza el mapeo de un package a una cuenta.
  Future<void> upsertSource({
    required String accountId,
    required String packageName,
    String? appName,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Usuario no autenticado.');

    await _client.from('account_sources').upsert({
      'user_id': userId,
      'account_id': accountId,
      'package_name': packageName,
      'app_name': appName ?? packageName,
    }, onConflict: 'user_id,package_name');
  }

  /// Busca la cuenta asociada a un package de app.
  Future<Account?> findAccountForPackage(String packageName) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return null;

    final rows = await _client
        .from('account_sources')
        .select('accounts(*)')
        .eq('user_id', userId)
        .eq('package_name', packageName)
        .maybeSingle();

    final account = rows?['accounts'];
    if (account is Map<String, dynamic>) return Account.fromMap(account);
    return null;
  }

  /// Lista todos los mapeos de sources del usuario.
  Future<List<AccountSourceMapping>> fetchSources() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    final rows = await _client
        .from('account_sources')
        .select()
        .eq('user_id', userId)
        .order('app_name');
    return rows.map(AccountSourceMapping.fromMap).toList();
  }

  /// Elimina un mapeo de source por su id.
  Future<void> deleteSource(String sourceId) async {
    await _client.from('account_sources').delete().eq('id', sourceId);
  }
}
