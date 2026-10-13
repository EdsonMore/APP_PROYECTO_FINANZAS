import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Timeout de cada petición de sync.
const syncTimeout = Duration(seconds: 15);

/// Sin red, timeout, servidor caído o límite de peticiones: insistir no sirve,
/// push() se detiene y lo no subido queda pendiente.
class NetworkFailure implements Exception {
  const NetworkFailure();
}

/// Sesión vencida o inválida (401, JWT): el motor refresca la sesión una vez
/// y reintenta; si no se puede, pide volver a entrar. No es [NetworkFailure]:
/// sale de push() y de pull() sin marcar nada, todo queda pendiente.
class AuthExpiredFailure implements Exception {
  const AuthExpiredFailure();
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
  if (error is NetworkFailure || error is DataFailure || error is AuthExpiredFailure) return error as Exception;
  if (error is TimeoutException || error is SocketException || error is HttpException) return const NetworkFailure();
  if (error is PostgrestException) {
    final code = error.code ?? '';
    // Estado HTTP (3 dígitos). Los SQLSTATE de Postgres también son números
    // (23503) pero de 5 caracteres: esos son errores de datos.
    final http = code.length == 3 ? int.tryParse(code) : null;
    if (http == 401 || code == 'PGRST301' || code == 'PGRST303') return const AuthExpiredFailure(); // JWT vencido o inválido
    if (http != null && (http >= 500 || http == 429)) return const NetworkFailure();
    return DataFailure(code, error.message);
  }
  // Desconocido (p. ej. ClientException de http): se trata como red. Es lo
  // seguro: push() se detiene y todo queda pendiente, nada se pierde.
  return const NetworkFailure();
}

/// Filas por página al bajar: el máximo que devuelve PostgREST en Supabase.
const pullPageSize = 1000;

/// Lo que push() y pull() necesitan del servidor. Real: Supabase; tests: [FakeSyncRemote].
abstract interface class SyncRemote {
  /// Inserta o reemplaza [rows] (formato del servidor, sin user_id).
  /// Last-write-wins lo decide el trigger del servidor (SPEC §Sync), que
  /// DESCARTA en silencio una versión no más nueva que la guardada. Devuelve
  /// las claves que el servidor aceptó ([remoteRowKey]); las demás se
  /// descartaron y el teléfono tiene que traer la versión ganadora.
  Future<Set<String>> upsert(String table, List<Map<String, Object?>> rows);

  /// Marca borrada una fila (lápida). false = el servidor la descartó (tiene
  /// una versión más nueva) o la fila no está.
  Future<bool> markDeleted(String table, String id, int deletedAt);

  /// Las filas de [table] con esas claves, tal como están en el servidor
  /// (settings: la del usuario, sin importar [keys]).
  Future<List<Map<String, Object?>>> fetch(String table, List<String> keys);

  /// Una página de [table] ordenada por server_updated_at, desde [from]
  /// (excluido, o incluido si [inclusive]); null = desde el principio. Trae
  /// también las borradas (deleted_at), que son lápidas para el teléfono.
  Future<List<Map<String, Object?>>> pullPage(String table, {String? from, bool inclusive = false, int limit = pullPageSize});
}

/// Clave de conflicto y clave de fila en el servidor (ver supabase/migrations).
const _remoteConflict = {
  'categories': 'user_id,id',
  'sources': 'user_id,id',
  'accounts': 'user_id,id',
  'settings': 'user_id',
  'entries': 'user_id,id',
  'budgets': 'user_id,category_id',
  'transfers': 'user_id,id',
};
const _remoteKey = {'entries': 'id', 'budgets': 'category_id', 'transfers': 'id'};

/// Clave de una fila en el formato del servidor, como texto. settings tiene
/// una sola fila por usuario: su clave es 'settings'.
String remoteRowKey(String table, Map<String, Object?> row) =>
    table == 'settings' ? 'settings' : '${row[_remoteKey[table] ?? 'id']}';

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

  /// Columna clave en el servidor (settings: user_id).
  static String _keyColumn(String table) => table == 'settings' ? 'user_id' : _remoteKey[table] ?? 'id';

  @override
  Future<Set<String>> upsert(String table, List<Map<String, Object?>> rows) => _call(() async {
        // defaultToNull: false → "missing=default": user_id (que no se manda)
        // toma su default auth.uid() en vez de NULL. select(): solo vuelven las
        // filas escritas; las que el trigger descartó (return null), no.
        final written = await _client
            .from(table)
            .upsert(rows, onConflict: _remoteConflict[table], defaultToNull: false)
            .select(_keyColumn(table));
        return {for (final r in written) table == 'settings' ? 'settings' : '${r[_keyColumn(table)]}'};
      });

  @override
  Future<bool> markDeleted(String table, String id, int deletedAt) => _call(() async {
        final written = await _client
            .from(table)
            .update({'deleted_at': deletedAt, 'updated_at': deletedAt})
            .eq(_remoteKey[table]!, id)
            .select(_remoteKey[table]!);
        return written.isNotEmpty;
      });

  @override
  Future<List<Map<String, Object?>>> fetch(String table, List<String> keys) => _call(() async {
        final q = _client.from(table).select();
        return await (table == 'settings' ? q : q.inFilter(_keyColumn(table), keys));
      });

  @override
  Future<List<Map<String, Object?>>> pullPage(String table, {String? from, bool inclusive = false, int limit = pullPageSize}) =>
      _call(() async {
        // RLS ya limita a las filas del usuario; el índice (user_id, server_updated_at) la sirve.
        var q = _client.from(table).select();
        if (from != null) q = inclusive ? q.gte('server_updated_at', from) : q.gt('server_updated_at', from);
        return await q.order('server_updated_at', ascending: true).limit(limit);
      });
}

/// Servidor en memoria para tests: aplica last-write-wins como el trigger,
/// pone server_updated_at (1 s por escritura), simula las FK de categorías y
/// cuentas,
/// separa los datos por [user] (como RLS) y permite inyectar fallas.
class FakeSyncRemote implements SyncRemote {
  final _byUser = <String, Map<String, Map<String, Map<String, Object?>>>>{};

  /// Usuario de la sesión: cada uno ve solo sus filas.
  String user = 'u1';

  /// tabla → clave → fila, del usuario actual.
  Map<String, Map<String, Map<String, Object?>>> get rows => _byUser.putIfAbsent(user, () => {});

  var _tick = 0;
  String _serverNow() => DateTime.utc(2026, 10, 13).add(Duration(seconds: ++_tick)).toIso8601String();

  final log = <String>[];

  /// Filas tal como llegaron en cada upsert (lo que "viajó").
  final sent = <String, List<Map<String, Object?>>>{};
  final pullLog = <({String table, String? from})>[];

  /// Tabla en la que "se cae la red" al bajar.
  String? networkDownOnPull;

  /// Si es true, toda petición falla por sesión vencida.
  bool sessionExpired = false;

  /// Si es true, toda petición falla por red.
  bool offline = false;

  void _fail() {
    if (sessionExpired) throw const AuthExpiredFailure();
    if (offline) throw const NetworkFailure();
  }
  final upsertCalls = <({String table, int count})>[];

  /// ids (de cualquier tabla) que el servidor rechaza con un error de datos.
  Set<String> rejectIds = {};

  /// Tabla en la que "se cae la red".
  String? networkDownAtTable;

  /// id de lápida cuya subida falla por red.
  String? networkDownOnDelete;

  /// Se llama antes de cada upsert (para simular cambios durante la subida).
  Future<void> Function(String table)? onUpsert;

  static String _key(String table, Map<String, Object?> row) => remoteRowKey(table, row);

  /// Adelanta el reloj del servidor (para dejar una versión lejos del cursor).
  void tickSeconds(int seconds) => _tick += seconds;

  @override
  Future<Set<String>> upsert(String table, List<Map<String, Object?>> batch) async {
    await onUpsert?.call(table);
    _fail();
    log.add('upsert $table');
    upsertCalls.add((table: table, count: batch.length));
    sent.putIfAbsent(table, () => []).addAll([for (final r in batch) Map.of(r)]);
    if (networkDownAtTable == table) throw const NetworkFailure();
    for (final r in batch) {
      final id = _key(table, r);
      if (rejectIds.contains(id)) throw const DataFailure('23514', 'rechazada');
      final cat = r['category_id'];
      if (table == 'entries' && cat != null && !(rows['categories']?.containsKey(cat) ?? false)) {
        throw const DataFailure('23503', 'categoría inexistente');
      }
      // Fase 4A: account_id (entries) y los dos lados de transfers → accounts.
      for (final col in const ['account_id', 'from_account_id', 'to_account_id']) {
        final acc = r[col];
        if (acc != null && !(rows['accounts']?.containsKey(acc) ?? false)) {
          throw const DataFailure('23503', 'cuenta inexistente');
        }
      }
    }
    final t = rows.putIfAbsent(table, () => {});
    final accepted = <String>{};
    for (final r in batch) {
      final id = _key(table, r);
      final old = t[id];
      if (old == null || (r['updated_at']! as int) > (old['updated_at']! as int)) {
        t[id] = {...r, 'server_updated_at': _serverNow()};
        accepted.add(id);
      }
    }
    return accepted;
  }

  @override
  Future<bool> markDeleted(String table, String id, int deletedAt) async {
    log.add('delete $table $id');
    _fail();
    if (networkDownOnDelete == id) throw const NetworkFailure();
    final row = rows[table]?[id];
    if (row == null || deletedAt <= (row['updated_at']! as int)) return false;
    row
      ..['deleted_at'] = deletedAt
      ..['updated_at'] = deletedAt
      ..['server_updated_at'] = _serverNow();
    return true;
  }

  @override
  Future<List<Map<String, Object?>>> fetch(String table, List<String> keys) async {
    log.add('fetch $table');
    _fail();
    return [
      for (final MapEntry(:key, :value) in rows[table]?.entries ?? const <MapEntry<String, Map<String, Object?>>>[])
        if (table == 'settings' || keys.contains(key)) Map.of(value),
    ];
  }

  @override
  Future<List<Map<String, Object?>>> pullPage(String table, {String? from, bool inclusive = false, int limit = pullPageSize}) async {
    pullLog.add((table: table, from: from));
    log.add('pull $table');
    _fail();
    if (networkDownOnPull == table) throw const NetworkFailure();
    final since = from == null ? null : DateTime.parse(from);
    DateTime at(Map<String, Object?> r) => DateTime.parse(r['server_updated_at']! as String);
    final out = [
      for (final r in rows[table]?.values ?? const <Map<String, Object?>>[])
        if (since == null || (inclusive ? !at(r).isBefore(since) : at(r).isAfter(since))) Map.of(r),
    ]..sort((a, b) => at(a).compareTo(at(b)));
    return out.take(limit).toList();
  }
}
