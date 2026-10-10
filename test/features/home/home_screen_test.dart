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
import 'package:saldo_claro/features/budget/budget_screen.dart';
import 'package:saldo_claro/features/entry/draft_store.dart';
import 'package:saldo_claro/features/home/home_blocks.dart';
import 'package:saldo_claro/features/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';

final today = day(2026, 10, 8);
DateTime ago(int n) => today.subtract(Duration(days: n));
var _n = 0;

/// Base en memoria con settings y movimientos ya cargados.
class Seed {
  Seed(this.mode);
  final Mode mode;
  final db = AppDatabase(NativeDatabase.memory());

  Future<void> expense(int soles, DateTime d, {String cat = 'comida'}) => db.insertManualEntry(
      id: 'x${_n++}', kind: EntryKind.expense, amountCents: soles * 100, day: d, pickId: cat, now: DateTime(2026, 10, 8, 0, 0, _n));

  Future<void> income(int soles, DateTime d) => db.insertManualEntry(
      id: 'x${_n++}', kind: EntryKind.income, amountCents: soles * 100, day: d, pickId: 'chamba', now: DateTime(2026, 10, 8, 0, 0, _n));

  Future<void> budget(String cat, int cents) => db.into(db.budgets).insert(BudgetsCompanion.insert(categoryId: cat, capCents: cents));

  /// 14 días con S/ 10 de gasto diario y S/ 1,000 de ingreso → runway ~86 días.
  Future<void> twoWeeks() async {
    await income(1000, ago(13));
    for (var i = 0; i < 14; i++) {
      await expense(10, ago(i));
    }
  }
}

Future<Seed> seeded(Mode mode, [Future<void> Function(Seed s)? fill]) async {
  final s = Seed(mode);
  await s.db.completeOnboarding(mode: mode);
  if (fill != null) await fill(s);
  return s;
}

Future<void> pumpHome(WidgetTester tester, Seed seed, {Size size = const Size(411, 914), ThemeData? theme}) async {
  const dpr = 2.625;
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  addTearDown(seed.db.close);
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(seed.db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      todayProvider.overrideWithValue(today),
    ],
    child: MaterialApp(theme: theme ?? AppTheme.light, home: const HomeScreen()),
  ));
  await tester.pumpAndSettle();
}

/// Desmonta y drena el timer que drift agenda al cancelar los streams.
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

double width(WidgetTester tester, String key) => tester.getSize(find.byKey(Key(key))).width;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  group('por modo', () {
    testWidgets('sin datos: bienvenida, semáforo gris, sin top ni recientes, sin botón central', (tester) async {
      await pumpHome(tester, await seeded(Mode.stable));
      expect(tester.takeException(), isNull);
      expect(find.text('Mis cuentas'), findsOneWidget);
      expect(find.text('Empecemos'), findsOneWidget);
      expect(find.text('Aún sin movimientos'), findsOneWidget);
      expect(find.text('Entró S/ 0.00 · Salió S/ 0.00'), findsOneWidget);
      expect(find.byKey(const Key('home.top')), findsNothing);
      expect(find.byKey(const Key('home.recents')), findsNothing);
      expect(find.text('Registrar mi primer gasto'), findsNothing); // decisión C
      expect(find.byKey(const Key('home.cta.expense')), findsOneWidget);
      expect(find.byKey(const Key('home.cta.income')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('Estable con techos y datos: "Te queda", barra, CTAs del mismo ancho', (tester) async {
      await pumpHome(
          tester,
          await seeded(Mode.stable, (s) async {
            await s.budget('comida', 50000);
            await s.budget('ocio', 30000);
            await s.income(1000, day(2026, 10, 1));
            await s.expense(160, ago(1));
          }));
      expect(find.text('Te queda'), findsOneWidget);
      expect(find.text('S/ 640.00'), findsOneWidget);
      expect(find.text('del presupuesto de octubre'), findsOneWidget);
      expect(find.byKey(const Key('home.budgetBar')), findsOneWidget);
      expect(find.text('Entra más que sale'), findsOneWidget);
      expect(find.text('En qué se va'), findsOneWidget);
      expect(find.text('Recientes'), findsOneWidget);
      expect(width(tester, 'home.cta.expense'), width(tester, 'home.cta.income'));
      await unmount(tester);
    });

    testWidgets('Estable sin techos y datos: "Gastaste S/ X" + runway, sin barra', (tester) async {
      await pumpHome(tester, await seeded(Mode.stable, (s) => s.twoWeeks()));
      expect(find.text('Gastaste'), findsOneWidget);
      expect(find.text('S/ 80.00'), findsOneWidget);
      expect(find.text('en octubre. Te alcanza para ~86 días.'), findsOneWidget);
      expect(find.byKey(const Key('home.budgetBar')), findsNothing);
      await unmount(tester);
    });

    testWidgets('Variable con datos: "~86 días" + ingreso típico y gasto 30d', (tester) async {
      await pumpHome(tester, await seeded(Mode.variable, (s) => s.twoWeeks()));
      expect(find.text('Te alcanza para'), findsOneWidget);
      expect(find.text('~86 días'), findsOneWidget);
      expect(find.textContaining('Ingreso típico 30d', findRichText: true), findsOneWidget);
      expect(find.textContaining('S/ 2,142.86', findRichText: true), findsOneWidget);
      expect(width(tester, 'home.cta.expense'), width(tester, 'home.cta.income'));
      await unmount(tester);
    });

    testWidgets('Supervivencia con datos: gasto diario y "+ Ingreso" más grande', (tester) async {
      await pumpHome(tester, await seeded(Mode.survival, (s) => s.twoWeeks()));
      expect(find.text('~86 días'), findsOneWidget);
      expect(find.text('Gastas ~S/ 10.00 al día.'), findsOneWidget);
      final income = width(tester, 'home.cta.income');
      final expense = width(tester, 'home.cta.expense');
      expect(income, greaterThan(expense));
      expect(income / expense, closeTo(1.5, 0.01)); // 3/5 vs 2/5
      await unmount(tester);
    });
  });

  group('presupuesto en el Home (1c)', () {
    Iterable<Color> barFills(WidgetTester tester) => tester
        .widgetList<ColoredBox>(
            find.descendant(of: find.byKey(const Key('home.budgetBar')), matching: find.byType(ColoredBox)))
        .map((b) => b.color);

    testWidgets('barra en ink; pasado del techo → expenseFg, nunca ámbar (D3)', (tester) async {
      final seed = await seeded(Mode.stable, (s) async {
        await s.budget('comida', 50000);
        await s.income(1000, day(2026, 10, 1));
        await s.expense(160, ago(1));
      });
      await pumpHome(tester, seed);
      expect(barFills(tester), contains(Palette.light.ink));
      expect(barFills(tester), isNot(contains(Palette.light.expenseFg)));

      await seed.expense(400, ago(1)); // 560 de 500
      await tester.pumpAndSettle();
      expect(find.text('Te pasaste por'), findsOneWidget);
      expect(barFills(tester), contains(Palette.light.expenseFg));
      expect(barFills(tester), isNot(contains(Palette.light.amberFg)));
      await unmount(tester);
    });

    testWidgets('tocar el bloque de presupuesto abre Presupuesto', (tester) async {
      await pumpHome(
          tester,
          await seeded(Mode.stable, (s) async {
            await s.budget('comida', 50000);
            await s.income(1000, day(2026, 10, 1));
            await s.expense(160, ago(1));
          }));
      await tester.tap(find.text('Te queda'));
      await tester.pumpAndSettle();
      expect(find.byType(BudgetScreen), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('sin ingreso en el mes ("Gastaste"): el bloque no abre nada', (tester) async {
      await pumpHome(
          tester,
          await seeded(Mode.stable, (s) async {
            await s.budget('comida', 50000);
            await s.expense(160, ago(1));
          }));
      await tester.tap(find.text('Gastaste'));
      await tester.pumpAndSettle();
      expect(find.byType(BudgetScreen), findsNothing);
      await unmount(tester);
    });
  });

  group('C1: el número cabe en una línea', () {
    testWidgets('"S/ 999,999.99" a 320 dp de ancho no desborda y baja de 52 sp', (tester) async {
      await pumpHome(
          tester,
          await seeded(Mode.stable, (s) async {
            await s.budget('comida', 99999999);
            await s.income(1, day(2026, 10, 1));
          }),
          size: const Size(320, 640));
      expect(tester.takeException(), isNull, reason: 'overflow');
      expect(find.text('S/ 999,999.99'), findsOneWidget);
      final value = tester.widget<Text>(find.byKey(const Key('home.value')));
      expect(value.style!.fontSize, lessThan(52));
      expect(value.style!.fontSize, greaterThanOrEqualTo(36));
      expect(width(tester, 'home.value'), lessThanOrEqualTo(320 - 2 * 20));
      await unmount(tester);
    });

    testWidgets('un monto corto se queda en 52 sp', (tester) async {
      await pumpHome(tester, await seeded(Mode.variable, (s) => s.twoWeeks()), size: const Size(320, 640));
      expect(tester.widget<Text>(find.byKey(const Key('home.value'))).style!.fontSize, 52);
      await unmount(tester);
    });

    test('escalera 52 → 44 → 36 y nunca menos de 36', () {
      const scaler = TextScaler.noScaling;
      expect(FitDisplayText.sizeFor('~23 días', 280, scaler), 52);
      final big = FitDisplayText.sizeFor('S/ 999,999.99', 280, scaler);
      expect([44.0, 36.0], contains(big));
      expect(FitDisplayText.sizeFor('S/ 999,999.99 S/ 999,999.99', 280, scaler), 36);
    });
  });

  group('contexto bajo el runway', () {
    /// Gasto de S/ 1 diario por 14 días + ingreso: runway = ingreso − 14 días.
    Future<void> runwayOf(Seed s, int days) async {
      await s.income(days + 14, ago(13));
      for (var i = 0; i < 14; i++) {
        await s.expense(1, ago(i));
      }
    }

    Color contextColor(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('home.context'))).style!.color!;

    testWidgets('Supervivencia con 5 días: "Son menos de 7 días." en expenseFg', (tester) async {
      await pumpHome(tester, await seeded(Mode.survival, (s) => runwayOf(s, 5)));
      expect(find.text('Son menos de 7 días.'), findsOneWidget);
      expect(contextColor(tester), Palette.light.expenseFg);
      await unmount(tester);
    });

    testWidgets('Variable con 20 días: "Menos de un mes." en inkMuted', (tester) async {
      await pumpHome(tester, await seeded(Mode.variable, (s) => runwayOf(s, 20)));
      expect(find.text('Menos de un mes.'), findsOneWidget);
      expect(contextColor(tester), Palette.light.inkMuted);
      await unmount(tester);
    });

    testWidgets('Variable con 45 días: sin texto', (tester) async {
      await pumpHome(tester, await seeded(Mode.variable, (s) => runwayOf(s, 45)));
      expect(find.byKey(const Key('home.context')), findsNothing);
      await unmount(tester);
    });

    testWidgets('Supervivencia sin colchón: "Registra un ingreso para activar el cálculo." en inkMuted', (tester) async {
      await pumpHome(tester, await seeded(Mode.survival, (s) => s.expense(50, ago(1))));
      expect(find.text('Registra un ingreso para activar el cálculo.'), findsOneWidget);
      expect(contextColor(tester), Palette.light.inkMuted);
      await unmount(tester);
    });

    testWidgets('Estable con 5 días: sin texto', (tester) async {
      await pumpHome(tester, await seeded(Mode.stable, (s) => runwayOf(s, 5)));
      expect(find.byKey(const Key('home.context')), findsNothing);
      await unmount(tester);
    });
  });

  group('Deshacer', () {
    Future<void> saveExpense(WidgetTester tester, String keys) async {
      await tester.tap(find.byKey(const Key('home.cta.expense')));
      await tester.pumpAndSettle();
      for (final k in keys.split('')) {
        await tester.tap(find.byKey(Key('key.$k')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const Key('entry.save')));
      await tester.pumpAndSettle();
    }

    testWidgets('guardar → el Home se actualiza → Deshacer hace DELETE real → "Movimiento eliminado" 2 s',
        (tester) async {
      final seed = await seeded(Mode.variable);
      await pumpHome(tester, seed);
      await saveExpense(tester, '12');

      expect(find.text('Gasto de S/ 12.00 guardado'), findsOneWidget);
      expect(await seed.db.select(seed.db.entries).get(), hasLength(1));
      expect(find.byKey(const Key('home.recents')), findsOneWidget, reason: 'reactivo: aparece sin recargar');

      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect(await seed.db.select(seed.db.entries).get(), isEmpty, reason: 'DELETE real');
      expect(find.text('Movimiento eliminado'), findsOneWidget);
      expect(find.byKey(const Key('home.recents')), findsNothing);
      expect(find.text('Empecemos'), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(find.text('Movimiento eliminado'), findsNothing);
      await unmount(tester);
    });

    testWidgets('sin tocar Deshacer, el aviso se va solo a los 4 s y el movimiento queda', (tester) async {
      final seed = await seeded(Mode.variable);
      await pumpHome(tester, seed);
      await saveExpense(tester, '7');
      await tester.pump(const Duration(milliseconds: 3900));
      expect(find.text('Gasto de S/ 7.00 guardado'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.text('Gasto de S/ 7.00 guardado'), findsNothing);
      expect(await seed.db.select(seed.db.entries).get(), hasLength(1));
      await unmount(tester);
    });

    testWidgets('deslizar hacia abajo lo cierra sin borrar ni mostrar "Movimiento eliminado" (C3)', (tester) async {
      final seed = await seeded(Mode.variable);
      await pumpHome(tester, seed);
      await saveExpense(tester, '9');
      await tester.drag(find.byKey(const Key('home.undoSnack')), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home.undoSnack')), findsNothing);
      expect(find.text('Movimiento eliminado'), findsNothing);
      expect(await seed.db.select(seed.db.entries).get(), hasLength(1));
      await unmount(tester);
    });
  });
}
