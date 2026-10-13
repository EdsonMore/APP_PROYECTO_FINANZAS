import '../../data/database.dart';
import 'remote.dart';

/// Filas por petición. Si el lote falla por datos se reintenta fila por fila.
const pushBatchSize = 200;

class PushError {
  const PushError(this.table, this.id, this.code, this.message);
  final String table;
  final String id;
  final String code;
  final String message;
}

/// Resumen de un push(). Lo que no se subió queda pendiente para el siguiente.
class PushResult {
  const PushResult({this.pushed = 0, this.failed = 0, this.errors = const [], this.stoppedByNetwork = false});

  /// Filas y lápidas confirmadas por el servidor.
  final int pushed;

  /// Filas que el servidor rechazó por datos (siguen pendientes).
  final int failed;
  final List<PushError> errors;

  /// Se cortó por red: lo que faltaba ni se intentó.
  final bool stoppedByNetwork;

  PushResult _add({int pushed = 0, List<PushError> errors = const [], bool stopped = false}) => PushResult(
        pushed: this.pushed + pushed,
        failed: failed + errors.length,
        errors: [...this.errors, ...errors],
        stoppedByNetwork: stoppedByNetwork || stopped,
      );
}

/// Sube lo pendiente (SPEC §Sync). Resiliente: una fila mala no frena a las
/// demás; sin red se detiene. Nunca corren dos a la vez. Lo reutiliza la 3C.
class Pusher {
  Pusher(this._db, this._remote);
  final AppDatabase _db;
  final SyncRemote _remote;
  Future<PushResult>? _running;

  Future<PushResult> push() {
    final running = _running;
    if (running != null) return running;
    final f = _push().whenComplete(() => _running = null);
    _running = f;
    return f;
  }

  Future<PushResult> _push() async {
    var result = const PushResult();

    // 1. Filas, tabla por tabla, en el orden de las FK del servidor.
    for (final table in AppDatabase.syncTables.keys) {
      final key = AppDatabase.syncTables[table]!;
      final pending = await _db.pendingRows(table);
      for (var i = 0; i < pending.length; i += pushBatchSize) {
        final batch = pending.sublist(i, i + pushBatchSize > pending.length ? pending.length : i + pushBatchSize);
        final out = await _sendBatch(table, key, batch);
        await _db.markSynced(table, [for (final r in out.confirmed) (r[key]!, r['updated_at']! as int)]);
        result = result._add(pushed: out.confirmed.length, errors: out.errors, stopped: out.network);
        if (out.network) return result;
      }
    }

    // 2. Lápidas: borrados de filas que ya estaban en el servidor.
    for (final t in await _db.pendingTombstones()) {
      try {
        await _remote.markDeleted(t.entity, t.recordId, t.deletedAt);
        await _db.dropTombstone(t);
        result = result._add(pushed: 1);
      } on NetworkFailure {
        return result._add(stopped: true);
      } on DataFailure catch (e) {
        result = result._add(errors: [PushError(t.entity, t.recordId, e.code, e.message)]);
      }
    }
    return result;
  }

  /// Un lote entero; si falla por datos, fila por fila para aislar las malas.
  Future<_BatchOutcome> _sendBatch(String table, String key, List<Map<String, Object?>> rows) async {
    try {
      await _remote.upsert(table, [for (final r in rows) toRemote(table, r)]);
      return _BatchOutcome(rows, const [], network: false);
    } on NetworkFailure {
      return const _BatchOutcome([], [], network: true);
    } on DataFailure {
      final confirmed = <Map<String, Object?>>[];
      final errors = <PushError>[];
      for (final r in rows) {
        try {
          await _remote.upsert(table, [toRemote(table, r)]);
          confirmed.add(r);
        } on NetworkFailure {
          return _BatchOutcome(confirmed, errors, network: true);
        } on DataFailure catch (e) {
          errors.add(PushError(table, '${r[key]}', e.code, e.message));
        }
      }
      return _BatchOutcome(confirmed, errors, network: false);
    }
  }
}

class _BatchOutcome {
  const _BatchOutcome(this.confirmed, this.errors, {required this.network});
  final List<Map<String, Object?>> confirmed;
  final List<PushError> errors;
  final bool network;
}

const _boolColumns = {'archived', 'is_default', 'onboarding_done'};

/// Fila de SQLite → fila del servidor: sin synced_at (nunca sale del
/// teléfono) ni user_id (lo pone el servidor con auth.uid()); booleanos como
/// bool; settings sin su id local (en el servidor la clave es user_id) y sin
/// deleted_at; las demás con deleted_at null para "revivir" una fila borrada.
Map<String, Object?> toRemote(String table, Map<String, Object?> row) => {
      for (final e in row.entries)
        if (e.key != 'synced_at' && !(table == 'settings' && e.key == 'id'))
          e.key: _boolColumns.contains(e.key) && e.value is int ? e.value == 1 : e.value,
      if (table != 'settings') 'deleted_at': null,
    };
