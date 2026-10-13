import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/data/providers.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/entry/draft_store.dart';
import 'package:saldo_claro/features/history/history_screen.dart';
import 'package:saldo_claro/features/home/home_blocks.dart';
import 'package:saldo_claro/features/home/home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import '../home/home_screen_test.dart' as h;

/// Movimientos con id fijo (las pruebas los buscan por id).
Future<void> add(h.Seed s, String id, int cents, int daysAgo,
        {String pick = 'comida', EntryKind kind = EntryKind.expense, String? note}) =>
    s.db.insertManualEntry(
        id: id, kind: kind, amountCents: cents, day: h.ago(daysAgo), pickId: pick, note: note,
        now: DateTime(2026, 10, 8, 12).subtract(Duration(days: daysAgo)));

/// Comida 42 hoy y 18.50 ayer (con "supermercado"), Ocio 30, Chamba 800.
Future<void> four(h.Seed s) async {
  await add(s, 'super1', 4200, 0, note: 'supermercado Plaza Vea');
  await add(s, 'super2', 1850, 1, note: 'supermercado');
  await add(s, 'cine', 3000, 2, pick: 'ocio');
  await add(s, 'pago', 80000, 3, pick: 'chamba', kind: EntryKind.income);
}

/// Base cuyo borrado espera a [gate]: como en el teléfono, donde drift corre
/// en otro isolate y la lista no se entera del borrado en el mismo frame.
class SlowDeleteDb extends AppDatabase {
  SlowDeleteDb() : super(NativeDatabase.memory());
  final gate = Completer<void>();

  @override
  Future<int> deleteEntry(String id) async {
    await gate.future;
    return super.deleteEntry(id);
  }
}

Future<h.Seed> pumpHistory(WidgetTester tester,
    {Future<void> Function(h.Seed s)? fill, Size size = const Size(411, 914), ThemeData? theme, AppDatabase? db}) async {
  const dpr = 2.625;
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final seed = await h.seeded(Mode.variable, fill, db);
  addTearDown(seed.db.close);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(seed.db),
      sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      todayProvider.overrideWithValue(h.today),
    ],
    child: MaterialApp(theme: theme ?? AppTheme.light, home: const HistoryScreen()),
  ));
  await tester.pumpAndSettle();
  return seed;
}

Finder row(String id) => find.byKey(Key('history.row.$id'));
Finder key(String k) => find.byKey(Key(k));

Future<void> tap(WidgetTester tester, String k) async {
  await tester.ensureVisible(key(k));
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

String totalsText(WidgetTester tester) =>
    tester.widget<Text>(key('history.totals.oneLine')).textSpan!.toPlainText().replaceAll('\u00A0', ' ');

Future<Entry?> entry(h.Seed s, String id) => (s.db.select(s.db.entries)..where((e) => e.id.equals(id))).getSingleOrNull();

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  testWidgets('vacío: sin movimientos, el mensaje y sin totales', (tester) async {
    await pumpHistory(tester);
    expect(find.text('Historial'), findsOneWidget);
    expect(key('history.empty'), findsOneWidget);
    expect(find.text('Todavía no hay movimientos.'), findsOneWidget);
    expect(find.text('Registra tu primer gasto o ingreso desde el Inicio.'), findsOneWidget);
    expect(find.textContaining('movimientos ·'), findsNothing);
    expect(find.text('Buscar movimientos'), findsOneWidget, reason: 'C1: placeholder corto');
    await h.unmount(tester);
  });

  testWidgets('lista agrupada por día y totales de todo', (tester) async {
    await pumpHistory(tester, fill: four);
    expect(find.text('Hoy'), findsOneWidget);
    expect(find.text('Ayer'), findsOneWidget);
    for (final id in ['super1', 'super2', 'cine', 'pago']) {
      expect(row(id), findsOneWidget);
    }
    expect(totalsText(tester), '4 movimientos · Gastos S/ 90.50 · Ingresos S/ 800.00');
    expect(tester.widget<Text>(key('history.totals.oneLine')).textSpan!.toPlainText(), contains('S/ 800.00'),
        reason: 'C3: un monto nunca se parte entre "S/" y la cifra');
    await h.unmount(tester);
  });

  testWidgets('filtros: tipo cambia los chips; chips y totales; "Limpiar"', (tester) async {
    await pumpHistory(tester, fill: four);
    await tap(tester, 'history.kind.expense');
    expect(row('pago'), findsNothing);
    expect(key('history.pick.chamba'), findsNothing, reason: 'con Gastos no hay fuentes');
    expect(totalsText(tester), '3 movimientos · Gastos S/ 90.50');

    await tap(tester, 'history.pick.comida');
    expect(row('cine'), findsNothing);
    expect(totalsText(tester), '2 movimientos · Gastos S/ 60.50');

    await tap(tester, 'history.clearPicks');
    expect(row('cine'), findsOneWidget);

    await tap(tester, 'history.kind.income');
    expect(key('history.pick.comida'), findsNothing);
    expect(key('history.pick.chamba'), findsOneWidget);
    expect(totalsText(tester), '1 movimiento · Ingresos S/ 800.00');
    await h.unmount(tester);
  });

  testWidgets('búsqueda en vivo: nota y categoría o fuente; la X la borra', (tester) async {
    await pumpHistory(tester, fill: four);
    await tester.enterText(key('history.search'), 'SUPER');
    await tester.pumpAndSettle();
    expect([row('super1'), row('super2')], everyElement(findsOneWidget));
    expect(row('cine'), findsNothing);

    await tester.enterText(key('history.search'), 'chamba');
    await tester.pumpAndSettle();
    expect(row('pago'), findsOneWidget);
    expect(row('super1'), findsNothing);

    await tap(tester, 'history.search.clear');
    expect(row('super1'), findsOneWidget);
    expect(find.text('Buscar movimientos'), findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('sin resultados: mensaje y "Quitar filtros" vuelve a todo', (tester) async {
    await pumpHistory(tester, fill: four);
    await tap(tester, 'history.kind.expense');
    await tester.enterText(key('history.search'), 'zzz');
    await tester.pumpAndSettle();
    expect(key('history.noResults'), findsOneWidget);
    expect(find.text('Nada con estos filtros.'), findsOneWidget);
    await tap(tester, 'history.resetFilters');
    expect(row('pago'), findsOneWidget);
    expect(tester.widget<TextField>(key('history.search')).controller!.text, isEmpty);
    await h.unmount(tester);
  });

  testWidgets('Fecha: menú con rangos; "Últimos 30 días" deja fuera lo viejo; Personalizado abre el calendario',
      (tester) async {
    await pumpHistory(tester, fill: (s) async {
      await four(s);
      await add(s, 'viejo', 500, 60);
    });
    expect(row('viejo'), findsOneWidget);
    await tap(tester, 'history.date');
    expect(find.text('Este mes'), findsOneWidget);
    expect(find.text('Mes pasado'), findsOneWidget);
    await tap(tester, 'range.last30');
    expect(row('viejo'), findsNothing);
    expect(find.text('Últimos 30 días'), findsOneWidget, reason: 'la etiqueta del chip');

    await tap(tester, 'history.date');
    await tap(tester, 'range.custom');
    expect(find.byType(DateRangePickerDialog), findsOneWidget);
    Navigator.of(tester.element(find.byType(DateRangePickerDialog))).pop();
    await tester.pumpAndSettle();
    expect(row('viejo'), findsNothing, reason: 'cancelar no cambia el rango');
    await h.unmount(tester);
  });

  group('edición (H1)', () {
    testWidgets('tocar una fila abre la hoja precargada; un cambio se guarda y avisa', (tester) async {
      final handle = tester.ensureSemantics();
      final seed = await pumpHistory(tester, fill: four);
      await tester.tap(row('super1'));
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Monto: S/ 42.00'), findsOneWidget);
      expect(find.text('Guardar cambios'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'supermercado Plaza Vea'), findsOneWidget, reason: 'la nota precargada');
      await tap(tester, 'pick.transporte');
      await tap(tester, 'entry.save');
      expect((await entry(seed, 'super1'))!.categoryId, 'transporte');
      expect(find.text('Cambios guardados'), findsOneWidget);
      handle.dispose();
      await h.unmount(tester);
    });

    testWidgets('sin cambios: cierra sin escribir y sin aviso', (tester) async {
      final seed = await pumpHistory(tester, fill: four);
      final before = (await entry(seed, 'cine'))!.updatedAt;
      await tester.tap(row('cine'));
      await tester.pumpAndSettle();
      await tap(tester, 'entry.save');
      expect(find.byKey(const Key('entry.save')), findsNothing, reason: 'la hoja se cerró');
      expect((await entry(seed, 'cine'))!.updatedAt, before);
      expect(find.text('Cambios guardados'), findsNothing);
      await h.unmount(tester);
    });

    testWidgets('V1 / O3: la categoría archivada aparece al editar (marcada) y no al crear', (tester) async {
      final seed = await h.seeded(Mode.variable, (s) async {
        await add(s, 'cine', 3000, 2, pick: 'ocio');
        await s.db.setArchived(EntryKind.expense, 'ocio', archived: true);
      });
      await h.pumpHome(tester, seed);
      await tester.tap(find.byKey(const Key('home.cta.expense')));
      await tester.pumpAndSettle();
      expect(key('pick.ocio'), findsNothing, reason: 'creación: las archivadas no se ofrecen');
      await tap(tester, 'entry.close');

      await tester.tap(find.byType(MovementTile).first);
      await tester.pumpAndSettle();
      expect(key('pick.ocio'), findsOneWidget, reason: 'edición: la del movimiento sigue');
      expect(find.text('Ocio (archivada)'), findsOneWidget);
      await tap(tester, 'entry.close');
      await h.unmount(tester);
    });
  });

  group('C2: deslizar para borrar', () {
    testWidgets('deslizar → diálogo → Cancelar: la fila sigue en su lugar y en la base', (tester) async {
      final seed = await pumpHistory(tester, fill: four);
      await tester.drag(row('cine'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('¿Borrar este movimiento?'), findsOneWidget);
      expect(find.text('Ocio, S/ 30.00, 6 oct. No se puede deshacer.'), findsOneWidget);
      await tap(tester, 'history.delete.cancel');
      expect(row('cine'), findsOneWidget);
      expect(await entry(seed, 'cine'), isNotNull);
      expect(tester.takeException(), isNull);
      await h.unmount(tester);
    });

    testWidgets('deslizar → Borrar: la fila desaparece, se borra con lápida y avisa', (tester) async {
      final seed = await pumpHistory(tester, fill: four);
      await seed.db.customUpdate("UPDATE entries SET synced_at = updated_at WHERE id = 'cine'"); // ya sincronizado
      await tester.drag(row('cine'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tap(tester, 'history.delete.confirm');
      expect(row('cine'), findsNothing);
      expect(await entry(seed, 'cine'), isNull);
      expect([for (final t in await seed.db.pendingTombstones()) t.recordId], ['cine']);
      expect(find.text('Movimiento eliminado'), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'sin "dismissed Dismissible still in the tree"');
      await h.unmount(tester);
    });

    testWidgets('con la base lenta: la fila sale de la lista en el acto, sin esperar el borrado', (tester) async {
      final db = SlowDeleteDb();
      await pumpHistory(tester, fill: four, db: db);
      await tester.drag(row('cine'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(key('history.delete.confirm'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1)); // la base sigue sin terminar de borrar
      // Algo redibuja la lista en ese hueco (aquí, escribir en el buscador): la
      // fila deslizada no puede volver a construirse.
      await tester.enterText(key('history.search'), 'ocio');
      await tester.pump();
      expect(row('cine'), findsNothing);
      expect(tester.takeException(), isNull, reason: 'sin "dismissed Dismissible still in the tree"');
      db.gate.complete();
      await tester.pumpAndSettle();
      await h.unmount(tester);
    });

    testWidgets('un deslizamiento muy rápido igual espera la confirmación', (tester) async {
      final seed = await pumpHistory(tester, fill: four);
      await tester.fling(row('cine'), const Offset(-400, 0), 5000);
      await tester.pump(); // ni un frame de más: la base todavía no puede haber cambiado
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('¿Borrar este movimiento?'), findsOneWidget);
      expect(await entry(seed, 'cine'), isNotNull, reason: 'nada se borra antes de confirmar');
      await tap(tester, 'history.delete.cancel');
      expect(row('cine'), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('accesibilidad: la acción "Borrar" pide la misma confirmación', (tester) async {
      final seed = await pumpHistory(tester, fill: four);
      final tile = tester.widget<MovementTile>(row('cine'));
      tile.actions[const CustomSemanticsAction(label: 'Borrar')]!();
      await tester.pumpAndSettle();
      expect(find.text('¿Borrar este movimiento?'), findsOneWidget);
      await tap(tester, 'history.delete.confirm');
      expect(await entry(seed, 'cine'), isNull);
      await h.unmount(tester);
    });
  });

  group('C3: totales en una o dos líneas', () {
    testWidgets('caben: una línea', (tester) async {
      await pumpHistory(tester, fill: four);
      expect(key('history.totals.oneLine'), findsOneWidget);
      expect(key('history.totals.count'), findsNothing);
      await h.unmount(tester);
    });

    testWidgets('320 dp con montos grandes: conteo arriba, montos completos abajo, sin desbordes', (tester) async {
      await pumpHistory(tester, size: const Size(320, 640), fill: (s) async {
        await add(s, 'casa', 123456789, 0, pick: 'vivienda');
        await add(s, 'venta', 987654321, 1, pick: 'venta', kind: EntryKind.income);
      });
      expect(key('history.totals.oneLine'), findsNothing);
      expect(tester.widget<Text>(key('history.totals.count')).textSpan!.toPlainText(), '2 movimientos');
      expect(tester.widget<Text>(key('history.totals.sums')).textSpan!.toPlainText().replaceAll('\u00A0', ' '),
          'Gastos S/ 1,234,567.89 · Ingresos S/ 9,876,543.21', reason: 'sin abreviar');
      expect(tester.takeException(), isNull);
      await h.unmount(tester);
    });
  });

  group('V2: accesos y Recientes', () {
    testWidgets('tocar un movimiento de Recientes abre la edición; "Ver todo" abre el Historial', (tester) async {
      final seed = await h.seeded(Mode.variable, four);
      await h.pumpHome(tester, seed);
      expect(find.byType(MovementTile), findsNWidgets(4), reason: 'Recientes usa la misma fila');
      await tester.tap(find.byType(MovementTile).first);
      await tester.pumpAndSettle();
      expect(find.text('Guardar cambios'), findsOneWidget);
      await tap(tester, 'entry.close');

      await tap(tester, 'home.seeAll');
      expect(find.byType(HistoryScreen), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('fila "Historial" en Ajustes', (tester) async {
      final seed = await h.seeded(Mode.variable, four);
      await h.pumpHome(tester, seed);
      await tester.tap(find.byTooltip('Ajustes'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: key('settings.history'), matching: find.text('4 movimientos')), findsOneWidget);
      await tap(tester, 'settings.history');
      expect(find.byType(HistoryScreen), findsOneWidget);
      await h.unmount(tester);
    });
  });

  testWidgets('V3: editar no toca el borrador del registro', (tester) async {
    final handle = tester.ensureSemantics();
    final seed = await h.seeded(Mode.variable, four);
    await h.pumpHome(tester, seed);
    await tester.tap(find.byKey(const Key('home.cta.expense')));
    await tester.pumpAndSettle();
    await tap(tester, 'key.7');
    await tap(tester, 'key.5');
    await tap(tester, 'entry.close'); // cierra sin guardar: queda el borrador
    final store = ProviderScope.containerOf(tester.element(find.byType(HomeScreen))).read(draftStoreProvider);
    expect(store.load(EntryKind.expense)?.amountText, '75');

    await tester.tap(find.byType(MovementTile).first); // un gasto: misma clave de borrador
    await tester.pumpAndSettle();
    expect(find.text('Guardar cambios'), findsOneWidget);
    await tap(tester, 'key.9'); // teclear en la edición tampoco lo toca
    await tap(tester, 'entry.close');
    expect(store.load(EntryKind.expense)?.amountText, '75');

    await tester.tap(find.byKey(const Key('home.cta.expense')));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp(r'^Monto: S/ 75')), findsOneWidget, reason: 'el borrador sigue ahí');
    await tap(tester, 'entry.close');
    handle.dispose();
    await h.unmount(tester);
  });

  testWidgets('modo oscuro: renderiza sin errores', (tester) async {
    await pumpHistory(tester, fill: four, theme: AppTheme.dark);
    expect(row('super1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });
}
