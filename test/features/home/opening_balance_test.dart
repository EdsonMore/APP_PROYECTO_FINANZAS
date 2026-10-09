import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/data/providers.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/entry/draft_store.dart';
import 'package:saldo_claro/features/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import 'home_screen_test.dart' as h;

const cardText = 'Así el cálculo usa tu plata real.';

Finder get card => find.byKey(const Key('home.openingCard'));
Finder get sheet => find.byKey(const Key('opening.sheet'));

Future<Setting> settingsOf(AppDatabase db) => db.select(db.settings).getSingle();

/// Monta un ProviderScope nuevo sobre la misma base: equivale a reiniciar la app.
Future<void> restart(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      todayProvider.overrideWithValue(h.today),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
  ));
  await tester.pumpAndSettle();
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home.openingCard.set')));
  await tester.pumpAndSettle();
  expect(sheet, findsOneWidget);
}

Future<void> keys(WidgetTester tester, String seq) async {
  for (final k in seq.split('')) {
    await tester.tap(find.byKey(Key('key.$k')));
    await tester.pump();
  }
}

FilledButton saveButton(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('opening.save')));

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  group('tarjeta en el Home', () {
    testWidgets('aparece sin saldo inicial y sin datos', (tester) async {
      await h.pumpHome(tester, await h.seeded(Mode.stable));
      expect(card, findsOneWidget);
      expect(find.text(cardText), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('aparece sin saldo inicial aunque el balance sea positivo (criterio nuevo)', (tester) async {
      await h.pumpHome(tester, await h.seeded(Mode.variable, (s) => s.twoWeeks()));
      expect(find.text('~86 días'), findsOneWidget, reason: 'balance positivo');
      expect(card, findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('no aparece con saldo inicial', (tester) async {
      await h.pumpHome(
          tester, await h.seeded(Mode.variable, (s) => s.db.setOpeningBalance(cents: 50000, at: DateTime(2026, 10, 1))));
      expect(card, findsNothing);
      await h.unmount(tester);
    });

    testWidgets('la X la descarta, no vuelve con cambios de datos, sí al reiniciar', (tester) async {
      final seed = await h.seeded(Mode.variable);
      await h.pumpHome(tester, seed);
      await tester.tap(find.byKey(const Key('home.openingCard.close')));
      await tester.pumpAndSettle();
      expect(card, findsNothing);

      await seed.expense(20, h.ago(0)); // el Home se recalcula: la tarjeta sigue oculta
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home.recents')), findsOneWidget);
      expect(card, findsNothing);
      expect((await settingsOf(seed.db)).openingBalanceCents, isNull, reason: 'descartar no escribe en la base');

      await restart(tester, seed.db);
      expect(card, findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('C1: monto sin instante (datos viejos) no rompe, se ignora y la tarjeta permite corregirlo',
        (tester) async {
      final seed = await h.seeded(Mode.survival, (s) async {
        await s.db.update(s.db.settings).write(const SettingsCompanion(openingBalanceCents: Value(100000)));
        await s.expense(50, h.ago(1));
      });
      await h.pumpHome(tester, seed);
      expect(tester.takeException(), isNull);
      expect(find.text('Sin colchón'), findsOneWidget, reason: 'el S/ 1,000 sin instante cuenta como 0');
      expect(card, findsOneWidget);
      await h.unmount(tester);
    });
  });

  group('hoja "¿Cuánto tienes hoy?"', () {
    testWidgets('"Poner saldo" la abre, con el monto vacío y el botón deshabilitado', (tester) async {
      final seed = await h.seeded(Mode.variable);
      await h.pumpHome(tester, seed);
      await openSheet(tester);
      expect(find.text('Con eso calculo cuántos días te alcanza. Puedes cambiarlo en Ajustes.'), findsOneWidget);
      expect(find.text('S/ 0.00'), findsOneWidget);
      expect(saveButton(tester).onPressed, isNull, reason: 'deshabilitado con monto vacío');
      await tester.tap(find.byKey(const Key('opening.save')), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget);
      expect((await settingsOf(seed.db)).openingBalanceCents, isNull);
      await h.unmount(tester);
    });

    testWidgets('guardar escribe monto e instante; la tarjeta se va y el número cambia', (tester) async {
      final seed = await h.seeded(Mode.survival, (s) => s.expense(50, h.ago(1)));
      await h.pumpHome(tester, seed);
      expect(find.text('Sin colchón'), findsOneWidget);
      await openSheet(tester);
      await keys(tester, '1100');
      final before = DateTime.now();
      await tester.tap(find.byKey(const Key('opening.save')));
      await tester.pumpAndSettle();

      final s = await settingsOf(seed.db);
      expect(s.openingBalanceCents, 110000);
      expect(s.openingBalanceAt, isNotNull);
      expect(s.openingBalanceAt!, greaterThanOrEqualTo(before.millisecondsSinceEpoch - 1000));
      expect(sheet, findsNothing);
      expect(card, findsNothing);
      expect(find.text('Sin colchón'), findsNothing);
      expect(find.textContaining('días'), findsWidgets);
      await h.unmount(tester);
    });

    testWidgets('S/ 0 es válido: el botón se habilita y se guarda 0', (tester) async {
      final seed = await h.seeded(Mode.survival);
      await h.pumpHome(tester, seed);
      await openSheet(tester);
      await keys(tester, '0');
      expect(saveButton(tester).onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('opening.save')));
      await tester.pumpAndSettle();
      expect((await settingsOf(seed.db)).openingBalanceCents, 0);
      expect(card, findsNothing);
      await h.unmount(tester);
    });

    testWidgets('C2: monto vacío → deslizar hacia abajo cierra', (tester) async {
      final seed = await h.seeded(Mode.variable);
      await h.pumpHome(tester, seed);
      await openSheet(tester);
      await tester.drag(sheet, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect(card, findsOneWidget, reason: 'cerrar sin guardar no descarta la tarjeta');
      await h.unmount(tester);
    });

    testWidgets('C2: con monto → ni deslizar, ni tocar fuera, ni Atrás cierran; "Ahora no" sí, sin escribir',
        (tester) async {
      final seed = await h.seeded(Mode.variable);
      await h.pumpHome(tester, seed);
      await openSheet(tester);
      await keys(tester, '500');

      await tester.drag(sheet, const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget, reason: 'deslizar no pierde el monto');

      await tester.tapAt(const Offset(200, 40)); // fondo oscuro, fuera de la hoja
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget, reason: 'tocar fuera no cierra');

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(sheet, findsOneWidget, reason: 'Atrás no cierra');
      expect(find.text('S/ 500.00'), findsOneWidget);

      await tester.tap(find.text('Ahora no'));
      await tester.pumpAndSettle();
      expect(sheet, findsNothing);
      expect((await settingsOf(seed.db)).openingBalanceCents, isNull);
      expect(card, findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('cabe en 360×640 dp sin desbordar', (tester) async {
      await h.pumpHome(tester, await h.seeded(Mode.variable), size: const Size(360, 640));
      await openSheet(tester);
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.text('Ahora no')).bottom, lessThanOrEqualTo(640));
      await h.unmount(tester);
    });
  });
}
