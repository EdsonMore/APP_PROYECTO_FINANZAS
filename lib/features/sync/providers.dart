import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'auth_gateway.dart';
import 'fake_auth_gateway.dart';
import 'push.dart';
import 'remote.dart';

/// main.dart los reemplaza por SupabaseAuthGateway / SupabaseSyncRemote. El
/// valor por defecto (en memoria, sin red) es el de los tests.
final authGatewayProvider = Provider<AuthGateway>((_) => FakeAuthGateway());
final syncRemoteProvider = Provider<SyncRemote>((_) => FakeSyncRemote());

final pusherProvider = Provider<Pusher>((ref) => Pusher(ref.watch(databaseProvider), ref.watch(syncRemoteProvider)));

/// Correo de la sesión; null = sin cuenta.
final accountEmailProvider = StreamProvider<String?>((ref) async* {
  final gateway = ref.watch(authGatewayProvider);
  yield gateway.currentEmail;
  yield* gateway.emailChanges;
});
