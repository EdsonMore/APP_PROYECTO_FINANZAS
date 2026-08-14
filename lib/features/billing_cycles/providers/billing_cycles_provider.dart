import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saldo_claro/features/billing_cycles/data/billing_cycle_repository.dart';
import 'package:saldo_claro/features/billing_cycles/models/billing_cycle_model.dart';
import 'package:saldo_claro/features/billing_cycles/services/billing_auto_match_service.dart';
import 'package:saldo_claro/features/billing_cycles/services/billing_notification_scheduler.dart';

/// Repositorio de ciclos de facturación (instancia única compartida).
final billingCycleRepositoryProvider = Provider<BillingCycleRepository>((ref) {
  return BillingCycleRepository();
});

/// Programador de alarmas locales de los ciclos de facturación.
final billingNotificationSchedulerProvider =
    Provider<BillingNotificationScheduler>((ref) {
  return BillingNotificationScheduler();
});

/// Servicio de Auto-Match: detecta pagos de servicios desde notificaciones.
final billingAutoMatchServiceProvider =
    Provider<BillingAutoMatchService>((ref) {
  return BillingAutoMatchService(
    repository: ref.watch(billingCycleRepositoryProvider),
    scheduler: ref.watch(billingNotificationSchedulerProvider),
  );
});

/// Lista de ciclos de facturación del usuario (ordenados por vencimiento).
final billingCyclesProvider = FutureProvider<List<BillingCycle>>((ref) {
  return ref.watch(billingCycleRepositoryProvider).fetchAll();
});

/// Invalida los providers de ciclos para forzar una recarga.
void refreshBillingCycles(WidgetRef ref) {
  ref.invalidate(billingCyclesProvider);
}
