import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show Tristate;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/data/providers.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/entry/draft_store.dart';
import 'package:saldo_claro/features/entry/entry_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

final today = day(2026, 10, 8);

/// DB cuyo insert espera a [gate]: permite ver el estado "guardando".
class SlowDb extends AppDatabase {
  SlowDb() : super(NativeDatabase.memory());
  final gate = Completer<void>();
  int inserts = 0;

  @override
  Future<Entry> insertManualEntry({
    required String id,
    required EntryKind kind,
    required int amountCents,
    required DateTime day,
    required String pickId,
    String? note,
    required DateTime now,
  }) async {
    inserts++;
    await gate.future;
    return super.insertManualEntry(
        id: id, kind: kind, amountCents: amountCents, day: day, pickId: pickId, note: note, now: now);
  }
}

/// DB cuyo insert real tarda [delay] (Future.delayed: avanza con el reloj del test).
class DelayDb extends AppDatabase {
  DelayDb(this.delay) : super(NativeDatabase.memory());
  final Duration delay;

  @override
  Future<Entry> insertManualEntry({
    required String id,
    required EntryKind kind,
    required int amountCents,
    required DateTime day,
    required String pickId,
    String? note,
    required DateTime now,
  }) async {
    await Future<void>.delayed(delay);
    return super.insertManualEntry(
        id: id, kind: kind, amountCents: amountCents, day: day, pickId: pickId, note: note, now: now);
  }
}

class Host {
  Host(this.db, this.prefs);
  final AppDatabase db;
  final SharedPreferences prefs;
  Entry? result;
  bool closed = false;
}

Future<Host> pumpHost(
  WidgetTester tester, {
  AppDatabase? db,
  Size logicalSize = const Size(411, 914),
  double topPadding = 0,
  double bottomPadding = 0,
}) async {
  const dpr = 2.625;
  tester.view.physicalSize = logicalSize * dpr;
  tester.view.devicePixelRatio = dpr;
  tester.view.padding = FakeViewPadding(top: topPadding * dpr, bottom: bottomPadding * dpr);
  addTearDown(tester.view.reset);
  final database = db ?? AppDatabase(NativeDatabase.memory());
  final host = Host(database, await SharedPreferences.getInstance());
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(database),
      sharedPreferencesProvider.overrideWithValue(host.prefs),
      todayProvider.overrideWithValue(today),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Column(children: [
            TextButton(
              onPressed: () async {
                host.closed = false;
                host.result = await showEntrySheet(ctx, EntryKind.expense);
                host.closed = true;
              },
              child: const Text('abrir gasto'),
            ),
            TextButton(
              onPressed: () async {
                host.closed = false;
                host.result = await showEntrySheet(ctx, EntryKind.income);
                host.closed = true;
              },
              child: const Text('abrir ingreso'),
            ),
          ]),
        ),
      ),
    ),
  ));
  return host;
}

/// Desmonta todo y drena timers (debounce del borrador, animaciones).
Future<void> unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
}

Future<void> open(WidgetTester tester, [String which = 'abrir gasto']) async {
  await tester.tap(find.text(which));
  await tester.pumpAndSettle();
}

Future<void> keys(WidgetTester tester, String seq) async {
  for (final k in seq.split('')) {
    await tester.tap(find.byKey(Key('key.$k')));
    await tester.pump();
  }
}

Future<void> save(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('entry.save')));
  await tester.pumpAndSettle();
}

Future<void> close(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('entry.close')));
  await tester.pumpAndSettle();
}

bool selected(WidgetTester tester, String id) =>
    tester.getSemantics(find.byKey(Key('pick.$id'))).flagsCollection.isSelected == Tristate.isTrue;

/// Fuentes reales: con Ahem (la fuente de test) los anchos no se parecen a
/// Geist y el test de 640 dp mediría otra cosa.
Future<void> loadRealFonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await l.load();
  }

  await load('Newsreader', ['Newsreader16pt-Medium.ttf']);
  await load('Geist', ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf']);
}

void main() {
  setUpAll(loadRealFonts);
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic(); // si no, el singleton arrastra borradores entre tests
  });

  group('render', () {
    testWidgets('gasto: título, Hoy, S/ 0.00, 6 categorías, Comida preseleccionada', (tester) async {
      await pumpHost(tester);
      await open(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Gasto'), findsOneWidget);
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('S/ 0.00'), findsOneWidget);
      for (final id in ['comida', 'transporte', 'vivienda', 'ocio', 'salud', 'otros']) {
        expect(find.byKey(Key('pick.$id')), findsOneWidget);
      }
      expect(selected(tester, 'comida'), isTrue);
      expect(selected(tester, 'otros'), isFalse);
      await unmount(tester);
    });

    testWidgets('ingreso: título, 5 fuentes, Chamba preseleccionada', (tester) async {
      await pumpHost(tester);
      await open(tester, 'abrir ingreso');
      expect(find.text('Ingreso'), findsOneWidget);
      expect(find.byKey(const Key('pick.comida')), findsNothing);
      for (final id in ['chamba', 'venta', 'familiar', 'prestamo', 'otro']) {
        expect(find.byKey(Key('pick.$id')), findsOneWidget);
      }
      expect(selected(tester, 'chamba'), isTrue);
      await unmount(tester);
    });
  });

  testWidgets('preselecciona la última categoría usada', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.insertManualEntry(
        id: 'e1', kind: EntryKind.expense, amountCents: 300, day: today, pickId: 'transporte', now: DateTime(2026, 10, 7));
    await pumpHost(tester, db: db);
    await open(tester);
    expect(selected(tester, 'transporte'), isTrue);
    expect(selected(tester, 'comida'), isFalse);
    await unmount(tester);
  });

  testWidgets('última usada archivada → cae a la primera del orden', (tester) async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.insertManualEntry(
        id: 'e1', kind: EntryKind.expense, amountCents: 300, day: today, pickId: 'ocio', now: DateTime(2026, 10, 7));
    await (db.update(db.categories)..where((c) => c.id.equals('ocio'))).write(const CategoriesCompanion(archived: Value(true)));
    await pumpHost(tester, db: db);
    await open(tester);
    expect(find.byKey(const Key('pick.ocio')), findsNothing);
    expect(selected(tester, 'comida'), isTrue);
    await unmount(tester);
  });

  testWidgets('teclear 12.50 muestra S/ 12.50 y guarda 1250 centavos manual', (tester) async {
    final h = await pumpHost(tester);
    await open(tester);
    await keys(tester, '12.50');
    expect(find.text('S/ 12.50'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pick.ocio')));
    await tester.pump();
    await save(tester);

    expect(h.closed, isTrue);
    final e = h.result!;
    expect(e.amountCents, 1250);
    expect(e.kind, EntryKind.expense);
    expect(e.categoryId, 'ocio');
    expect(e.sourceId, isNull);
    expect(e.origin, Origin.manual);
    expect(e.occurredOn, '2026-10-08');
    expect(e.note, isNull);
    expect(await h.db.select(h.db.entries).get(), hasLength(1));
    await unmount(tester);
  });

  testWidgets('ingreso guarda source_id, no category_id', (tester) async {
    final h = await pumpHost(tester);
    await open(tester, 'abrir ingreso');
    await keys(tester, '300');
    await save(tester);
    expect(h.result!.sourceId, 'chamba');
    expect(h.result!.categoryId, isNull);
    await unmount(tester);
  });

  group('errores', () {
    testWidgets('monto vacío: error, no guarda, no cierra; teclear lo limpia', (tester) async {
      final h = await pumpHost(tester);
      await open(tester);
      await save(tester);
      expect(find.text('Ingresa un monto mayor a S/ 0'), findsOneWidget);
      expect(h.closed, isFalse);
      expect(await h.db.select(h.db.entries).get(), isEmpty);
      await keys(tester, '5');
      expect(find.byKey(const Key('entry.error')), findsNothing);
      await unmount(tester);
    });

    testWidgets('monto 0.00 también es error', (tester) async {
      final h = await pumpHost(tester);
      await open(tester);
      await keys(tester, '0.00');
      await save(tester);
      expect(find.text('Ingresa un monto mayor a S/ 0'), findsOneWidget);
      expect(await h.db.select(h.db.entries).get(), isEmpty);
      await unmount(tester);
    });

    testWidgets('sin categorías activas: aviso y Guardar no inserta', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await db.update(db.categories).write(const CategoriesCompanion(archived: Value(true)));
      final h = await pumpHost(tester, db: db);
      await open(tester);
      expect(find.text('No tienes categorías activas. Actívalas en Ajustes.'), findsOneWidget);
      await keys(tester, '5');
      await save(tester);
      expect(find.byKey(const Key('entry.error')), findsOneWidget);
      expect(await h.db.select(h.db.entries).get(), isEmpty);
      await unmount(tester);
    });
  });

  group('nota (C1)', () {
    testWidgets('con foco oculta el teclado propio; al salir vuelve; se guarda trim', (tester) async {
      final h = await pumpHost(tester);
      await open(tester);
      await keys(tester, '8');
      await tester.tap(find.byKey(const Key('entry.addNote')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('key.1')), findsNothing);
      expect(find.byKey(const Key('entry.save')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('entry.note')), '  menú del día  ');
      await tester.tap(find.byKey(const Key('entry.amount')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('key.1')), findsOneWidget);
      await save(tester);
      expect(h.result!.note, 'menú del día');
      await unmount(tester);
    });
  });

  group('guardando (C2)', () {
    testWidgets('spinner, opacidad 0.6, mismo tamaño; aviso a los 2 s', (tester) async {
      final db = SlowDb();
      final h = await pumpHost(tester, db: db);
      await open(tester);
      await keys(tester, '5');
      final sizeBefore = tester.getSize(find.byKey(const Key('entry.save')));
      await tester.tap(find.byKey(const Key('entry.save')));
      await tester.pump();

      expect(find.byKey(const Key('entry.saving')), findsOneWidget);
      expect(find.text('Guardar'), findsNothing);
      expect(tester.getSize(find.byKey(const Key('entry.save'))), sizeBefore);
      final opacity = tester.widget<AnimatedOpacity>(
          find.ancestor(of: find.byKey(const Key('entry.save')), matching: find.byType(AnimatedOpacity)));
      expect(opacity.opacity, 0.6);

      await tester.pump(const Duration(seconds: 2));
      expect(find.text('Esto está tardando más de lo normal'), findsOneWidget);

      db.gate.complete();
      await tester.pumpAndSettle();
      expect(h.result!.amountCents, 500);
      await unmount(tester);
    });

    testWidgets('doble toque en Guardar con insert en vuelo → exactamente 1 fila en entries', (tester) async {
      final db = DelayDb(const Duration(milliseconds: 500));
      final h = await pumpHost(tester, db: db);
      await open(tester);
      await keys(tester, '12.50');

      await tester.tap(find.byKey(const Key('entry.save')));
      await tester.pump(const Duration(milliseconds: 10)); // el primer insert está en vuelo
      await tester.tap(find.byKey(const Key('entry.save')), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 10));

      await tester.pump(const Duration(milliseconds: 600)); // avanza el tiempo: resuelve el insert
      await tester.pumpAndSettle();

      final rows = await db.select(db.entries).get();
      expect(rows, hasLength(1));
      expect(rows.single.amountCents, 1250);
      expect(h.result!.id, rows.single.id);
      await unmount(tester);
    });

    test('umbrales del cronómetro', () {
      expect(saveDurationLog(150), isNull);
      expect(saveDurationLog(499), isNull);
      expect(saveDurationLog(500), isNull);
      expect(saveDurationLog(501)!.level, 900);
      expect(saveDurationLog(501)!.message, 'guardado lento (501 ms)');
      expect(saveDurationLog(2000)!.level, 900);
      expect(saveDurationLog(2001)!.level, 1000);
      expect(saveDurationLog(2001)!.message, 'guardado muy lento (2001 ms)');
    });
  });

  group('borrador', () {
    testWidgets('cerrar con X y reabrir conserva monto, categoría y nota', (tester) async {
      final h = await pumpHost(tester);
      await open(tester);
      await keys(tester, '7');
      await tester.tap(find.byKey(const Key('pick.salud')));
      await tester.pump();
      await close(tester);
      expect(h.result, isNull);

      await open(tester);
      expect(find.text('S/ 7.00'), findsOneWidget);
      expect(selected(tester, 'salud'), isTrue);
      await unmount(tester);
    });

    testWidgets('sobrevive a cerrar y reabrir la app', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      await pumpHost(tester, db: db);
      await open(tester);
      await keys(tester, '42');
      await tester.tap(find.byKey(const Key('pick.transporte')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('entry.addNote')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('entry.note')), 'taxi');
      await tester.pump();
      await unmount(tester); // la app muere con la hoja abierta

      SharedPreferences.resetStatic(); // proceso nuevo: se relee del disco
      await pumpHost(tester, db: db);
      await open(tester);
      expect(find.text('S/ 42.00'), findsOneWidget);
      expect(selected(tester, 'transporte'), isTrue);
      expect(find.text('taxi'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('paused escribe el borrador sin esperar el debounce (C3)', (tester) async {
      final h = await pumpHost(tester);
      await open(tester);
      await keys(tester, '9');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(); // < 300 ms: el debounce todavía no corrió
      expect(h.prefs.getString('draft.expense'), contains('"amount":"9"'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await unmount(tester);
    });

    testWidgets('guardar borra el borrador', (tester) async {
      final h = await pumpHost(tester);
      await open(tester);
      await keys(tester, '3');
      await close(tester);
      expect(h.prefs.containsKey('draft.expense'), isTrue);
      await open(tester);
      await save(tester);
      expect(h.prefs.containsKey('draft.expense'), isFalse);
      await open(tester);
      expect(find.text('S/ 0.00'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('mantener presionado cerrar → "Descartar borrador" lo borra', (tester) async {
      final h = await pumpHost(tester);
      await open(tester);
      await keys(tester, '3');
      await tester.longPress(find.byKey(const Key('entry.close')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar borrador'));
      await tester.pumpAndSettle();
      expect(h.closed, isTrue);
      expect(h.prefs.containsKey('draft.expense'), isFalse);
      await open(tester);
      expect(find.text('S/ 0.00'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('sin borrador, mantener presionado cerrar no muestra menú', (tester) async {
      await pumpHost(tester);
      await open(tester);
      await tester.longPress(find.byKey(const Key('entry.close')));
      await tester.pumpAndSettle();
      expect(find.text('Descartar borrador'), findsNothing);
      await unmount(tester);
    });

    testWidgets('borrador de gasto no aparece en ingreso', (tester) async {
      await pumpHost(tester);
      await open(tester);
      await keys(tester, '6');
      await close(tester);
      await open(tester, 'abrir ingreso');
      expect(find.text('S/ 0.00'), findsOneWidget);
      await unmount(tester);
    });
  });

  group('alto en 720p (360×640 dp, con barras del sistema)', () {
    testWidgets('compacta: cabe sin scroll, con íconos de categoría y "Agregar nota" como chip', (tester) async {
      await pumpHost(tester, logicalSize: const Size(360, 640), topPadding: 24, bottomPadding: 24);
      await open(tester);
      expect(tester.takeException(), isNull, reason: 'overflow');
      for (final (id, icon) in [
        ('comida', Icons.restaurant),
        ('transporte', Icons.directions_bus),
        ('vivienda', Icons.home),
        ('ocio', Icons.movie),
        ('salud', Icons.healing),
        ('otros', Icons.local_mall),
      ]) {
        expect(find.descendant(of: find.byKey(Key('pick.$id')), matching: find.byIcon(icon)), findsOneWidget,
            reason: '$id sin ícono');
      }
      expect(find.ancestor(of: find.byKey(const Key('entry.addNote')), matching: find.byType(Wrap)), findsOneWidget,
          reason: 'en compacta la nota es un chip del Wrap');
      final scrollable = tester.state<ScrollableState>(
          find.descendant(of: find.byKey(const Key('entry.scroll')), matching: find.byType(Scrollable)));
      expect(scrollable.position.maxScrollExtent, 0, reason: 'no debe necesitar scroll');
      expect(tester.getRect(find.byKey(const Key('entry.save'))).bottom, lessThanOrEqualTo(640 - 24));
      expect(find.byKey(const Key('key.0')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('normal (≥ 700 dp): "Agregar nota" es un enlace separado bajo los chips', (tester) async {
      await pumpHost(tester, logicalSize: const Size(411, 914), topPadding: 24, bottomPadding: 24);
      await open(tester);
      final note = find.byKey(const Key('entry.addNote'));
      expect(find.ancestor(of: note, matching: find.byType(Wrap)), findsNothing);
      final lastChipBottom = tester.getRect(find.byKey(const Key('pick.otros'))).bottom;
      expect(tester.getRect(note).top, greaterThanOrEqualTo(lastChipBottom));
      expect(find.descendant(of: find.byKey(const Key('pick.comida')), matching: find.byIcon(Icons.restaurant)),
          findsOneWidget);
      await unmount(tester);
    });

    testWidgets('compacta: chip de nota abre el campo con borde ink y al salir muestra el texto', (tester) async {
      await pumpHost(tester, logicalSize: const Size(360, 640), topPadding: 24, bottomPadding: 24);
      await open(tester);
      await tester.tap(find.byKey(const Key('entry.addNote')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('entry.note')), findsOneWidget);
      expect(find.byKey(const Key('key.0')), findsNothing);
      await tester.enterText(find.byKey(const Key('entry.note')), 'menú');
      await tester.pump();
      await tester.tap(find.byKey(const Key('entry.amount')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('entry.note')), findsNothing, reason: 'sin foco, el campo vuelve a ser chip');
      expect(find.descendant(of: find.byKey(const Key('entry.addNote')), matching: find.text('menú')), findsOneWidget);
      expect(find.byKey(const Key('key.0')), findsOneWidget);
      final scrollable = tester.state<ScrollableState>(
          find.descendant(of: find.byKey(const Key('entry.scroll')), matching: find.byType(Scrollable)));
      expect(scrollable.position.maxScrollExtent, 0);
      await unmount(tester);
    });

    for (final size in [const Size(360, 640), const Size(411, 914)]) {
      testWidgets('Atrás cierra el teclado del sistema → vuelve el teclado propio (${size.height.toInt()} dp)',
          (tester) async {
        await pumpHost(tester, logicalSize: size, topPadding: 24, bottomPadding: 24);
        await open(tester);
        await tester.tap(find.byKey(const Key('entry.addNote')));
        await tester.pumpAndSettle();
        tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 2.625); // aparece el teclado
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('key.0')), findsNothing);
        tester.view.viewInsets = FakeViewPadding.zero; // Atrás: Android lo oculta sin quitar el foco
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('key.0')), findsOneWidget);
        await unmount(tester);
      });
    }

    testWidgets('con teclado del sistema (300 dp): sin teclado propio, Guardar encima', (tester) async {
      await pumpHost(tester, logicalSize: const Size(360, 640), topPadding: 24, bottomPadding: 24);
      await open(tester);
      await tester.tap(find.byKey(const Key('entry.addNote')));
      await tester.pumpAndSettle();
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 2.625);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'overflow');
      expect(find.byKey(const Key('key.0')), findsNothing);
      final save = tester.getRect(find.byKey(const Key('entry.save')));
      expect(save.bottom, lessThanOrEqualTo(640 - 300));
      final field = tester.getRect(find.byKey(const Key('entry.note')));
      expect(field.bottom, lessThanOrEqualTo(save.top), reason: 'el campo de nota no queda tapado');
      await unmount(tester);
    });
  });
}
