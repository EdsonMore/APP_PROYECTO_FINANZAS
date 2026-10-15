import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../sync/providers.dart' show accountEmailProvider;
import 'ai_client.dart';

typedef AiUsage = ({int today, int left});

/// Contador de consultas de hoy. Se lee al abrir el chat (autoDispose: cada
/// vez que se vuelve a mirar) y, tras cada consulta, se actualiza con el
/// "left" de la respuesta sin otra llamada. Sin cuenta o sin red: null.
class AiUsageNotifier extends AutoDisposeAsyncNotifier<AiUsage?> {
  @override
  Future<AiUsage?> build() async {
    final email = await ref.watch(accountEmailProvider.future);
    if (email == null) return null;
    try {
      final used = await ref.read(aiClientProvider).usedToday();
      return (today: used, left: math.max(0, aiDailyLimit - used));
    } catch (_) {
      return null;
    }
  }

  void applyLeft(int left) => state = AsyncData((today: aiDailyLimit - left, left: left));
}

final aiUsageProvider = AsyncNotifierProvider.autoDispose<AiUsageNotifier, AiUsage?>(AiUsageNotifier.new);

String aiUsageText(AiUsage u) => switch (u.left) {
      0 => 'Llegaste al límite de hoy. Vuelve mañana.',
      1 => 'Te queda 1 consulta hoy',
      final n => 'Te quedan $n consultas hoy',
    };
