import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
import 'package:saldo_claro/core/theme/tokens.dart';
import 'package:saldo_claro/core/widgets/choice_card.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/data/providers.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/onboarding/onboarding_screen.dart';

Future<AppDatabase> pumpOnboarding(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: MaterialApp(theme: AppTheme.light, home: const OnboardingScreen()),
  ));
  return db;
}

Future<void> choose(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump(Motion.lightChange); // pausa de confirmación antes de avanzar
  await tester.pumpAndSettle();
}

Finder checkIn(String label) =>
    find.descendant(of: find.widgetWithText(ChoiceCard, label), matching: find.byIcon(Icons.check));

void main() {
  group('validateSpaceName', () {
    test('trim y vacío → null sin error', () {
      expect(validateSpaceName('   '), (value: null, error: null));
      expect(validateSpaceName('  Casa  ').value, 'Casa');
    });

    group('quita emojis', () {
      for (final (input, expected) in [
        ('Mi casa 🏠', 'Mi casa'),
        ('Café ☕️', 'Café'), // U+2615 + variation selector U+FE0F
        ('Viaje 🇵🇪', 'Viaje'), // bandera = 2 indicadores regionales
        ('Gym 👍🏽', 'Gym'), // modificador de tono de piel
        ('Familia 👨‍👩‍👧', 'Familia'), // secuencia ZWJ
        ('Piso 1️⃣', 'Piso 1'), // keycap: 1 + U+FE0F + U+20E3
        ('Escocia 🏴󠁧󠁢󠁳󠁣󠁴󠁿', 'Escocia'), // bandera con tag characters U+E0020–E007F
      ]) {
        test('"$input" → "$expected"', () {
          final v = validateSpaceName(input).value!;
          expect(v, expected);
          expect(v.runes.where((r) => r > 0x2000 && r != 0x00E9), isEmpty, reason: 'quedaron runas: ${v.runes.toList()}');
        });
      }

      test('solo emojis → null', () {
        expect(validateSpaceName('🇵🇪👍🏽').value, isNull);
      });

      test('no toca letras con tilde, ñ ni signos', () {
        expect(validateSpaceName('Ñandú #1 (2026)').value, 'Ñandú #1 (2026)');
      });
    });

    test('30 caracteres OK, 31 es error (cuenta caracteres visibles)', () {
      expect(validateSpaceName('ñ' * 30).error, isNull);
      expect(validateSpaceName('ñ' * 31).error, 'Máximo 30 caracteres');
    });
  });

  testWidgets('paso 1 renderiza 4 opciones y no muestra Omitir', (tester) async {
    await pumpOnboarding(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.byType(ChoiceCard), findsNWidgets(4));
    expect(find.text('Omitir'), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('elegir opción avanza al paso 2', (tester) async {
    await pumpOnboarding(tester);
    await choose(tester, 'Variables');
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('Omitir'), findsOneWidget);
    expect(find.text('1 / 2'), findsNothing);
  });

  testWidgets('volver al paso 1 conserva la elección con check', (tester) async {
    await pumpOnboarding(tester);
    await choose(tester, 'Mixtos');
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(checkIn('Mixtos'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('back del sistema en el paso 2 vuelve al paso 1', (tester) async {
    await pumpOnboarding(tester);
    await choose(tester, 'Estables');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    expect(checkIn('Estables'), findsOneWidget);
  });

  testWidgets('elegir otra opción al volver mueve el check y avanza', (tester) async {
    await pumpOnboarding(tester);
    await choose(tester, 'Estables');
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    await choose(tester, 'Sin ingreso fijo ahora');
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(checkIn('Estables'), findsNothing);
    expect(checkIn('Sin ingreso fijo ahora'), findsOneWidget);
  });

  testWidgets('Empezar guarda settings con nombre limpio y defaults', (tester) async {
    final db = await pumpOnboarding(tester);
    await choose(tester, 'Variables');
    await tester.enterText(find.byType(TextField), '  Casa 🏠 ');
    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();
    final s = await db.select(db.settings).getSingle();
    expect(s.mode, Mode.variable);
    expect(s.spaceName, 'Casa');
    expect(s.onboardingDone, isTrue);
    expect(s.runwayWindowDays, 14);
    expect(s.incomeWindowDays, 30);
  });

  testWidgets('Empezar con nombre vacío guarda null sin error', (tester) async {
    final db = await pumpOnboarding(tester);
    await choose(tester, 'Estables');
    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();
    final s = await db.select(db.settings).getSingle();
    expect(s.spaceName, isNull);
    expect(s.mode, Mode.stable);
  });

  testWidgets('Omitir guarda sin nombre aunque haya texto escrito', (tester) async {
    final db = await pumpOnboarding(tester);
    await choose(tester, 'Sin ingreso fijo ahora');
    await tester.enterText(find.byType(TextField), 'Casa');
    await tester.tap(find.text('Omitir'));
    await tester.pumpAndSettle();
    final s = await db.select(db.settings).getSingle();
    expect(s.spaceName, isNull);
    expect(s.mode, Mode.survival);
    expect(s.onboardingDone, isTrue);
  });

  testWidgets('más de 30 caracteres: error inline y no guarda', (tester) async {
    final db = await pumpOnboarding(tester);
    await choose(tester, 'Variables');
    await tester.enterText(find.byType(TextField), 'a' * 31);
    await tester.pump();
    expect(find.text('Máximo 30 caracteres'), findsOneWidget);
    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();
    expect(await db.select(db.settings).getSingleOrNull(), isNull);
  });
}
