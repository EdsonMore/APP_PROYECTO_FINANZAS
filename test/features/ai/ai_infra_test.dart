import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/data/providers.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/ai/ai_client.dart';
import 'package:saldo_claro/features/ai/consent.dart';
import 'package:saldo_claro/features/ai/usage.dart';
import 'package:saldo_claro/features/entry/draft_store.dart';
import 'package:saldo_claro/features/settings/legal_screen.dart';
import 'package:saldo_claro/features/sync/providers.dart';
import 'package:saldo_claro/features/sync/screens/sync_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';

class AiHost {
  AiHost(this.prefs, this.client);
  final SharedPreferences prefs;
  final FakeAiClient client;
  bool? result;
}

/// Un botón "usar IA" que llama a ensureAiConsent; [home] reemplaza la pantalla.
Future<AiHost> pumpAi(WidgetTester tester, {String? email = 'tu@correo.com', int used = 0, Widget? home}) async {
  const dpr = 2.625;
  tester.view.physicalSize = const Size(411, 914) * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await db.completeOnboarding(mode: Mode.variable);
  final host = AiHost(await SharedPreferences.getInstance(), FakeAiClient()..used = used);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(host.prefs),
      todayProvider.overrideWithValue(day(2026, 10, 15)),
      accountEmailProvider.overrideWith((ref) => Stream.value(email)),
      aiClientProvider.overrideWithValue(host.client),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: home ??
          Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => host.result = await ensureAiConsent(ctx),
                  child: const Text('usar IA'),
                ),
              ),
            ),
          ),
    ),
  ));
  await tester.pumpAndSettle();
  return host;
}

Future<void> useAi(WidgetTester tester) async {
  await tester.tap(find.text('usar IA'));
  await tester.pumpAndSettle();
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  group('consentimiento (I5)', () {
    const accept = 'Acepto que mis datos agregados se envíen a Google para responder.';

    testWidgets('"Continuar" deshabilitado sin marcar; al aceptar guarda versión y fecha', (tester) async {
      final host = await pumpAi(tester);
      await useAi(tester);
      expect(find.text('Antes de usar la IA'), findsOneWidget);
      expect(find.text(accept), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('ai.consent.continue'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('ai.consent.check')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('ai.consent.continue')));
      await tester.pumpAndSettle();
      expect(host.result, isTrue);
      expect(host.prefs.getInt('ai.consentVersion'), aiConsentVersion);
      expect(host.prefs.getString('ai.consentAt'), isNotNull);
      await unmount(tester);
    });

    testWidgets('"Ahora no" no guarda nada', (tester) async {
      final host = await pumpAi(tester);
      await useAi(tester);
      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();
      expect(host.result, isFalse);
      expect(host.prefs.getInt('ai.consentVersion'), isNull);
      await unmount(tester);
    });

    testWidgets('ya aceptado: no vuelve a preguntar; con una versión vieja, sí', (tester) async {
      SharedPreferences.setMockInitialValues({'ai.consentVersion': aiConsentVersion});
      var host = await pumpAi(tester);
      await useAi(tester);
      expect(find.text('Antes de usar la IA'), findsNothing);
      expect(host.result, isTrue);
      await unmount(tester);

      SharedPreferences.setMockInitialValues({'ai.consentVersion': aiConsentVersion - 1});
      SharedPreferences.resetStatic();
      host = await pumpAi(tester);
      await useAi(tester);
      expect(find.text('Antes de usar la IA'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('el enlace abre la política de privacidad', (tester) async {
      await pumpAi(tester);
      await useAi(tester);
      await tester.tap(find.byKey(const Key('ai.consent.policy')));
      await tester.pumpAndSettle();
      expect(find.byType(LegalScreen), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('I1 sin cuenta: pide crear cuenta (no el consentimiento) y lleva a Sincronizar', (tester) async {
      final host = await pumpAi(tester, email: null);
      await useAi(tester);
      expect(find.text('Para usar la IA necesitas una cuenta'), findsOneWidget);
      expect(find.text('Antes de usar la IA'), findsNothing);
      await tester.tap(find.byKey(const Key('ai.account.create')));
      await tester.pumpAndSettle();
      expect(find.byType(SyncScreen), findsOneWidget);
      expect(host.result, isFalse);
      await unmount(tester);
    });
  });

  group('contador', () {
    test('textos: plural, singular y límite', () {
      expect(aiUsageText((today: 3, left: 7)), 'Te quedan 7 consultas hoy');
      expect(aiUsageText((today: 9, left: 1)), 'Te queda 1 consulta hoy');
      expect(aiUsageText((today: 10, left: 0)), 'Llegaste al límite de hoy. Vuelve mañana.');
    });

    testWidgets('lee el uso de hoy; tras una consulta usa el "left" de la respuesta sin otra llamada', (tester) async {
      final host = await pumpAi(tester, used: 3);
      final container = ProviderScope.containerOf(tester.element(find.text('usar IA')));
      final sub = container.listen(aiUsageProvider, (_, _) {});
      addTearDown(sub.close);
      expect(await container.read(aiUsageProvider.future), (today: 3, left: 7));
      container.read(aiUsageProvider.notifier).applyLeft(6);
      expect(container.read(aiUsageProvider).value, (today: 4, left: 6));
      expect(host.client.usedTodayCalls, 1);
      await unmount(tester);
    });

    testWidgets('sin cuenta no hay contador', (tester) async {
      final host = await pumpAi(tester, email: null);
      final container = ProviderScope.containerOf(tester.element(find.text('usar IA')));
      final sub = container.listen(aiUsageProvider, (_, _) {});
      addTearDown(sub.close);
      expect(await container.read(aiUsageProvider.future), isNull);
      expect(host.client.usedTodayCalls, 0);
      await unmount(tester);
    });
  });

  group('cliente', () {
    test('cada código de la función, su error y su texto', () {
      expect([401, 429, 422, 502, 504, 500, null].map(aiErrorFor), [
        AiError.session, AiError.limit, AiError.unverified, AiError.unavailable, AiError.unavailable,
        AiError.unavailable, AiError.offline,
      ]);
      expect(aiErrorTexts, {
        AiError.session: 'Tu sesión venció. Vuelve a entrar.',
        AiError.limit: 'Llegaste al límite de hoy. Vuelve mañana.',
        AiError.offline: 'No hay conexión. La IA necesita internet.',
        AiError.unavailable: 'La IA no respondió. Intenta de nuevo en un rato.',
        AiError.unverified: 'No pude responder con tus números. Intenta de nuevo.',
      });
    });

    test('el cuerpo lleva la pregunta, los hechos, la versión del consentimiento y nada más', () {
      final b = aiRequestBody(AiQuestion.canSpend, {'balanceCents': 85000}, amountCents: 12000, item: 'zapatillas');
      expect(b, {
        'question': 'can_spend',
        'facts': {'balanceCents': 85000},
        'input': {'amountCents': 12000, 'item': 'zapatillas'},
        'consentVersion': aiConsentVersion,
      });
      expect(aiRequestBody(AiQuestion.cut, const {}), {'question': 'cut', 'facts': {}, 'consentVersion': aiConsentVersion});
      expect([for (final q in AiQuestion.values) q.wire],
          ['cut', 'can_spend', 'what_if', 'break_even', 'save', 'pay_first', 'can_afford_installment', 'free'], reason: 'los mismos ids que la función');
      expect(aiRequestBody(AiQuestion.free, const {}, text: '¿Voy bien?'),
          {'question': 'free', 'facts': {}, 'input': {'text': '¿Voy bien?'}, 'consentVersion': aiConsentVersion});
    });
  });
}
