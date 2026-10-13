import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'auth_gateway.dart';
import 'fake_auth_gateway.dart';
import 'push.dart';
import 'remote.dart';
import 'scheduler.dart';
import 'status.dart';
import 'sync_engine.dart';

/// main.dart los reemplaza por SupabaseAuthGateway / SupabaseSyncRemote. El
/// valor por defecto (en memoria, sin red) es el de los tests.
final authGatewayProvider = Provider<AuthGateway>((_) => FakeAuthGateway());
final syncRemoteProvider = Provider<SyncRemote>((_) => FakeSyncRemote());

final pusherProvider = Provider<Pusher>((ref) => Pusher(ref.watch(databaseProvider), ref.watch(syncRemoteProvider)));

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine(ref.watch(databaseProvider), ref.watch(syncRemoteProvider), ref.watch(authGatewayProvider),
      pusher: ref.watch(pusherProvider));
  ref.onDispose(engine.dispose);
  return engine;
});

/// Estado para la pantalla de sync (y el ícono de la 3D).
final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  final engine = ref.watch(syncEngineProvider);
  yield engine.status;
  yield* engine.statusChanges;
});

/// Arranca al leerse (lo lee SyncLifecycle, arriba de la app).
final syncSchedulerProvider = Provider<SyncScheduler>((ref) {
  final engine = ref.watch(syncEngineProvider);
  final db = ref.watch(databaseProvider);
  final auth = ref.watch(authGatewayProvider);
  final scheduler = SyncScheduler(
    sync: engine.sync,
    pushOnly: engine.pushOnly,
    hasPending: db.hasPending,
    signedIn: () => auth.currentEmail != null,
    writes: db.tableUpdates(),
    sessions: auth.emailChanges.map((email) => email != null),
  )..start();
  ref.onDispose(scheduler.dispose);
  return scheduler;
});

/// Correo de la sesión; null = sin cuenta.
final accountEmailProvider = StreamProvider<String?>((ref) async* {
  final gateway = ref.watch(authGatewayProvider);
  yield gateway.currentEmail;
  yield* gateway.emailChanges;
});
