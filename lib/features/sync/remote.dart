import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Timeout de cada petición de sync.
const syncTimeout = Duration(seconds: 15);

/// Sin red, timeout, servidor caído, límite de peticiones o sesión vencida:
/// insistir no sirve, push() se detiene y lo no subido queda pendiente.
class NetworkFailure implements Exception {
  const NetworkFailure();
}

/// La fila no pasa una regla del servidor (CHECK, FK, NOT NULL, RLS): queda
/// pendiente y push() sigue con la siguiente. [code] es el código de
/// Postgres; [message] su texto, sin datos de la sesión.
class DataFailure implements Exception {
  const DataFailure(this.code, this.message);
  final String code;
  final String message;
}

/// Clasifica cualquier error de una petición de sync.
Exception syncFailureFrom(Object error) {
  if (error is NetworkFailure || error is DataFailure) return error as Exception;
  if (error is TimeoutException || error is SocketException || error is HttpException) return const NetworkFailure();
  if (error is PostgrestException) {
    final code = error.code ?? '';
    // Estado HTTP (3 dígitos). Los SQLSTATE de Postgres también son números
    // (23503) pero de 5 caracteres: esos son errores de datos.
    final http = code.length == 3 ? int.tryParse(code) : null;
    if (http != null && (http >= 500 || http == 429 || http == 401)) return const NetworkFailure();
    if (code == 'PGRST301' || code == 'PGRST303') return const NetworkFailure(); // JWT vencido o inválido
    return DataFailure(code, error.message);
  }
  // Desconocido (p. ej. ClientException de http): se trata como red. Es lo
  // seguro: push() se detiene y todo queda pendiente, nada se pierde.
  return const NetworkFailure();
}

/// Lo que push() necesita del servidor. Real: Supabase; tests: [FakeSyncRemote].
abstract interface class SyncRemote {
  /// Inserta o reemplaza [rows] (formato del servidor, sin user_id).
  /// Last-write-wins lo decide el trigger del servidor (SPEC §Sync).
  Future<void> upsert(String table, List<Map<String, Object?>> rows);

  /// Marca borrada una fila que ya estaba en el servidor (lápida).
  Future<void> markDeleted(String table, String id, int deletedAt);
}

/// Clave de conflicto y clave de fila en el servidor (ver supabase/migrations).
const _remoteConflict = {
  'categories': 'user_id,id',
  'sources': 'user_id,id',
  'settings': 'user_id',
  'entries': 'user_id,id',
  'budgets': 'user_id,category_id',
};
const _remoteKey = {'entries': 'id', 'budgets': 'category_id'};

class SupabaseSyncRemote implements SyncRemote {
  SupabaseSyncRemote(this._client);
  final SupabaseClient _client;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request().timeout(syncTimeout);
    } catch (e) {
      throw syncFailureFrom(e);
    }
  }

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows) => _call(() async {
        // defaultToNull: false → "missing=default": user_id (que no se manda)
        // toma su default auth.uid() en vez de NULL.
        await _client.from(table).upsert(rows, onConflict: _remoteConflict[table], defaultToNull: false);
      });

  @override
  Future<void> markDeleted(String table, String id, int deletedAt) => _call(() async {
        await _client
            .from(table)
            .update({'deleted_at': deletedAt, 'updated_at': deletedAt}).eq(_remoteKey[table]!, id);
      });
}

/// Servidor en memoria para tests: aplica last-write-wins como el trigger,
/// simula la FK de categorías/fuentes y permite inyectar fallas.
class FakeSyncRemote implements SyncRemote {
  /// tabla → clave → fila.
  final rows = <String, Map<String, Map<String, Object?>>>{};
  final log = <String>[];
  final upsertCalls = <({String table, int count})>[];

  /// ids (de cualquier tabla) que el servidor rechaza con un error de datos.
  Set<String> rejectIds = {};

  /// Tabla en la que "se cae la red".
  String? networkDownAtTable;

  /// id de lápida cuya subida falla por red.
  String? networkDownOnDelete;

  /// Se llama antes de cada upsert (para simular cambios durante la subida).
  Future<void> Function(String table)? onUpsert;

  static String _key(String table, Map<String, Object?> row) =>
      table == 'settings' ? 'user' : '${row[_remoteKey[table] ?? 'id']}';

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> batch) async {
    await onUpsert?.call(table);
    log.add('upsert $table');
    upsertCalls.add((table: table, count: batch.length));
    if (networkDownAtTable == table) throw const NetworkFailure();
    for (final r in batch) {
      final id = _key(table, r);
      if (rejectIds.contains(id)) throw const DataFailure('23514', 'rechazada');
      final cat = r['category_id'];
      if (table == 'entries' && cat != null && !(rows['categories']?.containsKey(cat) ?? false)) {
        throw const DataFailure('23503', 'categoría inexistente');
      }
    }
    final t = rows.putIfAbsent(table, () => {});
    for (final r in batch) {
      final id = _key(table, r);
      final old = t[id];
      if (old == null || (r['updated_at']! as int) > (old['updated_at']! as int)) t[id] = Map.of(r);
    }
  }

  @override
  Future<void> markDeleted(String table, String id, int deletedAt) async {
    log.add('delete $table $id');
    if (networkDownOnDelete == id) throw const NetworkFailure();
    final row = rows[table]?[id];
    if (row != null && deletedAt > (row['updated_at']! as int)) {
      row
        ..['deleted_at'] = deletedAt
        ..['updated_at'] = deletedAt;
    }
  }
}
