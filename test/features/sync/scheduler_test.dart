import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/features/sync/scheduler.dart';

/// Cuándo se sincroniza (Fase 3C, D1/D2/D11), con el tiempo simulado.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int syncs, pushOnlys;
  late bool signedIn, pending;
  late StreamController<void> writes;
  late StreamController<bool> sessions;

  SyncScheduler scheduler() => SyncScheduler(
        sync: () async => syncs++,
        pushOnly: () async => pushOnlys++,
        hasPending: () async => pending,
        signedIn: () => signedIn,
        writes: writes.stream,
        sessions: sessions.stream,
      );

  /// Corre [body] con el tiempo simulado y un scheduler ya arrancado.
  void run(void Function(FakeAsync time, SyncScheduler s) body) => fakeAsync((time) {
        writes = StreamController<void>.broadcast();
        sessions = StreamController<bool>.broadcast();
        final s = scheduler()..start();
        time.flushMicrotasks();
        body(time, s);
        s.dispose();
        time.flushMicrotasks();
        expect(time.pendingTimers, isEmpty, reason: 'dispose cancela todo');
      });

  setUp(() {
    syncs = 0;
    pushOnlys = 0;
    signedIn = true;
    pending = true;
  });

  test('al abrir: un sync si hay sesión', () => run((time, s) => expect(syncs, 1)));

  test('al abrir sin sesión: ninguno, y sin timers', () {
    signedIn = false;
    run((time, s) {
      expect(syncs, 0);
      time.elapse(const Duration(minutes: 5));
      writes.add(null);
      time.elapse(const Duration(seconds: 10));
      expect(syncs, 0);
      expect(time.pendingTimers, isEmpty);
    });
  });

  test('debounce: 5 escrituras en 2 s → un solo sync, 3 s después de la última', () => run((time, s) {
        syncs = 0;
        for (var i = 0; i < 5; i++) {
          writes.add(null);
          time.elapse(const Duration(milliseconds: 500));
        }
        time.elapse(const Duration(milliseconds: 2400));
        expect(syncs, 0, reason: 'todavía no pasan 3 s desde la última');
        time.elapse(const Duration(milliseconds: 200));
        expect(syncs, 1);
      }));

  test('V3: una escritura sin pendientes (como las del propio pull) no dispara nada', () => run((time, s) {
        syncs = 0;
        pending = false;
        writes.add(null);
        time.elapse(const Duration(seconds: 10));
        expect(syncs, 0, reason: 'sin bucle pull → escritura → pull');
      }));

  test('polling: cada 60 s con la app abierta', () => run((time, s) {
        syncs = 0;
        time.elapse(const Duration(seconds: 59));
        expect(syncs, 0);
        time.elapse(const Duration(seconds: 1));
        expect(syncs, 1);
        time.elapse(const Duration(seconds: 120));
        expect(syncs, 3);
      }));

  test('en background el polling se detiene; al volver, sync inmediato y vuelve el polling', () => run((time, s) {
        syncs = 0;
        s.didChangeAppLifecycleState(AppLifecycleState.hidden);
        s.didChangeAppLifecycleState(AppLifecycleState.paused);
        time.elapse(const Duration(minutes: 10));
        writes.add(null);
        time.elapse(const Duration(seconds: 10));
        expect(syncs, 0);
        s.didChangeAppLifecycleState(AppLifecycleState.resumed);
        time.flushMicrotasks();
        expect(syncs, 1);
        time.elapse(const Duration(seconds: 60));
        expect(syncs, 2);
      }));

  test('ir al background: pushOnly una vez, solo si hay pendientes', () => run((time, s) {
        s.didChangeAppLifecycleState(AppLifecycleState.hidden);
        s.didChangeAppLifecycleState(AppLifecycleState.paused);
        time.flushMicrotasks();
        expect(pushOnlys, 1);
        s.didChangeAppLifecycleState(AppLifecycleState.resumed);
        pending = false;
        s.didChangeAppLifecycleState(AppLifecycleState.paused);
        time.flushMicrotasks();
        expect(pushOnlys, 1);
      }));

  test('botón manual: sync inmediato y cancela el debounce que esperaba', () => run((time, s) {
        syncs = 0;
        writes.add(null);
        time.elapse(const Duration(seconds: 1));
        s.syncNow();
        time.flushMicrotasks();
        expect(syncs, 1);
        time.elapse(const Duration(seconds: 5));
        expect(syncs, 1, reason: 'el debounce ya no dispara');
      }));

  test('al cerrar sesión se cancelan los timers; al entrar, sync inmediato', () => run((time, s) {
        syncs = 0;
        signedIn = false;
        sessions.add(false);
        time.flushMicrotasks();
        expect(time.pendingTimers, isEmpty);
        time.elapse(const Duration(minutes: 5));
        expect(syncs, 0);
        signedIn = true;
        sessions.add(true);
        time.flushMicrotasks();
        expect(syncs, 1);
      }));

  test('nunca dos sync() a la vez lo garantiza el motor; el scheduler no espera: dispara y sigue', () => run((time, s) {
        // El candado está en SyncEngine (engine_test, "candado"). Aquí solo se
        // comprueba que varios disparadores juntos no rompen nada.
        syncs = 0;
        s.syncNow();
        s.syncNow();
        time.flushMicrotasks();
        expect(syncs, 2, reason: 'el motor los colapsa en uno corriendo + uno esperando');
      }));
}
