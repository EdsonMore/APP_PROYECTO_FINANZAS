import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:saldo_claro/core/providers/service_providers.dart';
import 'package:saldo_claro/core/services/smart_categorizer.dart';
import 'package:saldo_claro/features/billing_cycles/providers/billing_cycles_provider.dart';
import 'package:saldo_claro/features/capture/service/notification_capture_service.dart';
import 'package:saldo_claro/features/dashboard/providers/repository_providers.dart';

/// Categorizador "inteligente" (reglas locales + IA en cascada).
final smartCategorizerProvider = Provider<SmartCategorizer>((ref) {
  return SmartCategorizer(ai: ref.watch(aiServiceProvider));
});

/// Servicio de captura automática de notificaciones.
final notificationCaptureServiceProvider = Provider<NotificationCaptureService>((ref) {
  final service = NotificationCaptureService(
    channel: ref.watch(notificationListenerChannelProvider),
    accountRepository: ref.watch(accountRepositoryProvider),
    transactionRepository: ref.watch(transactionRepositoryProvider),
    categoryRepository: ref.watch(categoryRepositoryProvider),
    categorizer: ref.watch(smartCategorizerProvider),
    billingAutoMatch: ref.watch(billingAutoMatchServiceProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});
