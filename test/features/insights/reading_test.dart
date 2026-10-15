import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/core/theme/tokens.dart';
import 'package:saldo_claro/domain/insights.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/insights/reading.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import '../home/home_screen_test.dart' as h;
import 'insights_screen_test.dart' show expectOrder, full, openInsights, scrollTo;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  group('frases', () {
    const names = {'comida': 'Comida', 'ocio': 'Ocio'};
    String t(Fact f) => factText(f, categoryNames: names);
    final sep = day(2026, 9, 1);

    test('balance del mes', () {
      expect(t(const BalanceFact(cents: -15000)), 'Este mes salió S/ 150.00 más de lo que entró.');
      expect(t(const BalanceFact(cents: 30000)), 'Este mes te quedan S/ 300.00 de lo que entró.');
    });

    test('categoría que sube y que baja', () {
      expect(t(CategoryChange(categoryId: 'comida', deltaCents: 12000, percent: 35, previousMonth: sep)),
          'Vas S/ 120.00 más en Comida que a esta altura de septiembre (+35%).');
      expect(t(CategoryChange(categoryId: 'ocio', deltaCents: -3000, percent: -40, previousMonth: sep)),
          'Vas S/ 30.00 menos en Ocio que a esta altura de septiembre (−40%).');
    });

    test('días restantes: plural, singular y sin reserva', () {
      expect(t(const DaysLeftFact(days: 17, balanceCents: 85000, dailyCents: 5000)),
          'Quedan 17 días del mes: con S/ 850.00 te alcanza ~S/ 50.00 al día.');
      expect(t(const DaysLeftFact(days: 1, balanceCents: 2000, dailyCents: 2000)),
          'Queda 1 día del mes: con S/ 20.00 te alcanza ~S/ 20.00 al día.');
      expect(t(const DaysLeftFact(days: 17, balanceCents: -500, dailyCents: null)),
          'Quedan 17 días del mes y no tienes reserva.');
    });

    test('racha y día de la semana', () {
      expect(t(const StreakFact(days: 12, thresholdCents: 3000)), 'Llevas 12 días sin pasarte de S/ 30.00 al día.');
      expect(t(const WeekdayFact(weekday: DateTime.saturday, avgCents: 6000)),
          'Los sábados es cuando más gastas: S/ 60.00 en promedio.');
      expect(t(const WeekdayFact(weekday: DateTime.monday, avgCents: 6000)),
          'Los lunes es cuando más gastas: S/ 60.00 en promedio.');
    });
  });

  group('bloque "Lectura del mes"', () {
    Finder lines() => find.descendant(of: find.byKey(const Key('insights.reading')), matching: find.byType(Text));

    testWidgets('con cuentas: arriba de "Por cuenta"; máximo 4 frases en inkMuted', (tester) async {
      final s = await h.seeded(Mode.variable);
      await full(s);
      await s.db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone_android');
      await openInsights(tester, s);
      await scrollTo(tester, 'insights.byAccount');
      expect(find.text('Lectura del mes'), findsOneWidget);
      expectOrder(tester, ['insights.reading', 'insights.byAccount']);
      final texts = tester.widgetList<Text>(lines()).where((t) => t.data != 'Lectura del mes').toList();
      expect(texts.length, inInclusiveRange(1, 4));
      for (final t in texts) {
        expect(t.style?.color, Palette.light.inkMuted, reason: t.data);
      }
      await h.unmount(tester);
    });

    testWidgets('sin cuentas: queda al final', (tester) async {
      final s = await h.seeded(Mode.variable);
      await full(s);
      await openInsights(tester, s);
      await scrollTo(tester, 'insights.reading');
      expectOrder(tester, ['insights.runway', 'insights.reading']);
      await h.unmount(tester);
    });

    testWidgets('sin datos, no aparece', (tester) async {
      await openInsights(tester, await h.seeded(Mode.variable));
      expect(find.byKey(const Key('insights.reading')), findsNothing);
      await h.unmount(tester);
    });

    testWidgets('320×568 dp con letra ×1.3: sin desbordes', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final s = await h.seeded(Mode.variable);
      await full(s);
      await h.pumpHome(tester, s, size: const Size(320, 568));
      await tester.tap(find.byTooltip('Insights'));
      await tester.pumpAndSettle();
      await scrollTo(tester, 'insights.reading');
      expect(tester.takeException(), isNull);
      await h.unmount(tester);
    });
  });
}
