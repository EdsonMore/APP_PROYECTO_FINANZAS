import 'package:drift/drift.dart';

import '../../data/database.dart';
import 'remote.dart';

/// Al bajar se pide desde cursor − [pullOverlap]: una transacción del servidor
/// que confirma tarde puede dejar un server_updated_at algo anterior al último
/// cursor (nota del trigger 003). Aplicar dos veces la misma fila no cambia
/// nada, así que releer esos segundos no hace daño.
const pullOverlap = Duration(seconds: 10);

enum PullMode {
  /// Normal: gana el updated_at mayor, fila por fila.
  merge,

  /// D5 "Unir": como merge, pero los ajustes de la nube ganan siempre (si no,
  /// los del teléfono que recién entra pisarían modo y espacio de la cuenta).
  join,

  /// D5 "Usar solo lo de la nube": borra lo sincronizable del teléfono y deja
  /// exactamente lo de la nube. Baja todo, sin cursores.
  replace,
}

class PullResult {
  const PullResult({this.downloaded = 0, this.applied = 0, this.skipped = 0});

  /// Filas recibidas del servidor (incluye lápidas y relecturas).
  final int downloaded;

  /// Filas que cambiaron algo en el teléfono.
  final int applied;

  /// Filas que no se pudieron aplicar (p. ej. un CHECK local): se saltan para
  /// no trabar la sincronización; el motor las cuenta como problema.
  final int skipped;
}

/// Bajada: hijos antes que padres. En el servidor un padre existe antes que
/// sus hijos y categorías/fuentes/cuentas nunca se borran, así que todo hijo
/// bajado tiene su padre en el teléfono o en una lectura posterior de esta
/// bajada. (Se APLICA en el orden de [AppDatabase.syncTables]: padres primero.)
const _downloadOrder = ['transfers', 'budgets', 'entries', 'settings', 'accounts', 'sources', 'categories'];

/// Se archivan, nunca se borran; su nombre es UNIQUE en el teléfono.
const _catalogs = {'categories', 'sources', 'accounts'};

/// Baja lo nuevo del servidor (SPEC §Sync, tabla de reglas) y lo aplica en
/// UNA transacción local, junto con los cursores: si algo falla a mitad, no
/// cambia nada y la próxima vez se baja de nuevo.
class Puller {
  Puller(this._db, this._remote, {this.pageSize = pullPageSize});
  final AppDatabase _db;
  final SyncRemote _remote;
  final int pageSize;

  Future<PullResult> pull({PullMode mode = PullMode.merge}) async =>
      apply(await download(full: mode == PullMode.replace), mode: mode);

  /// Todo lo posterior a cada cursor (o todo, si [full]). Sin red, lanza.
  Future<Map<String, List<Map<String, Object?>>>> download({bool full = false}) async {
    final cursors = full ? const <String, String>{} : await _db.readSyncCursors();
    final out = <String, List<Map<String, Object?>>>{};
    for (final table in _downloadOrder) {
      final cursor = cursors[table];
      var from = cursor == null || cursor.isEmpty
          ? null
          : DateTime.parse(cursor).subtract(pullOverlap).toUtc().toIso8601String();
      var inclusive = false;
      final byKey = <Object?, Map<String, Object?>>{}; // las páginas se solapan en el borde
      while (true) {
        final page = await _remote.pullPage(table, from: from, inclusive: inclusive, limit: pageSize);
        for (final r in page) {
          byKey[table == 'settings' ? 'settings' : r[AppDatabase.syncTables[table]!]] = r;
        }
        if (page.length < pageSize) break;
        final last = page.last['server_updated_at']! as String;
        // ponytail: si una página entera comparte server_updated_at, >= no
        // avanza y se pasa a > (con clock_timestamp() es prácticamente imposible).
        if (inclusive && last == from) {
          inclusive = false;
        } else {
          from = last;
          inclusive = true;
        }
      }
      out[table] = byKey.values.toList();
    }
    return out;
  }

  /// Lo que el servidor descartó en un push (tenía una versión más nueva o
  /// la fila ya no estaba): se trae por clave y se aplica, sin mover los
  /// cursores. Una lápida de una fila que el servidor no tiene se descarta.
  /// Sin esto, el teléfono quedaría con su versión marcada como subida y la
  /// del servidor detrás del cursor: nunca convergerían.
  Future<PullResult> reconcile(Map<String, List<String>> discarded) async {
    final fetched = <String, List<Map<String, Object?>>>{};
    for (final MapEntry(key: table, value: keys) in discarded.entries) {
      fetched[table] = await _remote.fetch(table, keys);
    }
    final result = await apply(fetched, saveCursors: false);
    await _db.transaction(() async {
      for (final MapEntry(key: table, value: keys) in discarded.entries) {
        final found = {for (final r in fetched[table]!) remoteRowKey(table, r)};
        for (final k in keys.where((k) => !found.contains(k))) {
          await _db.customUpdate('DELETE FROM tombstones WHERE entity = ? AND row_id = ?',
              variables: [Variable(table), Variable(k)], updates: {_db.tombstones}, updateKind: UpdateKind.delete);
        }
      }
    });
    return result;
  }

  Future<PullResult> apply(Map<String, List<Map<String, Object?>>> downloaded,
      {PullMode mode = PullMode.merge, bool saveCursors = true}) async {
    var applied = 0, skipped = 0, total = 0;
    await _db.transaction(() async {
      final cursors = await _db.readSyncCursors();
      if (mode == PullMode.replace) await _wipe();
      for (final table in AppDatabase.syncTables.keys) {
        final rows = downloaded[table] ?? const <Map<String, Object?>>[];
        total += rows.length;
        for (final r in rows) {
          try {
            // Savepoint: si la fila no entra, se deshace solo ella.
            final changed = await _db.transaction(() => _applyRow(table, r, force: mode == PullMode.join && table == 'settings'));
            if (changed) applied++;
          } on Exception {
            skipped++;
          }
        }
        if (!saveCursors) continue;
        DateTime? max;
        for (final r in rows) {
          final at = DateTime.parse(r['server_updated_at']! as String);
          if (max == null || at.isAfter(max)) max = at;
        }
        await _db.writeSyncCursor(table, max?.toUtc().toIso8601String() ?? cursors[table] ?? '');
      }
    });
    return PullResult(downloaded: total, applied: applied, skipped: skipped);
  }

  /// Una fila remota R contra la local L y la lápida local T. Gana el
  /// updated_at mayor; en empate, el servidor (su versión es la que quedó).
  Future<bool> _applyRow(String table, Map<String, Object?> r, {required bool force}) async {
    final key = AppDatabase.syncTables[table]!;
    final columns = {for (final c in _db.syncTable(table).$columns) c.name};
    final values = <String, Object?>{
      for (final e in r.entries)
        if (columns.contains(e.key) && e.key != 'synced_at') e.key: e.value is bool ? ((e.value! as bool) ? 1 : 0) : e.value,
      if (table == 'settings') 'id': 1, // en el servidor la clave es user_id
    };
    final id = values[key]!;
    final ru = (r['updated_at']! as num).toInt();
    final dead = r['deleted_at'] != null;
    if (dead && _catalogs.contains(table)) return false; // se archivan, nunca se borran

    final local = await _db
        .customSelect('SELECT updated_at FROM $table WHERE $key = ?', variables: [Variable(id)])
        .getSingleOrNull();
    if (local != null) {
      if (!force && ru < local.read<int>('updated_at')) return false; // L más nueva: la sube el push
      dead ? await _delete(table, key, id) : await _upsert(table, key, values, ru);
      return true;
    }
    final tomb = await _db
        .customSelect('SELECT deleted_at FROM tombstones WHERE entity = ? AND row_id = ?',
            variables: [Variable(table), Variable('$id')])
        .getSingleOrNull();
    if (tomb != null) {
      if (ru < tomb.read<int>('deleted_at')) return false; // borrado local más nuevo: lo sube el push
      await _db.customUpdate('DELETE FROM tombstones WHERE entity = ? AND row_id = ?',
          variables: [Variable(table), Variable('$id')], updates: {_db.tombstones}, updateKind: UpdateKind.delete);
      if (!dead) await _upsert(table, key, values, ru);
      return true;
    }
    if (dead) return false; // nunca estuvo en este teléfono
    await _upsert(table, key, values, ru);
    return true;
  }

  /// Inserta o reemplaza con los valores del servidor: updated_at el remoto
  /// (no [AppDatabase.bumped]) y synced_at = ese mismo, o sea, no pendiente.
  Future<void> _upsert(String table, String key, Map<String, Object?> values, int ru) async {
    if (_catalogs.contains(table) && values['name'] is String) {
      await _freeName(table, values['name']! as String, values[key]! as String);
    }
    final all = {...values, 'synced_at': ru};
    final names = all.keys.toList();
    await _db.customInsert(
      'INSERT INTO $table (${names.join(', ')}) VALUES (${List.filled(names.length, '?').join(', ')}) '
      'ON CONFLICT($key) DO UPDATE SET ${[for (final n in names) if (n != key) '$n = excluded.$n'].join(', ')}',
      variables: [for (final n in names) all[n] == null ? const Variable<Object>(null) : Variable<Object>(all[n])],
      updates: {_db.syncTable(table)},
    );
  }

  /// name es UNIQUE en el teléfono (no en el servidor). Si otra fila local ya
  /// usa [name], esa fila pasa a "name (n)" (el primer n libre) y queda pendiente: los dos
  /// teléfonos terminan con los dos nombres y no se pierde nada.
  // ponytail: dos nombres intercambiados en una misma bajada dejan un "(2)";
  // se arregla a mano renombrando, no vale la pena un algoritmo de swaps.
  Future<void> _freeName(String table, String name, String id) async {
    final clash = await _db
        .customSelect('SELECT id FROM $table WHERE name = ? AND id <> ?', variables: [Variable(name), Variable(id)])
        .getSingleOrNull();
    if (clash == null) return;
    final base = name.replaceFirst(RegExp(r' \(\d+\)$'), '');
    for (var n = 2;; n++) {
      final candidate = '$base ($n)';
      final used = await _db.customSelect('SELECT 1 FROM $table WHERE name = ?', variables: [Variable(candidate)]).get();
      if (used.isEmpty) return _db.renameForSync(table, clash.read<String>('id'), candidate);
    }
  }

  Future<void> _delete(String table, String key, Object id) => _db.customUpdate('DELETE FROM $table WHERE $key = ?',
      variables: [Variable<Object>(id)], updates: {_db.syncTable(table)}, updateKind: UpdateKind.delete);

  /// "Usar solo lo de la nube": hijos antes que padres por las FK.
  Future<void> _wipe() async {
    for (final t in ['transfers', 'budgets', 'entries', 'settings', 'accounts', 'categories', 'sources']) {
      await _db.customUpdate('DELETE FROM $t', updates: {_db.syncTable(t)}, updateKind: UpdateKind.delete);
    }
    await _db.customUpdate('DELETE FROM tombstones', updates: {_db.tombstones}, updateKind: UpdateKind.delete);
    await _db.customUpdate('DELETE FROM sync_cursors', updates: {_db.syncCursors}, updateKind: UpdateKind.delete);
  }
}
