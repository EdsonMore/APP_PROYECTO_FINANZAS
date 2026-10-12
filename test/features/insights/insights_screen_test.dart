import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
import 'package:saldo_claro/core/theme/tokens.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/insights/insights_screen.dart';
import 'package:saldo_claro/features/insights/runway_line.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import '../home/home_screen_test.dart' as h;

/// Abre Insights desde el ícono del Home (el acceso real, I1).
Future<void> openInsights(WidgetTester tester, h.Seed seed, {ThemeData? theme}) async {
  await h.pumpHome(tester, seed, theme: theme);
  await tester.tap(find.byTooltip('Insights'));
  await tester.pumpAndSettle();
}

/// Datos completos: 2 meses cerrados, 14 días de serie, gasto en 3 categorías.
Future<void> full(h.Seed s) async {
  await s.income(900, day(2026, 8, 1));
  await s.income(600, day(2026, 9, 3));
  await s.twoWeeks();
  await s.expense(30, h.ago(2), cat: 'ocio');
  await s.expense(20, h.ago(3), cat: 'transporte');
}

double top(WidgetTester tester, String key) => tester.getTopLeft(find.byKey(Key(key))).dy;

void expectOrder(WidgetTester tester, List<String> keys) {
  for (var i = 1; i < keys.length; i++) {
    expect(top(tester, keys[i - 1]), lessThan(top(tester, keys[i])), reason: '${keys[i - 1]} antes que ${keys[i]}');
  }
}

Future<void> scrollTo(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(find.byKey(Key(key)), 200, scrollable: find.byType(Scrollable).last);
  await tester.pumpAndSettle();
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

  testWidgets('el ícono del Home abre Insights en los 3 modos (I1)', (tester) async {
    for (final mode in Mode.values) {
      await openInsights(tester, await h.seeded(mode));
      expect(find.byType(InsightsScreen), findsOneWidget, reason: mode.name);
      expect(find.text('Últimos 30 días'), findsOneWidget);
      await h.unmount(tester);
    }
  });

  testWidgets('Estable: frase E1 y orden presupuesto → gasto → racha → meses → reserva', (tester) async {
    await openInsights(
        tester,
        await h.seeded(Mode.stable, (s) async {
          await full(s);
          await s.budget('comida', 50000);
        }));
    expect(tester.takeException(), isNull);
    expect(find.text('Llevas S/\u00A0130.00 de S/\u00A0500.00 de tus techos este mes.'), findsOneWidget,
        reason: 'espacio no separable: el monto no se parte');
    expect(find.byKey(const Key('insights.seeBudget')), findsOneWidget);
    expectOrder(tester, ['insights.phrase', 'insights.budget', 'insights.spend', 'insights.streak', 'insights.months',
      'insights.runway']);
    expect(tester.getSize(find.byKey(const Key('insights.runwayLine'))).height, 96);
    await h.unmount(tester);
  });

  testWidgets('Variable: entra y sale → meses → gasto → reserva → racha', (tester) async {
    await openInsights(tester, await h.seeded(Mode.variable, full));
    expect(find.textContaining('En un mes típico te sobran'), findsOneWidget);
    expectOrder(tester, ['insights.phrase', 'insights.flow', 'insights.months', 'insights.spend', 'insights.runway',
      'insights.streak']);
    expect(find.text('Septiembre'), findsOneWidget);
    expect(find.text('Agosto'), findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('Supervivencia: reserva alto primero, meses al fondo', (tester) async {
    await openInsights(tester, await h.seeded(Mode.survival, full));
    expect(find.text('A este ritmo te alcanza para 170 días.'), findsOneWidget);
    expectOrder(tester, ['insights.phrase', 'insights.runway', 'insights.streak', 'insights.suggested', 'insights.spend',
      'insights.months']);
    expect(tester.getSize(find.byKey(const Key('insights.runwayLine'))).height, 140);
    expect(find.descendant(of: find.byKey(const Key('insights.runway')), matching: find.text('Reserva')), findsOneWidget,
        reason: 'título del bloque (antes "Colchón")');
    await h.unmount(tester);
  });

  testWidgets('[Usar] en Supervivencia: se desvanece, guarda y avisa dónde verlo (3 s)', (tester) async {
    final seed = await h.seeded(Mode.survival, full);
    await openInsights(tester, seed);
    await scrollTo(tester, 'insights.use.ocio');
    await tester.tap(find.byKey(const Key('insights.use.ocio')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('insights.suggestedSnack')), findsNothing, reason: 'primero el fundido');
    await tester.pumpAndSettle();
    expect(find.text('Techo de Ocio guardado. Lo verás en Presupuesto cuando cambies a modo Estable.'), findsOneWidget);
    final b = await seed.db.select(seed.db.budgets).get();
    expect(b.map((x) => x.categoryId), ['ocio']);
    expect(find.byKey(const Key('insights.use.ocio')), findsNothing, reason: 'la fila se fue');
    await tester.pump(suggestedSnackDuration + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('insights.suggestedSnack')), findsNothing, reason: 'se va sola');
    await h.unmount(tester);
  });

  testWidgets('sin datos: frase de espera, solo bloques con texto de espera', (tester) async {
    await openInsights(tester, await h.seeded(Mode.stable));
    expect(find.text('Registra unos días más y aquí verás tu patrón.'), findsOneWidget);
    expect(find.byKey(const Key('insights.defineBudgets')), findsOneWidget);
    expect(find.text('Cuando cierres dos meses te muestro tu mes típico.'), findsOneWidget);
    expect(find.text('Necesito una semana de datos para dibujar tu tendencia.'), findsOneWidget);
    for (final k in ['spend', 'streak', 'flow', 'suggested', 'runwayLine']) {
      expect(find.byKey(Key('insights.$k')), findsNothing, reason: k);
    }
    await h.unmount(tester);
  });

  testWidgets('te faltan: frase en expenseFg con ícono', (tester) async {
    await openInsights(
        tester,
        await h.seeded(Mode.variable, (s) async {
          await s.income(100, h.ago(5));
          await s.expense(300, h.ago(5));
        }));
    final t = tester.widget<Text>(find.byKey(const Key('insights.flowSentence')));
    expect(t.data, 'Te faltan ~S/ 1,000.00 en un mes típico.');
    expect(t.style!.color, Palette.light.expenseFg);
    expect(find.descendant(of: find.byKey(const Key('insights.flow')), matching: find.byIcon(Icons.error_outline)),
        findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('racha en 0 por el gasto de hoy: "Hoy pasaste tu límite diario." sin rojo', (tester) async {
    await openInsights(
        tester,
        await h.seeded(Mode.variable, (s) async {
          await s.income(300, h.ago(9));
          await s.expense(500, h.today);
        }));
    await scrollTo(tester, 'insights.streak');
    final t = tester.widget<Text>(find.text('Hoy pasaste tu límite diario.'));
    expect(t.style!.color, Palette.light.inkMuted);
    await h.unmount(tester);
  });

  testWidgets('reserva: la serie con días sin reserva corta la línea y el rótulo lo dice', (tester) async {
    await openInsights(
        tester,
        await h.seeded(Mode.survival, (s) async {
          await s.income(200, h.ago(9));
          for (var i = 9; i >= 2; i--) {
            await s.expense(10, h.ago(i));
          }
          await s.expense(300, h.ago(1)); // desde ayer, saldo negativo
        }));
    final painter = tester.widget<CustomPaint>(
        find.descendant(of: find.byKey(const Key('insights.runwayLine')), matching: find.byType(CustomPaint))).painter
        as RunwayLine;
    expect(painter.series.last, isNull);
    expect(RunwayLine.segments(painter.series), hasLength(1), reason: 'un tramo y luego el corte');
    expect(find.textContaining('días → sin reserva', findRichText: true), findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('reserva con menos de 7 días de serie: texto de espera, sin línea', (tester) async {
    await openInsights(
        tester,
        await h.seeded(Mode.survival, (s) async {
          await s.income(200, h.ago(5));
          await s.expense(10, h.ago(5));
        }));
    expect(find.text('Necesito una semana de datos para dibujar tu tendencia.'), findsOneWidget);
    expect(find.byKey(const Key('insights.runwayLine')), findsNothing);
    await h.unmount(tester);
  });

  testWidgets('tema oscuro: barras de gasto con el color oscuro de la categoría', (tester) async {
    await openInsights(tester, await h.seeded(Mode.stable, full), theme: AppTheme.dark);
    expect(tester.takeException(), isNull);
    final bar = tester.widget<Container>(find.byKey(const Key('insights.spendBar.Comida')));
    expect((bar.decoration! as BoxDecoration).color, categoryDark[0]);
    await h.unmount(tester);
  });

  testWidgets('hallazgo 2: si [Usar] no puede guardar, la fila vuelve y avisa el error', (tester) async {
    await openInsights(tester, await h.seeded(Mode.survival, full, h.FailingBudgetDb()));
    await scrollTo(tester, 'insights.use.ocio');
    await tester.tap(find.byKey(const Key('insights.use.ocio')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'el error se maneja, no se escapa');
    expect(find.text('No se pudo guardar el techo. Intenta de nuevo.'), findsOneWidget);
    expect(find.byKey(const Key('insights.suggestedSnack')), findsNothing);
    final fade = tester.widget<AnimatedOpacity>(
        find.ancestor(of: find.byKey(const Key('insights.use.ocio')), matching: find.byType(AnimatedOpacity)));
    expect(fade.opacity, 1, reason: 'la fila vuelve a verse y se puede reintentar');
    await h.unmount(tester);
  });

  testWidgets('hallazgo 5: reconstruir Insights reutiliza las animaciones de entrada (no crea nuevas)', (tester) async {
    final seed = await h.seeded(Mode.stable, full);
    await openInsights(tester, seed);
    Listenable reveal() => tester
        .widget<AnimatedBuilder>(
            find.ancestor(of: find.byKey(const Key('insights.phrase')), matching: find.byType(AnimatedBuilder)).first)
        .animation;
    final before = reveal();
    await seed.expense(1, h.today); // cada movimiento reconstruye Insights
    await tester.pumpAndSettle();
    expect(reveal(), same(before));
    await h.unmount(tester);
  });
}
