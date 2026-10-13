import 'dart:async';

import 'package:flutter/widgets.dart';

/// D2: espera desde la última escritura (agrupa una racha de cargas).
const syncDebounce = Duration(seconds: 3);

/// D1: polling con la app abierta (sin Realtime).
const syncPoll = Duration(seconds: 60);

/// Cuándo sincronizar (Fase 3C): al abrir, al volver, 3 s después de
/// escribir, cada 60 s en primer plano y con el botón. Al ir al background,
/// solo subir (D11). Sin sesión no hay timers ni red. El candado está en
/// SyncEngine: aquí solo se dispara.
class SyncScheduler with WidgetsBindingObserver {
  SyncScheduler({
    required this.sync,
    required this.pushOnly,
    required this.hasPending,
    required this.signedIn,
    required this.writes,
    required this.sessions,
    this.debounce = syncDebounce,
    this.poll = syncPoll,
  });

  final Future<void> Function() sync;
  final Future<void> Function() pushOnly;
  final Future<bool> Function() hasPending;
  final bool Function() signedIn;
  final Stream<void> writes;
  final Stream<bool> sessions;
  final Duration debounce;
  final Duration poll;

  final _subs = <StreamSubscription<void>>[];
  Timer? _debounceTimer, _pollTimer;
  var _foreground = true;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _subs
      ..add(writes.listen((_) => _onWrite()))
      ..add(sessions.listen((on) => on ? syncNow() : _cancel()));
    syncNow(); // al abrir
  }

  /// Todo disparador pasa por aquí (también el botón manual).
  void syncNow() {
    _cancel();
    if (!signedIn()) return;
    if (_foreground) _pollTimer = Timer(poll, syncNow); // 60 s desde el último sync
    unawaited(sync());
  }

  void _onWrite() {
    if (!signedIn() || !_foreground) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () async {
      // Las escrituras del propio pull no dejan pendientes: sin bucle.
      if (await hasPending()) syncNow();
    });
  }

  void _cancel() {
    _debounceTimer?.cancel();
    _pollTimer?.cancel();
    _debounceTimer = _pollTimer = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foreground = true;
        syncNow();
      case AppLifecycleState.hidden || AppLifecycleState.paused:
        if (!_foreground) return; // hidden y paused llegan juntos: una vez
        _foreground = false;
        _cancel();
        if (signedIn()) unawaited(_pushIfPending());
      case AppLifecycleState.inactive || AppLifecycleState.detached:
        break;
    }
  }

  Future<void> _pushIfPending() async {
    if (await hasPending()) await pushOnly();
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _cancel();
  }
}
