import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../gemini/gemini_client.dart';
import '../groq/groq_client.dart';
import '../network/supabase_client.dart';
import '../notification/notification_listener_channel.dart';
import '../permissions/notification_permission_service.dart';
import '../services/ai_service.dart';

/// Cliente de Supabase compartido en toda la app.
final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService.instance;
});

/// Cliente de Gemini (IA principal). Nota: si no hay clave configurada,
/// `GeminiClient.available` es false y la app degrada sin IA.
final geminiClientProvider = Provider<GeminiClient>((ref) {
  final client = GeminiClient();
  ref.onDispose(client.dispose);
  return client;
});

/// Cliente de Groq (IA de respaldo, gratis y rápida).
final groqClientProvider = Provider<GroqClient>((ref) {
  final client = GroqClient();
  ref.onDispose(client.dispose);
  return client;
});

/// Orquestador de IA con fallback en cascada: Gemini -> Groq -> null.
///
/// Todos los servicios con IA (categorizador, CFO, insights) deben usar este
/// provider, NO los clientes sueltos, para aprovechar el intercalado.
final aiServiceProvider = Provider<AIService>((ref) {
  return AIService(
    primary: ref.watch(geminiClientProvider),
    backup: ref.watch(groqClientProvider),
  );
});

/// Canal nativo de notificaciones (EventChannel).
final notificationListenerChannelProvider = Provider<NotificationListenerChannel>((ref) {
  return NotificationListenerChannel.instance;
});

/// Servicio de verificación de permisos de notificaciones en Android.
final notificationPermissionServiceProvider =
    Provider<NotificationPermissionService>((ref) {
  return NotificationPermissionService.instance;
});
