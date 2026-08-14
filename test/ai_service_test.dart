import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:saldo_claro/core/ai/ai_model_client.dart';
import 'package:saldo_claro/core/groq/groq_client.dart';
import 'package:saldo_claro/core/services/ai_service.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/models/transaction_type.dart';
import 'package:saldo_claro/core/services/insights_engine.dart';

/// Cliente de IA falso para probar la lógica de fallback.
class _FakeAiClient implements AiModelClient {
  _FakeAiClient({
    required this.available,
    this.result,
    this.fail = false,
    this.neverCompletes = false,
    this.jsonResult,
  });

  @override
  final bool available;
  String? result;
  bool fail;
  bool neverCompletes;
  Map<String, dynamic>? jsonResult;
  int generateCalls = 0;
  int jsonCalls = 0;

  @override
  String get providerName => 'fake';

  @override
  Future<String?> generate({
    required String prompt,
    bool jsonMode = false,
    double temperature = 0.3,
  }) async {
    generateCalls++;
    if (neverCompletes) {
      await Completer<String>().future;
    }
    if (fail) throw Exception('error simulado');
    return result;
  }

  @override
  Future<T?> generateJson<T>({
    required String prompt,
    required T Function(Map<String, dynamic> json) fromJson,
  }) async {
    jsonCalls++;
    if (neverCompletes) {
      await Completer<String>().future;
    }
    if (fail) throw Exception('error simulado');
    if (jsonResult == null) return null;
    return fromJson(jsonResult!);
  }

  @override
  void dispose() {}
}

void main() {
  group('AIService (fallback Gemini -> Groq -> local)', () {
    test('devuelve el resultado del proveedor principal', () async {
      final primary = _FakeAiClient(available: true, result: 'respuesta A');
      final backup = _FakeAiClient(available: true, result: 'respuesta B');
      final service = AIService(primary: primary, backup: backup);

      final result = await service.generate(prompt: 'hola');

      expect(result, 'respuesta A');
      expect(service.lastProvider, 'fake');
      expect(backup.generateCalls, 0);
    });

    test('salta al respaldo cuando el principal lanza error', () async {
      final primary = _FakeAiClient(available: true, fail: true);
      final backup = _FakeAiClient(available: true, result: 'respuesta B');
      final service = AIService(primary: primary, backup: backup);

      final result = await service.generate(prompt: 'hola');

      expect(result, 'respuesta B');
      expect(primary.generateCalls, 1);
      expect(backup.generateCalls, 1);
    });

    test('salta al respaldo cuando el principal devuelve null (HTTP 429)', () async {
      final primary = _FakeAiClient(available: true, result: null);
      final backup = _FakeAiClient(available: true, result: 'respuesta B');
      final service = AIService(primary: primary, backup: backup);

      final result = await service.generate(prompt: 'hola');

      expect(result, 'respuesta B');
      expect(service.lastProvider, 'fake');
    });

    test('devuelve null si ambos proveedores fallan (usa fallback local)', () async {
      final primary = _FakeAiClient(available: true, fail: true);
      final backup = _FakeAiClient(available: true, fail: true);
      final service = AIService(primary: primary, backup: backup);

      final result = await service.generate(prompt: 'hola');

      expect(result, isNull);
    });

    test('salta al respaldo si el principal se cuelga (timeout)', () async {
      final primary = _FakeAiClient(available: true, neverCompletes: true);
      final backup = _FakeAiClient(available: true, result: 'respuesta B');
      final service = AIService(
        primary: primary,
        backup: backup,
        requestTimeout: const Duration(milliseconds: 50),
      );

      final result = await service.generate(prompt: 'hola');

      expect(result, 'respuesta B');
    });

    test('usa el respaldo si el principal no está configurado', () async {
      final primary = _FakeAiClient(available: false);
      final backup = _FakeAiClient(available: true, result: 'respuesta B');
      final service = AIService(primary: primary, backup: backup);

      final result = await service.generate(prompt: 'hola');

      expect(result, 'respuesta B');
      expect(primary.generateCalls, 0);
    });

    test('generateJson también intercala proveedores', () async {
      final primary = _FakeAiClient(available: true, fail: true);
      final backup = _FakeAiClient(
        available: true,
        jsonResult: {'ok': true},
      );
      final service = AIService(primary: primary, backup: backup);

      final result = await service.generateJson<Map<String, dynamic>>(
        prompt: 'json',
        fromJson: (json) => json,
      );

      expect(result, {'ok': true});
    });
  });

  group('GroqClient', () {
    test('devuelve el contenido en una respuesta 200', () async {
      final mock = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-key');
        return http.Response(
          '{"choices":[{"message":{"content":"Hola desde Groq"}}]}',
          200,
        );
      });
      final client = GroqClient(httpClient: mock, apiKey: 'test-key');

      final result = await client.generate(prompt: 'hola');

      expect(result, 'Hola desde Groq');
    });

    test('generateJson tolera markdown y texto extra', () async {
      final mock = MockClient((request) async {
        return http.Response(
          '{"choices":[{"message":{"content":"```json\\n{\\"ok\\": true}\\n```"}}]}',
          200,
        );
      });
      final client = GroqClient(httpClient: mock, apiKey: 'test-key');

      final result = await client.generateJson<Map<String, dynamic>>(
        prompt: 'devuelve json',
        fromJson: (json) => json,
      );

      expect(result, {'ok': true});
    });

    test('429 agota reintentos y devuelve null', () async {
      var calls = 0;
      final mock = MockClient((request) async {
        calls++;
        return http.Response('rate limited', 429);
      });
      final client = GroqClient(
        httpClient: mock,
        apiKey: 'test-key',
        maxRetries: 1,
      );

      final result = await client.generate(prompt: 'hola');

      expect(result, isNull);
      expect(calls, 2); // 1 intento + 1 reintento
    });
  });

  group('InsightsEngine.generateAiInsight', () {
    Transaction tx(double amount, DateTime at) {
      return Transaction(
        id: 't$amount',
        userId: 'u1',
        accountId: 'a1',
        amount: amount,
        type: TransactionType.expense,
        rawText: '',
        merchantOrPerson: 'Comercio',
        sourceApp: 'Yape',
        source: TransactionSource.auto,
        createdAt: at,
      );
    }

    List<Transaction> monthTransactions(int count, {double base = 10.0}) {
      final now = DateTime.now();
      return List.generate(count, (i) => tx(base + i, now));
    }

    test('no llama a la IA con pocos movimientos', () async {
      final primary = _FakeAiClient(
        available: true,
        jsonResult: {'title': 'T', 'message': 'M'},
      );
      final service = AIService(primary: primary, backup: primary);
      final engine = InsightsEngine(ai: service);

      final insight =
          await engine.generateAiInsight(monthTransactions(2));

      expect(insight, isNull);
      expect(primary.jsonCalls, 0);
    });

    test('genera un insight tipo "ai" cuando hay datos suficientes', () async {
      final primary = _FakeAiClient(
        available: true,
        jsonResult: {
          'title': 'Cuidado con los antojos',
          'message': 'Has gastado S/ 100 este mes.',
        },
      );
      final service = AIService(primary: primary, backup: primary);
      final engine = InsightsEngine(ai: service);

      final insight =
          await engine.generateAiInsight(monthTransactions(8, base: 100.0));

      expect(insight, isNotNull);
      expect(insight!.type, 'ai');
      expect(insight.title, 'Cuidado con los antojos');
    });

    test('no rompe si la IA falla (reglas locales intactas)', () async {
      final primary = _FakeAiClient(available: true, fail: true);
      final service = AIService(primary: primary, backup: primary);
      final engine = InsightsEngine(ai: service);

      final insight =
          await engine.generateAiInsight(monthTransactions(8, base: 200.0));

      expect(insight, isNull);
    });

    test('sin IA configurada devuelve null sin llamadas', () async {
      final engine = InsightsEngine();

      final insight =
          await engine.generateAiInsight(monthTransactions(8));

      expect(insight, isNull);
    });
  });
}
