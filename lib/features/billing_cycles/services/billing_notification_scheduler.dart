import 'dart:developer' as developer;

import 'package:saldo_claro/core/notification/local_notification_service.dart';
import 'package:saldo_claro/core/utils/formatters.dart';
import 'package:saldo_claro/features/billing_cycles/models/billing_cycle_model.dart';

/// Programa y cancela las alarmas locales de cada ciclo de facturación.
///
/// Para un ciclo en estado `pending` se programan dos alertas:
/// - Alerta informativa: 3 días antes del vencimiento a las 09:00 AM.
/// - Alerta crítica: 1 día antes del vencimiento a las 08:00 AM.
///
/// Si la fecha ya pasó, la alerta se omite. Al pagar, pausar o eliminar el
/// registro se cancelan las notificaciones programadas (IDs derivados del
/// ID del ciclo para que sean estables entre reinicios).
class BillingNotificationScheduler {
  BillingNotificationScheduler({LocalNotificationService? notifications})
      : _notifications = notifications ?? LocalNotificationService.instance;

  final LocalNotificationService _notifications;

  /// Hora de la alerta informativa (3 días antes, 09:00 AM).
  static const int _informativeHour = 9;
  static const int _informativeMinute = 0;

  /// Hora de la alerta crítica (1 día antes, 08:00 AM).
  static const int _criticalHour = 8;
  static const int _criticalMinute = 0;

  /// Programa las alertas de un ciclo (informativas y críticas).
  ///
  /// Solo se programan ciclos activos en estado 'pending'. Las alertas cuya
  /// fecha ya haya pasado se omiten automáticamente.
  Future<void> scheduleForCycle(BillingCycle cycle) async {
    if (!cycle.isActive || cycle.status != BillingStatus.pending) return;

    final dueDate = cycle.dateOnly;
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    // Alerta informativa: 3 días antes del vencimiento a las 09:00.
    final informativeDate = DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day - 3,
      _informativeHour,
      _informativeMinute,
    );
    // Alerta crítica: 1 día antes del vencimiento a las 08:00.
    final criticalDate = DateTime(
      dueDate.year,
      dueDate.month,
      dueDate.day - 1,
      _criticalHour,
      _criticalMinute,
    );

    final informativeId = reminderIdFor(cycle.id, critical: false);
    final criticalId = reminderIdFor(cycle.id, critical: true);

    try {
      if (!informativeDate.isBefore(todayOnly)) {
        await _notifications.scheduleBillingReminder(
          id: informativeId,
          when: informativeDate,
          title: '⏰ Recordatorio: ${cycle.title}',
          body: 'Faltan 3 días para el vencimiento '
              '(${Formatters.currency(cycle.amount)}). '
              'Planifica tu pago a tiempo.',
        );
      }

      if (!criticalDate.isBefore(todayOnly)) {
        await _notifications.scheduleBillingReminder(
          id: criticalId,
          when: criticalDate,
          title: '🚨 ¡Casi se te pasa! ${cycle.title}',
          body: '${cycle.title} vence mañana '
              '(${Formatters.currency(cycle.amount)}). '
              'No esperes a que se corte el servicio.',
        );
      }

      developer.log(
        '[SaldoClaro] 📅 Recordatorios programados id=${cycle.id} '
        'info=$informativeId crit=$criticalId due=${cycle.dueDate}',
        name: 'SaldoClaro.Billing',
      );
    } catch (e) {
      developer.log(
        '[SaldoClaro] ⚠️ Error programando recordatorios id=${cycle.id}: $e',
        name: 'SaldoClaro.Billing',
      );
    }
  }

  /// Cancela las notificaciones programadas asociadas a un ciclo.
  Future<void> cancelForCycle(String cycleId) async {
    try {
      await _notifications.cancelBillingReminder(
        reminderIdFor(cycleId, critical: false),
      );
      await _notifications.cancelBillingReminder(
        reminderIdFor(cycleId, critical: true),
      );
      developer.log(
        '[SaldoClaro] 🗑️ Recordatorios cancelados id=$cycleId',
        name: 'SaldoClaro.Billing',
      );
    } catch (e) {
      developer.log(
        '[SaldoClaro] ⚠️ Error cancelando recordatorios id=$cycleId: $e',
        name: 'SaldoClaro.Billing',
      );
    }
  }

  /// ID estable de notificación para un ciclo (int positivo de 31 bits).
  ///
  /// Se deriva de los primeros 8 hex del UUID (informativa) y de los últimos
  /// 8 hex (crítica), de modo que siempre se cancela la alerta correcta.
  static int reminderIdFor(String cycleId, {required bool critical}) {
    final hex = cycleId.replaceAll('-', '');
    final part = critical
        ? hex.substring(hex.length - 8)
        : hex.substring(0, 8);
    final value = int.tryParse(part, radix: 16) ?? 0;
    return value & 0x7FFFFFFF;
  }
}
