import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/app.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/data/providers.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/entry/draft_store.dart';
import 'package:saldo_claro/features/settings/appearance.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// La app real (Home), con las preferencias que haya en "disco".
Future<void> pumpApp(WidgetTester tester, Map<String, Object> prefs) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues(prefs);
  SharedPreferences.resetStatic(); // proceso nuevo: se relee del disco
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  await db.completeOnboarding(mode: Mode.variable);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
    ],
    child: const App(),
  ));
  await tester.pumpAndSettle();
}

ThemeMode themeOf(WidgetTester tester) => tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode!;

Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(Duration.zero);
}

void main() {
  setUpAll(() => initializeDateFormatting('es_PE'));

  testWidgets('por defecto sigue al sistema y Ajustes lo dice', (tester) async {
    await pumpApp(tester, {});
    expect(themeOf(tester), ThemeMode.system);
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('settings.appearance')), matching: find.text('Sistema')),
        findsOneWidget);
    await unmount(tester);
  });

  testWidgets('elegir Oscuro aplica al instante, se guarda y la fila cambia', (tester) async {
    await pumpApp(tester, {});
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings.appearance')));
    await tester.pumpAndSettle();
    expect(find.text('Apariencia'), findsWidgets);
    expect(find.text('Sigue el modo claro u oscuro de tu teléfono.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('choice.ThemeMode.dark')));
    await tester.pumpAndSettle();
    expect(themeOf(tester), ThemeMode.dark);
    expect((await SharedPreferences.getInstance()).getString(themeModeKey), 'dark');
    expect(find.descendant(of: find.byKey(const Key('settings.appearance')), matching: find.text('Oscuro')),
        findsOneWidget);
    await unmount(tester);
  });

  testWidgets('se recuerda al reabrir la app', (tester) async {
    await pumpApp(tester, {themeModeKey: 'light'});
    expect(themeOf(tester), ThemeMode.light);
    await unmount(tester);
  });

  testWidgets('un valor raro en disco cuenta como Sistema', (tester) async {
    await pumpApp(tester, {themeModeKey: 'violeta'});
    expect(themeOf(tester), ThemeMode.system);
    await unmount(tester);
  });
}
