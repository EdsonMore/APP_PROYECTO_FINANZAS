import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/settings/catalog_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import '../home/home_screen_test.dart' as h;
import 'settings_screen_test.dart' as s;

Future<void> openCatalog(WidgetTester tester, {bool income = false}) async {
  await s.openSettings(tester);
  await s.tapRow(tester, income ? 'sources' : 'categories');
}

Future<void> openEditor(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('catalog.$id')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('editor.sheet')), findsOneWidget);
}

Future<void> typeName(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('editor.name')), name);
  await tester.pump();
}

Future<void> tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('editor.save')));
  await tester.tap(find.byKey(const Key('editor.save')));
  await tester.pumpAndSettle();
}

Future<Category> cat(AppDatabase db, String id) =>
    (db.select(db.categories)..where((c) => c.id.equals(id))).getSingle();

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  group('validateCatalogName', () {
    test('trim, sin emojis, ≤ 20, sin duplicados (sin distinguir mayúsculas)', () {
      expect(validateCatalogName('  Mascotas 🐶 ', taken: const []).value, 'Mascotas');
      expect(validateCatalogName('a' * 21, taken: const []).error, 'Máximo 20 caracteres');
      expect(validateCatalogName('comida', taken: const ['Comida']).error, 'Ya existe una con ese nombre.');
      expect(validateCatalogName('   ', taken: const []), (value: null, error: null));
    });
  });

  testWidgets('categorías: lista las 6 activas en orden', (tester) async {
    await s.pumpApp(tester, await h.seeded(Mode.variable));
    await openCatalog(tester);
    expect(find.text('Categorías de gasto'), findsWidgets);
    final ys = [
      for (final id in ['comida', 'transporte', 'vivienda', 'ocio', 'salud', 'otros'])
        tester.getTopLeft(find.byKey(Key('catalog.$id'))).dy,
    ];
    expect(ys, [...ys]..sort());
    await h.unmount(tester);
  });

  testWidgets('agregar: nombre + ícono, va al final y queda activa', (tester) async {
    final seed = await h.seeded(Mode.variable);
    await s.pumpApp(tester, seed);
    await openCatalog(tester);
    await tester.tap(find.byKey(const Key('catalog.add')));
    await tester.pumpAndSettle();
    expect(find.text('Nueva categoría'), findsOneWidget);
    await typeName(tester, 'Mascotas');
    await tester.tap(find.byKey(const Key('editor.icon.favorite')));
    await tester.pump();
    await tapSave(tester);

    final rows = await seed.db.catalog(EntryKind.expense);
    expect(rows.last.name, 'Mascotas');
    expect(rows.last.icon, 'favorite');
    expect(rows.last.archived, isFalse);
    expect(find.text('Mascotas'), findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('duplicado (sin distinguir mayúsculas): error y no guarda', (tester) async {
    final seed = await h.seeded(Mode.variable);
    await s.pumpApp(tester, seed);
    await openCatalog(tester);
    await tester.tap(find.byKey(const Key('catalog.add')));
    await tester.pumpAndSettle();
    await typeName(tester, 'comida');
    await tapSave(tester);
    expect(find.text('Ya existe una con ese nombre.'), findsOneWidget);
    expect(await seed.db.catalog(EntryKind.expense), hasLength(6));
    await h.unmount(tester);
  });

  testWidgets('Guardar deshabilitado con nombre vacío', (tester) async {
    await s.pumpApp(tester, await h.seeded(Mode.variable));
    await openCatalog(tester);
    await tester.tap(find.byKey(const Key('catalog.add')));
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(find.byKey(const Key('editor.save'))).onPressed, isNull);
    await h.unmount(tester);
  });

  testWidgets('editar nombre e ícono', (tester) async {
    final seed = await h.seeded(Mode.variable);
    await s.pumpApp(tester, seed);
    await openCatalog(tester);
    await openEditor(tester, 'comida');
    expect(find.text('Editar categoría'), findsOneWidget);
    await typeName(tester, 'Comidas');
    await tester.tap(find.byKey(const Key('editor.icon.fastfood')));
    await tester.pump();
    await tapSave(tester);
    final c = await cat(seed.db, 'comida');
    expect(c.name, 'Comidas');
    expect(c.icon, 'fastfood');
    await h.unmount(tester);
  });

  testWidgets('archivar → pasa a "Archivadas"; reactivar → vuelve al final de las activas', (tester) async {
    final seed = await h.seeded(Mode.variable);
    await s.pumpApp(tester, seed);
    await openCatalog(tester);
    await openEditor(tester, 'ocio');
    await tester.tap(find.byKey(const Key('editor.archive')));
    await tester.pumpAndSettle();
    expect((await cat(seed.db, 'ocio')).archived, isTrue);
    expect(find.text('Archivadas'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('catalog.ocio')), matching: find.text('Reactivar')), findsOneWidget);

    await tester.tap(find.byKey(const Key('catalog.ocio')));
    await tester.pumpAndSettle();
    final rows = await seed.db.catalog(EntryKind.expense);
    expect(rows.last.id, 'ocio');
    expect(rows.last.archived, isFalse);
    expect(find.text('Archivadas'), findsNothing);
    await h.unmount(tester);
  });

  testWidgets('la última activa no se puede archivar (decisión b)', (tester) async {
    final seed = await h.seeded(Mode.variable);
    await (seed.db.update(seed.db.categories)..where((c) => c.id.isNotValue('salud')))
        .write(const CategoriesCompanion(archived: Value(true)));
    await s.pumpApp(tester, seed);
    await openCatalog(tester);
    await openEditor(tester, 'salud');
    expect(find.text(lastActiveText), findsOneWidget);
    await tester.tap(find.byKey(const Key('editor.archive')));
    await tester.pumpAndSettle();
    expect((await cat(seed.db, 'salud')).archived, isFalse);
    await h.unmount(tester);
  });

  testWidgets('todas archivadas (BD editada a mano): la pantalla lo advierte', (tester) async {
    final seed = await h.seeded(Mode.variable);
    await seed.db.update(seed.db.categories).write(const CategoriesCompanion(archived: Value(true)));
    await s.pumpApp(tester, seed);
    await openCatalog(tester);
    expect(find.byKey(const Key('catalog.noActive')), findsOneWidget);
    expect(find.text(lastActiveText), findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('archivada: sale de los chips del registro pero sigue en Recientes', (tester) async {
    final seed = await h.seeded(Mode.variable, (x) => x.expense(30, h.ago(1), cat: 'ocio'));
    await seed.db.setArchived(EntryKind.expense, 'ocio', archived: true);
    await s.pumpApp(tester, seed);
    expect(find.descendant(of: find.byKey(const Key('home.recents')), matching: find.text('Ocio')), findsOneWidget);
    await tester.tap(find.byKey(const Key('home.cta.expense')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pick.ocio')), findsNothing);
    expect(find.byKey(const Key('pick.comida')), findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('fuentes de ingreso: mismo widget con sus 5 fuentes y textos propios', (tester) async {
    await s.pumpApp(tester, await h.seeded(Mode.variable));
    await openCatalog(tester, income: true);
    expect(find.text('Fuentes de ingreso'), findsWidgets);
    for (final id in ['chamba', 'venta', 'familiar', 'prestamo', 'otro']) {
      expect(find.byKey(Key('catalog.$id')), findsOneWidget);
    }
    expect(find.text('+ Agregar fuente'), findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('720p: el editor entra en 360×640 sin desbordar', (tester) async {
    await s.pumpApp(tester, await h.seeded(Mode.variable), size: const Size(360, 640));
    await openCatalog(tester);
    await openEditor(tester, 'comida');
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });
}
