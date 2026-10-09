import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
import 'package:saldo_claro/data/providers.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/entry/draft_store.dart';
import 'package:saldo_claro/features/home/home_screen.dart';
import 'package:saldo_claro/features/settings/about_screen.dart';
import 'package:saldo_claro/features/settings/csv_exporter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import '../home/home_screen_test.dart' as h;

/// Lo que recibió el exportador simulado.
class ExportCall {
  String? csv;
  String? fileName;
  int calls = 0;
}

Future<ExportCall> pumpApp(WidgetTester tester, h.Seed seed, {Size size = const Size(411, 914)}) async {
  const dpr = 2.625;
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  addTearDown(seed.db.close);
  final export = ExportCall();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(seed.db),
      sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      todayProvider.overrideWithValue(h.today),
      csvExporterProvider.overrideWithValue((csv, fileName) async {
        export
          ..calls += 1
          ..csv = csv
          ..fileName = fileName;
      }),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
  ));
  await tester.pumpAndSettle();
  return export;
}

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Ajustes'));
  await tester.pumpAndSettle();
}

Future<void> tapRow(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key('settings.$key')));
  await tester.tap(find.byKey(Key('settings.$key')));
  await tester.pumpAndSettle();
}

/// El valor actual de una fila (segunda línea).
Finder rowValue(String key, String value) =>
    find.descendant(of: find.byKey(Key('settings.$key')), matching: find.text(value));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  testWidgets('muestra los valores actuales', (tester) async {
    await pumpApp(tester, await h.seeded(Mode.variable));
    await openSettings(tester);
    expect(find.text('Ajustes'), findsOneWidget);
    expect(rowValue('mode', 'Variable'), findsOneWidget);
    expect(rowValue('name', 'Mis cuentas'), findsOneWidget);
    expect(rowValue('opening', 'Sin definir'), findsOneWidget);
    expect(rowValue('runway', '14 días'), findsOneWidget);
    expect(rowValue('categories', '6 activas'), findsOneWidget);
    expect(rowValue('sources', '5 activas'), findsOneWidget);
    expect(rowValue('export', 'Todavía no hay movimientos'), findsOneWidget);
    expect(rowValue('about', 'Versión 0.1.0'), findsOneWidget);
    await h.unmount(tester);
  });

  group('modo', () {
    testWidgets('3 opciones con "Supervivencia" y la explicación (C1, C2, decisión f)', (tester) async {
      await pumpApp(tester, await h.seeded(Mode.variable));
      await openSettings(tester);
      await tapRow(tester, 'mode');
      expect(find.text('Estable'), findsOneWidget);
      expect(find.text('Variable'), findsNWidgets(2)); // opción + valor de la fila
      expect(find.text('Supervivencia'), findsOneWidget);
      expect(find.text('Mixtos'), findsNothing);
      expect(find.textContaining('Al cambiar el modo, el Home se reorganiza'), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('cambiar a Supervivencia escribe el modo al instante y el Home se recalcula', (tester) async {
      final seed = await h.seeded(Mode.variable, (s) => s.twoWeeks());
      await pumpApp(tester, seed);
      expect(find.textContaining('Ingreso típico 30d', findRichText: true), findsOneWidget);
      await openSettings(tester);
      await tapRow(tester, 'mode');
      await tester.tap(find.byKey(const Key('choice.Mode.survival')));
      await tester.pumpAndSettle();

      expect((await seed.db.select(seed.db.settings).getSingle()).mode, Mode.survival);
      expect(rowValue('mode', 'Supervivencia'), findsOneWidget);
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(find.text('Gastas ~S/ 10.00 al día.'), findsOneWidget);
      await h.unmount(tester);
    });
  });

  group('nombre', () {
    Future<void> rename(WidgetTester tester, String text) async {
      await tapRow(tester, 'name');
      await tester.enterText(find.byKey(const Key('name.field')), text);
      await tester.pump();
    }

    testWidgets('conserva emojis y quita espacios; la fila lo muestra', (tester) async {
      final seed = await h.seeded(Mode.variable);
      await pumpApp(tester, seed);
      await openSettings(tester);
      await rename(tester, '  Casa 🏠 ');
      await tester.tap(find.byKey(const Key('name.save')));
      await tester.pumpAndSettle();
      expect((await seed.db.select(seed.db.settings).getSingle()).spaceName, 'Casa 🏠');
      expect(rowValue('name', 'Casa 🏠'), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('31 caracteres: error inline y no guarda', (tester) async {
      final seed = await h.seeded(Mode.variable);
      await pumpApp(tester, seed);
      await openSettings(tester);
      await rename(tester, 'a' * 31);
      expect(find.text('Máximo 30 caracteres'), findsOneWidget);
      await tester.tap(find.byKey(const Key('name.save')));
      await tester.pumpAndSettle();
      expect((await seed.db.select(seed.db.settings).getSingle()).spaceName, isNull);
      await h.unmount(tester);
    });

    testWidgets('vacío guarda null y vuelve "Mis cuentas"', (tester) async {
      final seed = await h.seeded(Mode.variable);
      await seed.db.setSpaceName('Casa');
      await pumpApp(tester, seed);
      await openSettings(tester);
      await rename(tester, '   ');
      await tester.tap(find.byKey(const Key('name.save')));
      await tester.pumpAndSettle();
      expect((await seed.db.select(seed.db.settings).getSingle()).spaceName, isNull);
      expect(rowValue('name', 'Mis cuentas'), findsOneWidget);
      await h.unmount(tester);
    });
  });

  testWidgets('saldo inicial abre la hoja existente y la fila muestra el monto guardado', (tester) async {
    final seed = await h.seeded(Mode.variable);
    await pumpApp(tester, seed);
    await openSettings(tester);
    await tapRow(tester, 'opening');
    expect(find.byKey(const Key('opening.sheet')), findsOneWidget);
    for (final k in '500'.split('')) {
      await tester.tap(find.byKey(Key('key.$k')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const Key('opening.save')));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('settings.opening')), matching: find.textContaining('S/ 500.00 · desde')),
        findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('ventana de runway: 4 opciones; elegir 7 escribe la BD y la fila', (tester) async {
    final seed = await h.seeded(Mode.variable);
    await pumpApp(tester, seed);
    await openSettings(tester);
    await tapRow(tester, 'runway');
    for (final d in [7, 14, 21, 30]) {
      expect(find.byKey(Key('choice.$d')), findsOneWidget);
    }
    expect(find.text('14 días (recomendado)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('choice.7')));
    await tester.pumpAndSettle();
    expect((await seed.db.select(seed.db.settings).getSingle()).runwayWindowDays, 7);
    expect(rowValue('runway', '7 días'), findsOneWidget);
    await h.unmount(tester);
  });

  group('exportar CSV', () {
    testWidgets('con movimientos: comparte el CSV con el nombre del día', (tester) async {
      final export = await pumpApp(tester, await h.seeded(Mode.variable, (s) => s.expense(12, h.ago(0))));
      await openSettings(tester);
      expect(rowValue('export', '1 movimiento'), findsOneWidget);
      await tapRow(tester, 'export');
      expect(export.calls, 1);
      expect(export.fileName, 'saldoclaro-movimientos-2026-10-08.csv');
      expect(export.csv, startsWith('﻿id;kind;amount_cents'));
      expect(export.csv, contains(';gasto;1200;12.00;2026-10-08;Comida;comida;'));
      await h.unmount(tester);
    });

    testWidgets('sin movimientos: la fila está deshabilitada y no exporta', (tester) async {
      final export = await pumpApp(tester, await h.seeded(Mode.variable));
      await openSettings(tester);
      await tapRow(tester, 'export');
      expect(export.calls, 0);
      await h.unmount(tester);
    });
  });

  group('Acerca de', () {
    test('la versión coincide con pubspec.yaml', () {
      final line = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
      expect(line.trim(), 'version: $appVersion+$appBuild');
    });

    testWidgets('muestra versión, privacidad y licencias', (tester) async {
      await pumpApp(tester, await h.seeded(Mode.variable));
      await openSettings(tester);
      await tapRow(tester, 'about');
      expect(find.text('Versión 0.1.0 (1)'), findsOneWidget);
      expect(find.text('Política de privacidad: llega en la Fase 2.'), findsOneWidget);
      expect(find.byKey(const Key('about.licenses')), findsOneWidget);
      await h.unmount(tester);
    });
  });

  testWidgets('720p: Ajustes no desborda (puede desplazarse)', (tester) async {
    await pumpApp(tester, await h.seeded(Mode.variable), size: const Size(360, 640));
    await openSettings(tester);
    expect(tester.takeException(), isNull);
    await tester.drag(find.byKey(const Key('settings.scroll')), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('settings.about')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });
}
