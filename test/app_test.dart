import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/app.dart';
import 'package:saldo_claro/core/theme/tokens.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/data/providers.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/home/home_screen.dart';

Future<AppDatabase> pumpApp(WidgetTester tester, {AppDatabase? db}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final d = db ?? AppDatabase(NativeDatabase.memory());
  addTearDown(d.close);
  await tester.pumpWidget(ProviderScope(overrides: [databaseProvider.overrideWithValue(d)], child: const App()));
  await tester.pumpAndSettle();
  return d;
}

/// Desmonta la app y drena el timer que drift agenda al cancelar el stream de
/// settings; si no, flutter_test falla con "A Timer is still pending".
void appTest(String description, Future<void> Function(WidgetTester) body) {
  testWidgets(description, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}

void main() {
  setUpAll(() => initializeDateFormatting('es_PE'));

  appTest('primer arranque va al Onboarding', (tester) async {
    await pumpApp(tester);
    expect(find.text('¿Cómo son tus ingresos?'), findsOneWidget);
  });

  appTest('onboarding terminado va a Home', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.settings).insert(
        SettingsCompanion.insert(id: const Value(1), mode: Mode.survival, onboardingDone: const Value(true)));
    await pumpApp(tester, db: db);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  // Integración con drift: la elección del paso 1 llega mapeada a settings.mode.
  for (final (label, mode) in [
    ('Estables', Mode.stable),
    ('Variables', Mode.variable),
    ('Mixtos', Mode.variable),
    ('Sin ingreso fijo ahora', Mode.survival),
  ]) {
    appTest('"$label" + Empezar → mode=${mode.name}, onboarding_done y pasa al Home', (tester) async {
      final db = await pumpApp(tester);
      await tester.tap(find.text(label));
      await tester.pump(Motion.lightChange);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Empezar'));
      await tester.pumpAndSettle();
      final s = await db.select(db.settings).getSingle();
      expect(s.mode, mode);
      expect(s.onboardingDone, isTrue);
      expect(find.byType(HomeScreen), findsOneWidget);
    });
  }
}
