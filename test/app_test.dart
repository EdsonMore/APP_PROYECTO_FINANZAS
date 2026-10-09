import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/app.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/data/providers.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:drift/drift.dart' show Value;

Future<void> pumpApp(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [databaseProvider.overrideWithValue(db)],
    child: const App(),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('primer arranque va a Onboarding', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await pumpApp(tester, db);
    expect(find.text('Onboarding — Fase 1b'), findsOneWidget);
    await db.close();
  });

  testWidgets('onboarding terminado va a Home', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.into(db.settings).insert(
        SettingsCompanion.insert(id: const Value(1), mode: Mode.survival, onboardingDone: const Value(true)));
    await pumpApp(tester, db);
    expect(find.text('Home — Fase 1b'), findsOneWidget);
    await db.close();
  });
}
