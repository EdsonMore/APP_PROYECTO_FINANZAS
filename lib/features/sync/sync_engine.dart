import 'dart:async';

import '../../data/database.dart';
import 'auth_gateway.dart';
import 'pull.dart';
import 'push.dart';
import 'remote.dart';
import 'status.dart';

/// Coordina la bajada y la subida (SPEC §Sync, Fase 3C). Todo pasa por un
/// solo candado: nunca hay dos operaciones de sync a la vez. Primero pull y
/// después push: si el servidor tiene algo más nuevo, el pull lo aplica y el
/// push no sube una versión perdedora.
class SyncEngine {
  SyncEngine(this._db, SyncRemote remote, this._auth, {Pusher? pusher, DateTime Function()? clock})
      : _puller = Puller(_db, remote),
        _pusher = pusher ?? Pusher(_db, remote),
        _clock = clock ?? DateTime.now {
    _email = _auth.currentEmail;
    _authSub = _auth.emailChanges.listen(_onSession);
  }

  final AppDatabase _db;
  final AuthGateway _auth;
  final Puller _puller;
  final Pusher _pusher;
  final DateTime Function() _clock;
  late final StreamSubscription<String?> _authSub;
  String? _email;

  final _changes = StreamController<SyncStatus>.broadcast();
  SyncStatus _status = const SyncStatus(SyncState.off);
  SyncStatus get status => _status;
  Stream<SyncStatus> get statusChanges => _changes.stream;

  DateTime? get _last => _status.lastSyncAt;

  /// La sesión se cerró por sesión vencida (no por el usuario).
  bool _expired = false;

  Future<void> _tail = Future.value();
  Future<SyncStatus>? _queued;

  /// Termina cuando no queda nada en el candado (para tests y para cerrar).
  Future<void> get idle => _tail;

  Future<T> _serial<T>(Future<T> Function() f) {
    final r = _tail.then((_) => f());
    _tail = r.then((_) {}, onError: (_) {});
    return r;
  }

  SyncStatus _emit(SyncStatus s) {
    _status = s;
    if (!_changes.isClosed) _changes.add(s);
    return s;
  }

  /// La única puerta de entrada. Si ya hay uno esperando en el candado,
  /// devuelve ese: como máximo uno corriendo y uno esperando.
  Future<SyncStatus> sync() {
    if (_auth.currentEmail == null) {
      return Future.value(_status.state == SyncState.needsLogin ? _status : _emit(const SyncStatus(SyncState.off)));
    }
    return _queued ??= _serial(() {
      _queued = null;
      return _guard(_syncOnce);
    });
  }

  /// D5 "Unir": los dos conjuntos; los ajustes de la nube ganan.
  Future<SyncStatus> join() => _serial(() => _guard(() async => _finish(await _puller.pull(mode: PullMode.join))));

  /// D5 "Usar solo los de la nube": lo del teléfono se reemplaza.
  Future<SyncStatus> useCloud() =>
      _serial(() => _guard(() async => _finish(await _puller.pull(mode: PullMode.replace))));

  /// Al ir al background: solo subir, rápido. Nunca en el primer contacto
  /// (antes de D5 no se sube nada). Los errores se ignoran: queda pendiente.
  Future<void> pushOnly() => _serial(() async {
        if (_auth.currentEmail == null || _status.state == SyncState.needsChoice || await _db.neverSynced()) return;
        try {
          await _pusher.push();
        } on Exception {
          // Pendiente para el próximo sync.
        }
      });

  Future<SyncStatus> _syncOnce() async {
    // Esperando la elección de D5: nada de red hasta que elija (en memoria:
    // si cierra la app, al volver se pregunta de nuevo).
    if (_status.state == SyncState.needsChoice) return _status;
    if (await _db.neverSynced()) {
      final cloud = await _puller.download(full: true);
      final empty = cloud.values.every((rows) => rows.isEmpty);
      if (empty) {
        // Nube vacía: apply solo guarda los cursores; el push de siempre sube
        // todo, como "Crear cuenta".
        return _finish(await _puller.apply(cloud));
      }
      if (await _db.hasUserData()) return _emit(SyncStatus(SyncState.needsChoice, lastSyncAt: _last));
      return _finish(await _puller.apply(cloud, mode: PullMode.replace)); // solo la semilla: la nube, sin preguntar
    }
    return _finish(await _puller.pull());
  }

  /// Sube (push de la 3B, sin cambios) y resume el estado.
  Future<SyncStatus> _finish(PullResult pulled) async {
    final pushed = await _pusher.push();
    if (pushed.stoppedByNetwork) return _emit(SyncStatus(SyncState.offline, lastSyncAt: _last));
    // Lo que el servidor descartó (versión más nueva allá): traer la ganadora.
    final fixed = pushed.discarded.isEmpty ? const PullResult() : await _puller.reconcile(pushed.discarded);
    final issues = pulled.skipped + fixed.skipped + pushed.failed;
    return _emit(SyncStatus(issues > 0 ? SyncState.issues : SyncState.ok, lastSyncAt: _clock(), issues: issues));
  }

  /// Errores de red y de sesión, con un solo reintento tras refrescar (D7).
  Future<SyncStatus> _guard(Future<SyncStatus> Function() body, {bool authRetried = false}) async {
    if (_auth.currentEmail == null) return _status; // se cerró la sesión mientras esperaba
    if (_status.state != SyncState.needsChoice) _emit(SyncStatus(SyncState.syncing, lastSyncAt: _last));
    try {
      return await body();
    } on NetworkFailure {
      return _emit(SyncStatus(SyncState.offline, lastSyncAt: _last));
    } on AuthExpiredFailure {
      if (!authRetried) {
        switch (await _auth.refreshSession()) {
          case RefreshOutcome.ok:
            return _guard(body, authRetried: true);
          case RefreshOutcome.offline:
            return _emit(SyncStatus(SyncState.offline, lastSyncAt: _last));
          case RefreshOutcome.invalid:
            break;
        }
      }
      _expired = true;
      await _auth.signOutLocal(); // los datos y lo pendiente se quedan en el teléfono
      return _emit(const SyncStatus(SyncState.needsLogin));
    }
  }

  /// Al cerrarse la sesión por cualquier causa (el usuario, sesión vencida,
  /// cuenta borrada): nada queda "sincronizado" con esa cuenta.
  void _onSession(String? email) {
    final wasSignedIn = _email != null;
    _email = email;
    if (email != null) {
      _expired = false;
      if (_status.state == SyncState.needsLogin) _emit(const SyncStatus(SyncState.off));
      return;
    }
    if (!wasSignedIn) return;
    final state = _expired ? SyncState.needsLogin : SyncState.off;
    _expired = false;
    _serial(() async {
      await _db.detachSync();
      _emit(SyncStatus(state));
    });
  }

  Future<void> dispose() async {
    await _authSub.cancel();
    await idle;
    await _changes.close();
  }
}
