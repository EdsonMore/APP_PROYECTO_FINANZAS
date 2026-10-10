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
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import '../home/home_screen_test.dart' as h;

/// Abre Presupuesto encima de una pantalla vacía (para que "volver" tenga adónde ir).
Future<void> pumpBudget(WidgetTester tester, h.Seed seed, {ThemeData? theme}) async {
  const dpr = 2.625;
  tester.view.physicalSize = const Size(411, 914) * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  addTearDown(seed.db.close);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(seed.db),
      sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      todayProvider.overrideWithValue(h.today),
    ],
    child: MaterialApp(
      theme: theme ?? AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BudgetScreen())),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('abrir'));
  await tester.pumpAndSettle();
}

/// 4 categorías con techo (Transporte pasada) y Ocio con gasto sin techo.
Future<h.Seed> withCaps() => h.seeded(Mode.stable, (s) async {
      await s.budget('comida', 15000);
      await s.budget('transporte', 9000);
      await s.budget('vivienda', 35000);
      await s.budget('salud', 6000);
      await s.expense(120, h.ago(1));
      await s.expense(105, h.ago(2), cat: 'transporte');
      await s.expense(350, h.ago(3), cat: 'vivienda');
      await s.expense(20, h.ago(4), cat: 'salud');
      await s.expense(30, h.ago(5), cat: 'ocio');
    });

Finder row(String id) => find.byKey(Key('budget.row.$id'));
double top(WidgetTester tester, String id) => tester.getTopLeft(row(id)).dy;

/// Colores de relleno pintados dentro de una barra (el carril incluido).
Iterable<Color> fills(WidgetTester tester, String key) => tester
    .widgetList<ColoredBox>(find.descendant(of: find.byKey(Key(key)), matching: find.byType(ColoredBox)))
    .map((b) => b.color);

Future<Map<String, int>> caps(h.Seed s) async =>
    {for (final b in await s.db.select(s.db.budgets).get()) b.categoryId: b.capCents};

Future<void> type(WidgetTester tester, String keys) async {
  for (final k in keys.split('')) {
    await tester.tap(find.byKey(Key(k == '<' ? 'key.backspace' : 'key.$k')));
    await tester.pump();
  }
}

FilledButton saveButton(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('budget.sheet.save')));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  testWidgets('vacío: texto, "Definir presupuestos" abre la hoja de la categoría con más gasto del mes', (tester) async {
    final seed = await h.seeded(Mode.stable, (s) async {
      await s.expense(30, h.ago(1));
      await s.expense(80, h.ago(2), cat: 'ocio');
    });
    await pumpBudget(tester, seed);
    expect(tester.takeException(), isNull);
    expect(find.text('Presupuesto'), findsOneWidget);
    expect(find.text('Octubre'), findsOneWidget);
    expect(find.text('Ponle un techo a lo que más gastas y te aviso cuando te acerques.'), findsOneWidget);
    expect(find.byKey(const Key('budget.total')), findsNothing);
    // Sugeridos como filas debajo del botón.
    expect(find.byKey(const Key('budget.use.ocio')), findsOneWidget);
    expect(find.byKey(const Key('budget.use.comida')), findsOneWidget);
    expect(top(tester, 'ocio'), lessThan(top(tester, 'comida')), reason: 'sin techo: por gasto del mes desc');

    await tester.tap(find.byKey(const Key('budget.define')));
    await tester.pumpAndSettle();
    final sheet = find.byKey(const Key('budget.sheet'));
    expect(find.descendant(of: sheet, matching: find.text('Ocio')), findsOneWidget);
    // Precargado con el sugerido: el chip no se muestra porque es igual.
    expect(find.byKey(const Key('budget.sheet.suggested')), findsNothing);
    expect(saveButton(tester).onPressed, isNotNull);
    expect(find.byKey(const Key('budget.sheet.remove')), findsNothing, reason: 'sin techo no hay "Quitar"');
    await h.unmount(tester);
  });

  testWidgets('vacío y sin ningún gasto: el botón abre la primera activa (Comida)', (tester) async {
    await pumpBudget(tester, await h.seeded(Mode.stable));
    expect(find.byKey(const Key('budget.empty')), findsOneWidget);
    expect(find.textContaining('Sin techo'), findsNothing, reason: 'sin gasto en 90 días no se lista nada');
    await tester.tap(find.byKey(const Key('budget.define')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('budget.sheet')), matching: find.text('Comida')), findsOneWidget);
    expect(saveButton(tester).onPressed, isNull, reason: 'sin techo ni sugerido: monto vacío');
    await h.unmount(tester);
  });

  testWidgets('con techos: total con todo el gasto del mes, "Incluye…", orden por % usado desc', (tester) async {
    await pumpBudget(tester, await withCaps());
    expect(tester.takeException(), isNull);
    // 625 gastados (incluye los 30 de Ocio) contra 650 de techos.
    expect(find.textContaining('S/ 625.00', findRichText: true), findsOneWidget);
    expect(find.textContaining('de S/ 650.00', findRichText: true), findsOneWidget);
    expect(find.text('Quedan S/ 25.00'), findsOneWidget);
    expect(find.text('Incluye S/ 30.00 de categorías sin techo'), findsOneWidget);

    // Transporte 116 % > Vivienda 100 % > Comida 80 % > Salud 33 %; luego Ocio sin techo.
    final order = ['transporte', 'vivienda', 'comida', 'salud', 'ocio'];
    for (var i = 1; i < order.length; i++) {
      expect(top(tester, order[i - 1]), lessThan(top(tester, order[i])), reason: '${order[i - 1]} antes que ${order[i]}');
    }
    expect(find.text('Sin techo'), findsOneWidget);
    expect(find.textContaining('S/ 120.00', findRichText: true), findsOneWidget);
    expect(find.textContaining('/ S/ 150.00', findRichText: true), findsOneWidget);
    // Sin gasto en 90 días y sin techo: no aparece.
    expect(row('otros'), findsNothing);
    // Cada barra lleva el color de su categoría.
    expect(fills(tester, 'budget.bar.comida'), contains(categoryLight[0]));
    expect(fills(tester, 'budget.bar.vivienda'), contains(categoryLight[2]));
    await h.unmount(tester);
  });

  testWidgets('categoría pasada: barra llena en expenseFg + ícono + "S/ 15.00 de más" en expenseFg', (tester) async {
    await pumpBudget(tester, await withCaps());
    final p = Palette.light;
    expect(fills(tester, 'budget.bar.transporte'), contains(p.expenseFg));
    expect(fills(tester, 'budget.bar.transporte'), isNot(contains(categoryLight[1])), reason: 'el lago no se pinta');
    final over = find.byKey(const Key('budget.over.transporte'));
    expect(find.descendant(of: over, matching: find.byIcon(Icons.error_outline)), findsOneWidget);
    expect(tester.widget<Icon>(find.descendant(of: over, matching: find.byIcon(Icons.error_outline))).color, p.expenseFg);
    expect(tester.widget<Text>(find.descendant(of: over, matching: find.text('S/ 15.00 de más'))).style!.color, p.expenseFg);
    // Vivienda justo en el techo (100 %): no está pasada.
    expect(find.byKey(const Key('budget.over.vivienda')), findsNothing);
    await h.unmount(tester);
  });

  testWidgets('total pasado: "por encima" con ícono, barra total en expenseFg', (tester) async {
    await pumpBudget(
        tester,
        await h.seeded(Mode.stable, (s) async {
          await s.budget('comida', 10000);
          await s.expense(140, h.ago(1));
        }));
    expect(find.byKey(const Key('budget.totalOver')), findsOneWidget);
    expect(find.text('S/ 40.00 por encima'), findsOneWidget);
    expect(find.textContaining('Quedan'), findsNothing);
    expect(fills(tester, 'budget.totalBar'), contains(Palette.light.expenseFg));
    await h.unmount(tester);
  });

  testWidgets('[Usar] guarda el sugerido y la fila pasa a "con techo"', (tester) async {
    final seed = await withCaps();
    await pumpBudget(tester, seed);
    expect(find.byKey(const Key('budget.bar.ocio')), findsNothing);
    final suggested = suggestedCaps([for (final e in await seed.db.select(seed.db.entries).get()) e.toMovement()],
        today: h.today)['ocio']!;
    await tester.ensureVisible(find.byKey(const Key('budget.use.ocio')));
    await tester.tap(find.byKey(const Key('budget.use.ocio')));
    await tester.pumpAndSettle();
    expect((await caps(seed))['ocio'], suggested);
    expect(find.byKey(const Key('budget.bar.ocio')), findsOneWidget);
    expect(find.text('Sin techo'), findsNothing);
    expect(find.textContaining('Incluye'), findsNothing, reason: 'ya no hay gasto fuera de techos');
    await h.unmount(tester);
  });

  testWidgets('hoja: precarga el techo, chip del sugerido, Guardar deshabilitado con 0, guarda y quita', (tester) async {
    final seed = await withCaps();
    await pumpBudget(tester, seed);
    await tester.tap(row('comida'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('Monto: S/ 150.00'), findsOneWidget);
    // El sugerido de Comida (S/ 120 en 6 días efectivos → S/ 600) ≠ 150: hay chip.
    expect(find.byKey(const Key('budget.sheet.suggested')), findsOneWidget);
    expect(find.byKey(const Key('budget.sheet.remove')), findsOneWidget);

    await type(tester, '<<<');
    expect(saveButton(tester).onPressed, isNull, reason: 'monto vacío');
    await type(tester, '0');
    expect(saveButton(tester).onPressed, isNull, reason: 'S/ 0 no es un techo');
    await type(tester, '<200');
    await tester.tap(find.byKey(const Key('budget.sheet.save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('budget.sheet')), findsNothing);
    expect((await caps(seed))['comida'], 20000);

    await tester.tap(row('comida'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('budget.sheet.suggested')));
    await tester.pump();
    expect(find.byKey(const Key('budget.sheet.suggested')), findsNothing, reason: 'ya es igual al sugerido');
    await tester.tap(find.byKey(const Key('budget.sheet.remove')));
    await tester.pumpAndSettle();
    expect((await caps(seed)).containsKey('comida'), isFalse);
    expect(find.byKey(const Key('budget.bar.comida')), findsNothing, reason: 'pasa a "sin techo"');
    expect(row('comida'), findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('archivada no aparece (ni su techo suma) aunque tenga gasto', (tester) async {
    final seed = await withCaps();
    await seed.db.setArchived(EntryKind.expense, 'salud', archived: true);
    await seed.db.setArchived(EntryKind.expense, 'ocio', archived: true);
    await pumpBudget(tester, seed);
    expect(row('salud'), findsNothing);
    expect(row('ocio'), findsNothing);
    // Techos activos: 150 + 90 + 350 = 590. El gasto de archivadas sigue siendo gasto.
    expect(find.textContaining('de S/ 590.00', findRichText: true), findsOneWidget);
    expect(find.text('Incluye S/ 50.00 de categorías sin techo'), findsOneWidget);
    expect((await caps(seed))['salud'], 6000, reason: 'el techo queda guardado');
    await h.unmount(tester);
  });

  testWidgets('si el modo deja de ser Estable con la pantalla abierta, vuelve atrás', (tester) async {
    final seed = await withCaps();
    await pumpBudget(tester, seed);
    await seed.db.setMode(Mode.variable);
    await tester.pumpAndSettle();
    expect(find.byType(BudgetScreen), findsNothing);
    expect(find.text('abrir'), findsOneWidget);
    expect(await caps(seed), hasLength(4), reason: 'cambiar de modo no borra techos');
    await h.unmount(tester);
  });

  testWidgets('tema oscuro: barras con el color oscuro de la categoría', (tester) async {
    await pumpBudget(tester, await withCaps(), theme: AppTheme.dark);
    expect(tester.takeException(), isNull);
    expect(fills(tester, 'budget.bar.comida'), contains(categoryDark[0]));
    expect(fills(tester, 'budget.bar.transporte'), contains(Palette.dark.expenseFg));
    await h.unmount(tester);
  });
}
