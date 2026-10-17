import 'dart:async';
import 'dart:io' show SocketException;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Versión del consentimiento de la IA. Si cambia lo que se envía, sube y se
/// vuelve a preguntar. La Edge Function `ai-proxy` exige la misma (I5).
const aiConsentVersion = 1;

/// Consultas por día y usuario; la función manda (AI_DAILY_LIMIT).
const aiDailyLimit = 10;

/// Las 6 preguntas de v1 y la libre (5C-Chat, C1-A), con el id que entiende `ai-proxy`.
enum AiQuestion {
  cut('cut'),
  canSpend('can_spend'),
  whatIf('what_if'),
  breakEven('break_even'),
  save('save'),
  payFirst('pay_first'),
  installment('can_afford_installment'),
  free('free');

  const AiQuestion(this.wire);
  final String wire;
}

enum AiError { session, limit, offline, unavailable, unverified }

const aiErrorTexts = {
  AiError.session: 'Tu sesión venció. Vuelve a entrar.',
  AiError.limit: 'Llegaste al límite de hoy. Vuelve mañana.',
  AiError.offline: 'No hay conexión. La IA necesita internet.',
  AiError.unavailable: 'La IA no respondió. Intenta de nuevo en un rato.',
  AiError.unverified: 'No pude responder con tus números. Intenta de nuevo.',
};

/// Código de la función → error. null = no llegó (sin red).
AiError aiErrorFor(int? status) => switch (status) {
      null => AiError.offline,
      401 => AiError.session,
      429 => AiError.limit,
      422 => AiError.unverified,
      _ => AiError.unavailable,
    };

sealed class AiResult {
  const AiResult();
}

class AiAnswer extends AiResult {
  const AiAnswer(this.text, this.left);
  final String text;

  /// Consultas que quedan hoy (la función ya contó esta).
  final int left;
}

class AiFailure extends AiResult {
  const AiFailure(this.error);
  final AiError error;
}

/// Lo único que sale del teléfono: la pregunta, los hechos ya calculados, lo
/// que escribió el usuario y la versión del consentimiento. Nada de correo ni ids.
Map<String, Object?> aiRequestBody(AiQuestion q, Map<String, Object?> facts,
        {int? amountCents, String? item, String? text}) =>
    {
      'question': q.wire,
      'facts': facts,
      if (amountCents != null || item != null || text != null)
        'input': {'amountCents': ?amountCents, 'item': ?item, 'text': ?text},
      'consentVersion': aiConsentVersion,
    };

/// Máximo de la pregunta libre; la función rechaza más.
const aiFreeTextMax = 200;

abstract interface class AiClient {
  Future<AiResult> ask(AiQuestion q, Map<String, Object?> facts, {int? amountCents, String? item, String? text});

  /// Consultas de hoy (día de Lima). Lanza si no hay sesión o red.
  Future<int> usedToday();
}

class SupabaseAiClient implements AiClient {
  SupabaseAiClient(this._client);
  final SupabaseClient _client;

  /// La función corta a los 15 s; esto cubre la red de ida y vuelta.
  static const _timeout = Duration(seconds: 20);

  @override
  Future<AiResult> ask(AiQuestion q, Map<String, Object?> facts,
      {int? amountCents, String? item, String? text}) async {
    try {
      final res = await _client.functions
          .invoke('ai-proxy', body: aiRequestBody(q, facts, amountCents: amountCents, item: item, text: text))
          .timeout(_timeout);
      final data = res.data as Map<String, dynamic>;
      return AiAnswer(data['text'] as String, (data['left'] as num).toInt());
    } on FunctionException catch (e) {
      return AiFailure(aiErrorFor(e.status));
    } on TimeoutException {
      return const AiFailure(AiError.unavailable);
    } on SocketException {
      return const AiFailure(AiError.offline);
    } catch (_) {
      return const AiFailure(AiError.offline);
    }
  }

  @override
  Future<int> usedToday() async => ((await _client.rpc('ai_usage_today')) as num).toInt();
}

/// Para tests y vistas previas: no sale a la red.
class FakeAiClient implements AiClient {
  int used = 0;
  int usedTodayCalls = 0;
  AiResult next = const AiAnswer('Te quedan S/ 850.00.', 9);

  /// Si está, la respuesta espera a que se complete (para ver el estado "esperando").
  Future<void>? gate;
  final sent = <Map<String, Object?>>[];

  @override
  Future<AiResult> ask(AiQuestion q, Map<String, Object?> facts,
      {int? amountCents, String? item, String? text}) async {
    sent.add(aiRequestBody(q, facts, amountCents: amountCents, item: item, text: text));
    if (gate case final g?) await g;
    return next;
  }

  @override
  Future<int> usedToday() async {
    usedTodayCalls++;
    return used;
  }
}

/// main.dart lo reemplaza por [SupabaseAiClient].
final aiClientProvider = Provider<AiClient>((_) => FakeAiClient());
