import 'dart:developer' as developer;

import 'package:saldo_claro/core/notification/local_notification_service.dart';
import 'package:saldo_claro/features/billing_cycles/data/billing_cycle_repository.dart';
import 'package:saldo_claro/features/billing_cycles/models/billing_cycle_model.dart';
import 'package:saldo_claro/features/billing_cycles/services/billing_notification_scheduler.dart';

/// Detecta automáticamente el pago de un servicio a partir de una
/// notificación capturada (Auto-Match).
///
/// Cuando una transacción se registra con éxito en [NotificationCaptureService],
/// se analiza el texto capturado contra los ciclos activos en estado 'pending'.
/// Si el texto coincide con el título o alguna keyword del ciclo (p. ej.
/// "Pago a ENOSA S/ 85.00" y la keyword 'enosa'):
///
/// 1. Se marca el recibo como pagado y se recalcula la `due_date` sumando el
///    intervalo según su frecuencia (mensual/bimestral/anual).
/// 2. El nuevo ciclo queda en estado 'pending'.
/// 3. Se reprograman las alarmas locales para el siguiente ciclo.
/// 4. Se lanza una notificación local inmediata de celebración.
class BillingAutoMatchService {
  BillingAutoMatchService({
    BillingCycleRepository? repository,
    BillingNotificationScheduler? scheduler,
    LocalNotificationService? notifications,
  })  : _repository = repository ?? BillingCycleRepository(),
        _scheduler = scheduler ?? BillingNotificationScheduler(),
        _notifications = notifications ?? LocalNotificationService.instance;

  final BillingCycleRepository _repository;
  final BillingNotificationScheduler _scheduler;
  final LocalNotificationService _notifications;

  /// Analiza el texto capturado contra los ciclos activos pendientes.
  ///
  /// Devuelve `true` si detectó y resolvió el pago de algún servicio.
  Future<bool> tryAutoMatch({
    required String title,
    required String text,
  }) async {
    try {
      final combined = '${title.trim()} ${text.trim()}'.toLowerCase();
      if (combined.trim().isEmpty) return false;

      final cycles = await _repository.fetchPendingActive();
      if (cycles.isEmpty) return false;

      for (final cycle in cycles) {
        if (!_matches(cycle, combined)) continue;

        developer.log(
          '[SaldoClaro] 🔗 Auto-Match: "${cycle.title}" coincide con la '
          'notificación capturada.',
          name: 'SaldoClaro.Billing',
        );
        await _settle(cycle);
        return true;
      }
      return false;
    } catch (e, st) {
      developer.log(
        '[SaldoClaro] ❌ Error en Auto-Match de ciclos: $e',
        name: 'SaldoClaro.Billing',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  }

  /// Verifica si el texto capturado coincide con el título o las keywords.
  bool _matches(BillingCycle cycle, String normalizedText) {
    final title = cycle.title.trim().toLowerCase();
    if (title.isNotEmpty && normalizedText.contains(title)) return true;

    for (final keyword in cycle.keywords) {
      final kw = keyword.trim().toLowerCase();
      if (kw.isNotEmpty && normalizedText.contains(kw)) return true;
    }
    return false;
  }

  /// Resuelve el ciclo: cancela alarmas viejas, avanza la fecha, reprograma
  /// las alarmas del nuevo ciclo y notifica al usuario.
  Future<void> _settle(BillingCycle cycle) async {
    await _scheduler.cancelForCycle(cycle.id);

    final next = await _repository.settleAndAdvance(cycle.id);
    if (next == null) return;

    await _scheduler.scheduleForCycle(next);
    await _notifications.showBillingPaidNotification(
      serviceTitle: cycle.title,
      nextDueDate: next.dueDate,
    );
  }
}
