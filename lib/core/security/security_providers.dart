import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'biometric_service.dart';
import 'lock_store.dart';

/// Servicio de biometría compartido en toda la app.
final biometricServiceProvider = Provider<BiometricService>((ref) {
  return BiometricService();
});

/// Almacén de preferencias de seguridad/privacidad (SharedPreferences).
final lockStoreProvider = Provider<LockStore>((ref) {
  return LockStore.instance;
});

/// Estado global del "modo incógnito" (ocultar saldos).
///
/// Se inicializa desde disco y cada cambio se persiste con [LockStore] para
/// mantener el estado al reiniciar la app.
class BalanceHiddenController extends StateNotifier<bool> {
  BalanceHiddenController() : super(false) {
    _hydrate();
  }

  Future<void> _hydrate() async {
    state = await LockStore.instance.isBalanceHidden();
  }

  Future<void> setHidden(bool value) async {
    if (state == value) return;
    state = value;
    await LockStore.instance.setBalanceHidden(value);
  }
}

final balanceHiddenProvider =
    StateNotifierProvider<BalanceHiddenController, bool>((ref) {
  return BalanceHiddenController();
});