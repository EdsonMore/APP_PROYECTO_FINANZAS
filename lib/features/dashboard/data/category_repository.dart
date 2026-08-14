import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:saldo_claro/core/models/category.dart';
import 'package:saldo_claro/core/models/transaction_type.dart';
import 'package:saldo_claro/core/network/supabase_client.dart';

/// Repositorio de categorías (persistencia en Supabase).
class CategoryRepository {
  CategoryRepository({SupabaseClient? client})
      : _client = client ?? supabase;

  final SupabaseClient _client;
  static const _uuid = Uuid();

  /// Lista las categorías del usuario actual, opcionalmente filtradas por tipo.
  Future<List<Category>> fetchAll({TransactionType? type}) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return const [];

    var query = _client.from('categories').select().eq('user_id', userId);
    if (type != null) {
      query = query.eq('type', type.badge);
    }
    final rows = await query.order('name');
    return rows.map(Category.fromMap).toList();
  }

  /// Crea una categoría nueva. Devuelve la categoría persistida.
  Future<Category> create({
    required String name,
    required TransactionType type,
    String icon = 'category',
    String? colorHex,
    List<String> keywords = const [],
    double? budget,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw StateError('Usuario no autenticado.');

    final id = _uuid.v4();
    await _client.from('categories').insert({
      'id': id,
      'user_id': userId,
      'name': name,
      'type': type.badge,
      'icon': icon,
      'color_hex': colorHex,
      'keywords': keywords,
      'budget': budget,
    });

    return Category(
      id: id,
      userId: userId,
      name: name,
      type: type,
      icon: icon,
      colorHex: colorHex,
      keywords: keywords,
      budget: budget,
    );
  }

  /// Actualiza los datos de una categoría.
  Future<void> update(Category category) async {
    await _client.from('categories').update({
      'name': category.name,
      'type': category.type.badge,
      'icon': category.icon,
      'color_hex': category.colorHex,
      'keywords': category.keywords,
      'budget': category.budget,
    }).eq('id', category.id);
  }

  /// Elimina una categoría.
  Future<void> delete(String categoryId) async {
    await _client.from('categories').delete().eq('id', categoryId);
  }

  /// Crea las categorías por defecto si el usuario aún no tiene ninguna.
  Future<void> ensureDefaults() async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    final userId = user.id;

    final existing = await _client
        .from('categories')
        .select('id')
        .eq('user_id', userId)
        .limit(1);
    if (existing.isNotEmpty) return;

    for (final cat in kDefaultCategories) {
      await _client.from('categories').insert({
        'id': _uuid.v4(),
        'user_id': userId,
        'name': cat['name'],
        'type': cat['type'],
        'icon': cat['icon'],
        'color_hex': cat['color_hex'],
        'keywords': (cat['keywords'] as List?) ?? const [],
      });
    }
  }
}
