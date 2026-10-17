import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
import 'package:saldo_claro/core/theme/tokens.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/data/providers.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/domain/recurrence.dart';
import 'package:saldo_claro/features/ai/ai_client.dart';
import 'package:saldo_claro/features/ai/chat_screen.dart';
import 'package:saldo_claro/features/entry/draft_store.dart';
import 'package:saldo_claro/features/settings/settings_screen.dart';
import 'package:saldo_claro/features/sync/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';

final today = day(2026, 10, 15);

class ChatHost {
  ChatHost(this.db, this.prefs, this.client);
  final AppDatabase db;
  final SharedPreferences prefs;
  final FakeAiClient client;
}

/// El chat solo (o [home]), con datos: ingreso de S/ 900 el 1 de octubre.
Future<ChatHost> pumpChat(WidgetTester tester,
    {String? email = 'tu@correo.com',
    int used = 0,
    bool consented = true,
    int pending = 0,
    Size size = const Size(411, 914),
    Widget? home}) async {
  const dpr = 2.625;
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({if (consented) 'ai.consentVersion': aiConsentVersion});
  SharedPreferences.resetStatic();
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await db.completeOnboarding(mode: Mode.variable);
  await db.insertManualEntry(
      id: 'i1', kind: EntryKind.income, amountCents: 90000, day: day(2026, 10, 1), pickId: 'chamba', now: DateTime(2026, 10, 1));
  for (var i = 0; i < pending; i++) {
    await db.insertRecurrence(
        id: 'r$i', amountCents: 4500 + i, categoryId: 'vivienda', frequency: Frequency.monthly,
        firstDue: today.add(Duration(days: i)));
  }
  final host = ChatHost(db, await SharedPreferences.getInstance(), FakeAiClient()..used = used);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(host.prefs),
      todayProvider.overrideWithValue(today),
      accountEmailProvider.overrideWith((ref) => Stream.value(email)),
      aiClientProvider.overrideWithValue(host.client),
    ],
    child: MaterialApp(theme: AppTheme.light, home: home ?? const AiChatScreen()),
  ));
  await tester.pumpAndSettle();
  return host;
}

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Finder q(AiQuestion question) => find.byKey(Key('ai.q.${question.wire}'));

Future<void> tapQ(WidgetTester tester, AiQuestion question) async {
  await tester.ensureVisible(q(question));
  await tester.tap(q(question));
  await tester.pumpAndSettle();
}

Future<void> keys(WidgetTester tester, String seq) async {
  for (final k in seq.split('')) {
    await tester.tap(find.byKey(Key('key.$k')));
    await tester.pump();
  }
}

Future<void> sendFree(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('ai.input')), text);
  await tester.pump();
  await tester.tap(find.byKey(const Key('ai.send')));
  await tester.pumpAndSettle();
}

Color colorOf(WidgetTester tester, Finder f) => tester.widget<Text>(f).style!.color!;

bool enabled(WidgetTester tester, Finder f) {
  final w = tester.widget(f);
  return switch (w) {
    IconButton(:final onPressed) => onPressed != null,
    TextField(:final enabled) => enabled ?? true,
    InkWell(:final onTap) => onTap != null,
    _ => throw StateError('$w'),
  };
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });

  testWidgets('C2: Ajustes → Inteligencia artificial abre el chat (activada o no)', (tester) async {
    await pumpChat(tester, consented: false, home: const SettingsScreen());
    await tester.scrollUntilVisible(find.byKey(const Key('settings.ai')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('settings.ai')));
    await tester.pumpAndSettle();
    expect(find.byType(AiChatScreen), findsOneWidget);
    expect(find.text('Pregúntale a SaldoClaro'), findsOneWidget);
    expect(find.text('Antes de usar la IA'), findsNothing, reason: 'el consentimiento se pide al enviar');
    await unmount(tester);
  });

  group('contador', () {
    testWidgets('7 en inkMuted; con 2 o menos, en rojo', (tester) async {
      await pumpChat(tester, used: 3);
      expect(find.text('Te quedan 7 consultas hoy'), findsOneWidget);
      expect(colorOf(tester, find.byKey(const Key('ai.counter'))), Palette.light.inkMuted);
      await unmount(tester);
      await pumpChat(tester, used: 8);
      expect(find.text('Te quedan 2 consultas hoy'), findsOneWidget);
      expect(colorOf(tester, find.byKey(const Key('ai.counter'))), Palette.light.expenseFg);
      await unmount(tester);
    });

    testWidgets('sin cuenta, sin contador', (tester) async {
      await pumpChat(tester, email: null);
      expect(find.byKey(const Key('ai.counter')), findsNothing);
      await unmount(tester);
    });
  });

  testWidgets('C5: 5 predefinidas; "pagar primero" solo con 2 o más pendientes', (tester) async {
    await pumpChat(tester, pending: 1);
    for (final question in AiQuestion.values.where((x) => x != AiQuestion.free && x != AiQuestion.payFirst)) {
      expect(q(question), findsOneWidget, reason: question.wire);
    }
    expect(q(AiQuestion.payFirst), findsNothing);
    expect(find.text('¿Puedo gastar S/ X en algo?'), findsOneWidget);
    await unmount(tester);
    await pumpChat(tester, pending: 2);
    expect(find.text('¿Qué me conviene pagar primero?'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('can_spend: monto y "¿En qué?" con el teclado propio; burbuja, respuesta, contador y lo enviado', (tester) async {
    final host = await pumpChat(tester, used: 0);
    await tapQ(tester, AiQuestion.canSpend);
    expect(find.text('¿Cuánto?'), findsOneWidget);
    expect(find.text('¿En qué?'), findsOneWidget);
    await keys(tester, '120');
    await tester.enterText(find.byKey(const Key('ai.amount.item')), 'zapatillas');
    await tester.tap(find.byKey(const Key('ai.amount.ask')));
    await tester.pumpAndSettle();
    expect(find.text('¿Puedo gastar S/ 120.00 en zapatillas?'), findsOneWidget);
    expect(find.text('Te quedan S/ 850.00.'), findsOneWidget);
    expect(find.text('Te quedan 9 consultas hoy'), findsOneWidget);
    final sent = host.client.sent.single;
    expect(sent['question'], 'can_spend');
    expect(sent['input'], {'amountCents': 12000, 'item': 'zapatillas'});
    expect((sent['facts']! as Map)['balanceAfterCents'], 78000);
    await unmount(tester);
  });

  testWidgets('what_if pide solo monto; sin monto, "Preguntar" deshabilitado', (tester) async {
    final host = await pumpChat(tester);
    await tapQ(tester, AiQuestion.whatIf);
    expect(find.byKey(const Key('ai.amount.item')), findsNothing);
    expect(tester.widget<FilledButton>(find.byKey(const Key('ai.amount.ask'))).onPressed, isNull);
    await keys(tester, '50');
    await tester.tap(find.byKey(const Key('ai.amount.ask')));
    await tester.pumpAndSettle();
    expect(find.text('¿Qué pasaría si gasto S/ 50.00 más al mes?'), findsOneWidget);
    expect(host.client.sent.single['input'], {'amountCents': 5000});
    await unmount(tester);
  });

  testWidgets('save con 2 meses de datos (desde el 10 de septiembre): el paquete lleva months', (tester) async {
    final host = await pumpChat(tester);
    await host.db.insertManualEntry(
        id: 's1', kind: EntryKind.income, amountCents: 250000, day: day(2026, 9, 10), pickId: 'chamba', now: DateTime(2026, 9, 10));
    await host.db.insertManualEntry(
        id: 's2', kind: EntryKind.expense, amountCents: 70000, day: day(2026, 9, 12), pickId: 'comida', now: DateTime(2026, 9, 12));
    await tester.pumpAndSettle();
    await tapQ(tester, AiQuestion.save);
    final facts = host.client.sent.single['facts']! as Map;
    expect(facts['months'], [
      {'month': '2026-09', 'incomeCents': 250000, 'expenseCents': 70000, 'netCents': 180000, 'partial': true},
    ]);
    expect((facts['surplusMonths'], facts['redMonths'], facts['avgSurplusCents']), (1, 0, 180000));
    await unmount(tester);
  });

  testWidgets('break_even con datos desde el 10 de septiembre: incomeByMonth lleva septiembre parcial', (tester) async {
    final host = await pumpChat(tester);
    await host.db.insertManualEntry(
        id: 'b1', kind: EntryKind.income, amountCents: 250000, day: day(2026, 9, 10), pickId: 'chamba', now: DateTime(2026, 9, 10));
    await tester.pumpAndSettle();
    await tapQ(tester, AiQuestion.breakEven);
    final facts = host.client.sent.single['facts']! as Map;
    expect(facts['incomeByMonth'], [
      {'month': '2026-09', 'incomeCents': 250000, 'partial': true},
    ]);
    await unmount(tester);
  });

  testWidgets('primer envío sin consentimiento: "Ahora no" no envía; aceptar envía', (tester) async {
    final host = await pumpChat(tester, consented: false);
    await tapQ(tester, AiQuestion.cut);
    expect(find.text('Antes de usar la IA'), findsOneWidget);
    await tester.tap(find.text('Ahora no'));
    await tester.pumpAndSettle();
    expect(host.client.sent, isEmpty);
    expect(find.byKey(const Key('ai.msg.user')), findsNothing);
    await tapQ(tester, AiQuestion.cut);
    await tester.tap(find.byKey(const Key('ai.consent.check')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai.consent.continue')));
    await tester.pumpAndSettle();
    expect(host.client.sent.single['question'], 'cut');
    expect(find.text('¿Qué puedo recortar sin que se sienta?'), findsWidgets);
    await unmount(tester);
  });

  testWidgets('campo libre: vacío deshabilitado; manda "free" con el texto; máximo 200', (tester) async {
    final host = await pumpChat(tester);
    expect(enabled(tester, find.byKey(const Key('ai.send'))), isFalse);
    await sendFree(tester, '¿Voy bien este mes?');
    expect(host.client.sent.single, containsPair('question', 'free'));
    expect(host.client.sent.single['input'], {'text': '¿Voy bien este mes?'});
    expect(find.text('¿Voy bien este mes?'), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('ai.input'))).maxLength, aiFreeTextMax);
    expect(tester.widget<TextField>(find.byKey(const Key('ai.input'))).controller!.text, isEmpty, reason: 'se limpia');
    await unmount(tester);
  });

  testWidgets('7: límite al abrir: predefinidas, campo y enviar deshabilitados, con el aviso', (tester) async {
    await pumpChat(tester, used: 10);
    expect(find.byKey(const Key('ai.limit')), findsOneWidget);
    expect(find.text('Llegaste al límite de hoy. Vuelve mañana.'), findsWidgets);
    expect(enabled(tester, find.byKey(const Key('ai.input'))), isFalse);
    expect(enabled(tester, find.descendant(of: q(AiQuestion.cut), matching: find.byType(InkWell)).first), isFalse);
    await unmount(tester);
  });

  testWidgets('7: al gastar la última (left 0) queda en estado límite', (tester) async {
    final host = await pumpChat(tester, used: 9);
    host.client.next = const AiAnswer('Te quedan S/ 850.00.', 0);
    await sendFree(tester, '¿Voy bien?');
    expect(find.byKey(const Key('ai.limit')), findsOneWidget);
    expect(enabled(tester, find.byKey(const Key('ai.input'))), isFalse);
    await unmount(tester);
  });

  group('8: errores', () {
    for (final (error, retry) in [
      (AiError.offline, true),
      (AiError.unavailable, true),
      (AiError.unverified, true),
      (AiError.session, false),
    ]) {
      testWidgets('${error.name}: su texto${retry ? ' y "Reintentar"' : ', sin reintentar'}', (tester) async {
        final host = await pumpChat(tester);
        host.client.next = AiFailure(error);
        await sendFree(tester, '¿Voy bien?');
        expect(find.text(aiErrorTexts[error]!), findsOneWidget);
        expect(find.byKey(const Key('ai.retry')), retry ? findsOneWidget : findsNothing);
        await unmount(tester);
      });
    }

    testWidgets('"Reintentar" reenvía la misma pregunta sin repetir la burbuja', (tester) async {
      final host = await pumpChat(tester);
      host.client.next = const AiFailure(AiError.unavailable);
      await sendFree(tester, '¿Voy bien?');
      host.client.next = const AiAnswer('Vas bien: te quedan S/ 850.00.', 8);
      await tester.tap(find.byKey(const Key('ai.retry')));
      await tester.pumpAndSettle();
      expect(host.client.sent.length, 2);
      expect(host.client.sent.last['input'], {'text': '¿Voy bien?'});
      expect(find.text('¿Voy bien?'), findsOneWidget);
      expect(find.text(aiErrorTexts[AiError.unavailable]!), findsNothing);
      expect(find.text('Vas bien: te quedan S/ 850.00.'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('límite desde la función: estado límite', (tester) async {
      final host = await pumpChat(tester, used: 4);
      host.client.next = const AiFailure(AiError.limit);
      await sendFree(tester, '¿Voy bien?');
      expect(find.byKey(const Key('ai.limit')), findsOneWidget);
      expect(find.byKey(const Key('ai.retry')), findsNothing);
      await unmount(tester);
    });
  });

  testWidgets('mientras espera: burbuja "Esperando respuesta" y no se puede enviar otra', (tester) async {
    final host = await pumpChat(tester);
    final gate = Completer<void>();
    host.client.gate = gate.future;
    await tester.enterText(find.byKey(const Key('ai.input')), '¿Voy bien?');
    await tester.pump();
    await tester.tap(find.byKey(const Key('ai.send')));
    await tester.pump();
    expect(find.bySemanticsLabel('Esperando respuesta'), findsOneWidget);
    expect(enabled(tester, find.descendant(of: q(AiQuestion.canSpend), matching: find.byType(InkWell)).first), isFalse);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Esperando respuesta'), findsNothing);
    await unmount(tester);
  });

  testWidgets('6: el historial vive solo en la pantalla: al volver está vacío', (tester) async {
    await pumpChat(tester, home: Builder(
      builder: (ctx) => Scaffold(
        body: TextButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const AiChatScreen())),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await sendFree(tester, '¿Voy bien?');
    expect(find.byKey(const Key('ai.msg.answer')), findsOneWidget);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('ai.msg.answer')), findsNothing);
    expect(find.byKey(const Key('ai.msg.user')), findsNothing);
    await unmount(tester);
  });

  testWidgets('pie: aviso y "Desactivar la IA" borra el consentimiento', (tester) async {
    final host = await pumpChat(tester);
    expect(find.text('Respuestas generadas con tus números. No es asesoría financiera.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('ai.deactivate.link')));
    await tester.tap(find.byKey(const Key('ai.deactivate.link')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('ai.deactivate')));
    await tester.pumpAndSettle();
    expect(host.prefs.getInt('ai.consentVersion'), isNull);
    expect(find.byKey(const Key('ai.deactivate.link')), findsNothing, reason: 'sin activar no hay qué desactivar');
    await unmount(tester);
  });

  testWidgets('320×568 dp con letra ×1.3: sin desbordes; campo y enviar se tocan; con respuesta también', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpChat(tester, size: const Size(320, 568), pending: 2);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ai.input')).hitTestable(), findsOneWidget);
    await sendFree(tester, '¿Voy bien?');
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('ai.send')).hitTestable(), findsOneWidget);
    await unmount(tester);
  });
}
