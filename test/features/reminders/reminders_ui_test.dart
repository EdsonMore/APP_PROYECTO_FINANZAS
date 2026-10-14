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
import 'package:saldo_claro/domain/recurrence.dart';
import 'package:saldo_claro/features/entry/draft_store.dart';
import 'package:saldo_claro/features/entry/entry_sheet.dart';
import 'package:saldo_claro/features/reminders/lifecycle.dart';
import 'package:saldo_claro/features/reminders/notifier.dart';
import 'package:saldo_claro/features/reminders/reminders_screen.dart';
import 'package:saldo_claro/features/reminders/service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import '../entry/entry_sheet_test.dart' show keys, save, unmount;
import '../home/home_screen_test.dart' as h;
import '../settings/settings_screen_test.dart' as st;

final today = day(2026, 10, 8);

class ReminderHost {
  ReminderHost(this.db, this.prefs, this.notifier);
  final AppDatabase db;
  final SharedPreferences prefs;
  final FakeReminderNotifier notifier;
}

/// Hoja de registro con el notificador falso; "abrir gasto"/"abrir ingreso" y
/// el ReminderOpener del Home (N7).
Future<ReminderHost> pumpHost(WidgetTester tester, {Size size = const Size(411, 914), bool granted = true}) async {
  const dpr = 2.625;
  tester.view.physicalSize = size * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final host = ReminderHost(AppDatabase(NativeDatabase.memory()), await SharedPreferences.getInstance(),
      FakeReminderNotifier()..granted = granted);
  addTearDown(host.db.close);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(host.db),
      sharedPreferencesProvider.overrideWithValue(host.prefs),
      todayProvider.overrideWithValue(today),
      reminderNotifierProvider.overrideWithValue(host.notifier),
      reminderServiceProvider.overrideWith(
          (ref) => ReminderService(host.db, host.notifier, clock: () => DateTime(2026, 10, 8, 10))),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: ReminderOpener(
        child: Builder(
          builder: (ctx) => Scaffold(
            body: Column(children: [
              TextButton(
                  onPressed: () => showEntrySheet(ctx, EntryKind.expense), child: const Text('abrir gasto')),
              TextButton(
                  onPressed: () => showEntrySheet(ctx, EntryKind.income), child: const Text('abrir ingreso')),
            ]),
          ),
        ),
      ),
    ),
  ));
  return host;
}

Future<void> open(WidgetTester tester, String which) async {
  await tester.tap(find.text(which));
  await tester.pumpAndSettle();
}

Future<void> pickRepeat(WidgetTester tester, String option) async {
  await tester.ensureVisible(find.byKey(const Key('entry.repeat')));
  await tester.tap(find.byKey(const Key('entry.repeat')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('repeat.$option')));
  await tester.pumpAndSettle();
}

Future<Recurrence> internet(AppDatabase db, {String categoryId = 'vivienda'}) => db.insertRecurrence(
    id: 'r1', amountCents: 4500, categoryId: categoryId, note: 'Internet', frequency: Frequency.monthly,
    firstDay: day(2026, 9, 11)); // próximo: 11 oct

/// Lo que haría tocar la notificación con la app abierta.
/// fix5: tocar un recordatorio abre la hoja de acciones; "Editar", el editor.
Future<void> openEditor(WidgetTester tester, String id) async {
  await tester.tap(find.byKey(Key('reminders.$id')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('reminder.edit')));
  await tester.pumpAndSettle();
}

Future<void> tapNotification(WidgetTester tester, String id) async {
  ProviderScope.containerOf(tester.element(find.text('abrir gasto'))).read(pendingReminderProvider.notifier).state = id;
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  group('Repetir (N5)', () {
    testWidgets('aparece al crear un gasto; no en ingresos', (tester) async {
      await pumpHost(tester);
      await open(tester, 'abrir gasto');
      expect(find.text('Repetir: Nunca'), findsOneWidget);
      expect(find.text('Guardar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('entry.close')));
      await tester.pumpAndSettle();
      await open(tester, 'abrir ingreso');
      expect(find.byKey(const Key('entry.repeat')), findsNothing);
      await unmount(tester);
    });

    testWidgets('con permiso: guarda el gasto y el recordatorio, y programa el aviso', (tester) async {
      final host = await pumpHost(tester);
      await open(tester, 'abrir gasto');
      await keys(tester, '45');
      await pickRepeat(tester, 'monthly');
      expect(host.notifier.requests, 0, reason: 'ya había permiso');
      expect(find.byKey(const Key('entry.noPermission')), findsNothing);
      expect(find.text('Guardar y recordar'), findsOneWidget);
      await save(tester);
      expect((await host.db.select(host.db.entries).get()).single.amountCents, 4500);
      final r = await host.db.select(host.db.recurrences).getSingle();
      expect((r.amountCents, r.categoryId, r.frequency, r.nextDue, r.anchorDay),
          (4500, 'comida', Frequency.monthly, '2026-11-08', 8));
      expect(host.notifier.scheduled[r.notificationId * 10]!.at, DateTime(2026, 11, 5, 9));
      await unmount(tester);
    });

    testWidgets('N6: sin permiso lo pide una sola vez; si lo niega, avisa y abre ajustes', (tester) async {
      final host = await pumpHost(tester, granted: false);
      host.notifier.grantOnRequest = false;
      await open(tester, 'abrir gasto');
      await pickRepeat(tester, 'weekly');
      expect(host.notifier.requests, 1);
      expect(find.text('Activa las notificaciones para que te avisemos.'), findsOneWidget);
      await pickRepeat(tester, 'monthly');
      expect(host.notifier.requests, 1, reason: 'no insiste en la misma hoja');
      await tester.tap(find.byKey(const Key('entry.openSettings')));
      expect(host.notifier.settingsOpened, 1);
      await unmount(tester);
    });

    testWidgets('"Nunca" no guarda recordatorio ni pide permiso', (tester) async {
      final host = await pumpHost(tester, granted: false);
      await open(tester, 'abrir gasto');
      await keys(tester, '9');
      await pickRepeat(tester, 'never');
      await save(tester);
      expect(host.notifier.requests, 0);
      expect(await host.db.select(host.db.recurrences).get(), isEmpty);
      await unmount(tester);
    });

    // 4D-fix: existir no basta; tiene que verse y tocarse sin scroll. Como chip
    // bajo las categorías, con letra grande quedaba fuera de la vista.
    for (final (size, scale) in [(const Size(360, 640), 1.0), (const Size(360, 640), 1.3), (const Size(320, 568), 1.3)]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} dp, letra ×$scale: Repetir arriba, visible y se elige',
          (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        final host = await pumpHost(tester, size: size);
        await open(tester, 'abrir gasto');
        expect(tester.takeException(), isNull);
        final repeat = find.byKey(const Key('entry.repeat'));
        expect(repeat.hitTestable(), findsOneWidget, reason: 'tapado o fuera de la vista');
        expect(tester.getRect(repeat).top, lessThan(tester.getRect(find.byKey(const Key('entry.amount'))).top),
            reason: 'en el encabezado, no entre los chips');
        expect(find.byKey(const Key('entry.save')).hitTestable(), findsOneWidget);
        await tester.tap(repeat);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('repeat.monthly')));
        await tester.pumpAndSettle();
        expect(tester.getSemantics(repeat).label, 'Repetir: Cada mes');
        await keys(tester, '9');
        await save(tester);
        expect(await host.db.select(host.db.recurrences).get(), hasLength(1));
        await unmount(tester);
      });
    }
  });

  group('desde la notificación (N7, R1)', () {
    testWidgets('abre la hoja precargada; al guardar registra el gasto y pasa al mes siguiente', (tester) async {
      final host = await pumpHost(tester);
      final r = await internet(host.db);
      await tapNotification(tester, r.id);
      expect(find.text('S/ 45.00'), findsOneWidget);
      expect(find.text('Internet'), findsOneWidget);
      expect(find.byKey(const Key('entry.repeat')), findsNothing);
      await save(tester);
      final e = (await host.db.select(host.db.entries).get()).single;
      expect((e.amountCents, e.categoryId, e.note), (4500, 'vivienda', 'Internet'));
      expect((await host.db.select(host.db.recurrences).getSingle()).nextDue, '2026-11-11');
      expect(ProviderScope.containerOf(tester.element(find.text('abrir gasto'))).read(pendingReminderProvider), isNull);
      await unmount(tester);
    });

    testWidgets('no toca el borrador del registro normal', (tester) async {
      final host = await pumpHost(tester);
      await open(tester, 'abrir gasto');
      await keys(tester, '12');
      await tester.tap(find.byKey(const Key('entry.close')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      final draft = host.prefs.getString('draft.expense');
      expect(draft, isNotNull);
      await tapNotification(tester, (await internet(host.db)).id);
      await save(tester);
      expect(host.prefs.getString('draft.expense'), draft);
      await unmount(tester);
    });

    testWidgets('N1: si la categoría ya no existe, la hoja abre igual y guarda', (tester) async {
      final host = await pumpHost(tester);
      await tapNotification(tester, (await internet(host.db, categoryId: 'no-existe')).id);
      expect(tester.takeException(), isNull);
      await save(tester);
      expect((await host.db.select(host.db.entries).get()).single.amountCents, 4500);
      await unmount(tester);
    });

    testWidgets('si se borró mientras tanto, no abre nada', (tester) async {
      await pumpHost(tester);
      await tapNotification(tester, 'no-existe');
      expect(find.byType(BottomSheet), findsNothing);
      await unmount(tester);
    });
  });

  group('Ajustes → Recordatorios', () {
    Future<AppDatabase> openList(WidgetTester tester) async {
      final seed = await h.seeded(Mode.variable);
      await st.pumpApp(tester, seed);
      await st.openSettings(tester);
      await st.showRow(tester, 'reminders');
      expect(st.rowValue('reminders', 'Sin recordatorios'), findsOneWidget);
      await seed.db.insertRecurrence(
          id: 'r1', amountCents: 4500, categoryId: 'vivienda', note: 'Internet', frequency: Frequency.monthly,
          firstDay: day(2026, 10, 17));
      await tester.pumpAndSettle();
      expect(st.rowValue('reminders', '1 activo'), findsOneWidget);
      await st.tapRow(tester, 'reminders');
      expect(find.byType(RemindersScreen), findsOneWidget);
      return seed.db;
    }

    testWidgets('lista: nombre, monto y "Cada mes · próximo 17 nov"', (tester) async {
      await openList(tester);
      expect(find.text('Internet (Vivienda)'), findsOneWidget);
      expect(find.text('S/ 45.00'), findsOneWidget);
      expect(find.text('Cada mes · próximo 17 nov'), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('Editar: cambia la frecuencia y guarda sin crear gastos', (tester) async {
      final db = await openList(tester);
      final before = (await db.select(db.entries).get()).length;
      await openEditor(tester, 'r1');
      expect(find.text('Guardar cambios'), findsOneWidget);
      expect(find.byKey(const Key('repeat.never')), findsNothing);
      await pickRepeat(tester, 'weekly');
      await save(tester);
      final r = await db.select(db.recurrences).getSingle();
      expect((r.frequency, r.nextDue), (Frequency.weekly, '2026-11-17'));
      expect((await db.select(db.entries).get()).length, before);
      expect(find.text('Cada semana · próximo 17 nov'), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('deslizar pide confirmar; Cancelar lo deja y Borrar lo quita', (tester) async {
      final db = await openList(tester);
      await tester.drag(find.byKey(const Key('reminders.r1')), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text('¿Borrar este recordatorio?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reminders.delete.cancel')));
      await tester.pumpAndSettle();
      expect(await db.select(db.recurrences).get(), hasLength(1));
      await tester.drag(find.byKey(const Key('reminders.r1')), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reminders.delete.confirm')));
      await tester.pumpAndSettle();
      expect(await db.select(db.recurrences).get(), isEmpty);
      expect(find.text('Sin recordatorios'), findsOneWidget);
      await h.unmount(tester);
    });
  });

  group('fix3: crear y editar desde Ajustes', () {
    /// Ajustes → Recordatorios sola, con el notificador falso y el reloj fijo
    /// (8 oct 2026, 10:00).
    Future<ReminderHost> pumpList(WidgetTester tester,
        {bool granted = true, Size size = const Size(411, 914)}) async {
      const dpr = 2.625;
      tester.view.physicalSize = size * dpr;
      tester.view.devicePixelRatio = dpr;
      addTearDown(tester.view.reset);
      final host = ReminderHost(AppDatabase(NativeDatabase.memory()), await SharedPreferences.getInstance(),
          FakeReminderNotifier()..granted = granted);
      addTearDown(host.db.close);
      await host.db.completeOnboarding(mode: Mode.variable);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(host.db),
          sharedPreferencesProvider.overrideWithValue(host.prefs),
          todayProvider.overrideWithValue(today),
          reminderNotifierProvider.overrideWithValue(host.notifier),
          reminderServiceProvider.overrideWith(
              (ref) => ReminderService(host.db, host.notifier, clock: () => DateTime(2026, 10, 8, 10))),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const RemindersScreen()),
      ));
      await tester.pumpAndSettle();
      return host;
    }

    Future<void> openNew(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('reminders.add')));
      await tester.tap(find.byKey(const Key('reminders.add')));
      await tester.pumpAndSettle();
    }

    /// Abre el calendario de "Próximo pago" y elige [dayOfMonth] del mes que
    /// muestra (o del anterior con [prevMonth]).
    Future<void> pickDue(WidgetTester tester, int dayOfMonth, {bool prevMonth = false}) async {
      await tester.tap(find.byKey(const Key('entry.date')));
      await tester.pumpAndSettle();
      expect(find.text('Próximo pago'), findsOneWidget);
      if (prevMonth) {
        await tester.tap(find.byTooltip('Previous month'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.descendant(of: find.byType(DatePickerDialog), matching: find.text('$dayOfMonth')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
    }

    testWidgets('lista vacía: "Sin recordatorios" y "Nuevo recordatorio"', (tester) async {
      await pumpList(tester);
      expect(find.text('Sin recordatorios'), findsOneWidget);
      expect(find.text('Nuevo recordatorio'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('crear: solo el recordatorio (ningún gasto), con la fecha elegida como ancla', (tester) async {
      final host = await pumpList(tester);
      await openNew(tester);
      expect(find.text('Recordatorio'), findsOneWidget);
      expect(find.text('Guardar recordatorio'), findsOneWidget);
      expect(find.text('Cada mes'), findsOneWidget, reason: 'por defecto');
      expect(find.text('dom 8 nov'), findsOneWidget, reason: 'D4: un mes desde hoy');
      await keys(tester, '45');
      await tester.tap(find.byKey(const Key('pick.vivienda')));
      await pickDue(tester, 15);
      expect(find.text('dom 15 nov'), findsOneWidget);
      await save(tester);
      final r = await host.db.select(host.db.recurrences).getSingle();
      expect((r.amountCents, r.categoryId, r.frequency, r.nextDue, r.anchorDay),
          (4500, 'vivienda', Frequency.monthly, '2026-11-15', 15));
      expect(await host.db.select(host.db.entries).get(), isEmpty, reason: 'desde Ajustes no se crea gasto');
      expect(host.notifier.scheduled[r.notificationId * 10]!.at, DateTime(2026, 11, 12, 9));
      expect(find.byType(RemindersScreen), findsOneWidget);
      expect(find.text('Cada mes · próximo 15 nov'), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('frecuencia obligatoria: sin "Nunca"; "Cada año" se guarda', (tester) async {
      final host = await pumpList(tester);
      await openNew(tester);
      await tester.tap(find.byKey(const Key('entry.repeat')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('repeat.never')), findsNothing);
      await tester.tap(find.byKey(const Key('repeat.yearly')));
      await tester.pumpAndSettle();
      expect(find.text('Cada año'), findsOneWidget);
      await keys(tester, '350');
      await save(tester);
      expect((await host.db.select(host.db.recurrences).getSingle()).frequency, Frequency.yearly);
      await unmount(tester);
    });

    testWidgets('permiso: se pide al guardar; si se niega, se guarda igual y la lista avisa', (tester) async {
      final host = await pumpList(tester, granted: false);
      host.notifier.grantOnRequest = false;
      await openNew(tester);
      expect(host.notifier.requests, 0, reason: 'no al abrir');
      await keys(tester, '20');
      await save(tester);
      expect(host.notifier.requests, 1);
      expect(await host.db.select(host.db.recurrences).get(), hasLength(1));
      expect(find.byKey(const Key('reminders.noPermission')), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('no toca el borrador del registro', (tester) async {
      final host = await pumpList(tester);
      await openNew(tester);
      await keys(tester, '12');
      await tester.tap(find.byKey(const Key('entry.close')));
      await tester.pumpAndSettle(const Duration(seconds: 1));
      expect(host.prefs.getString('draft.expense'), isNull);
      expect(await host.db.select(host.db.recurrences).get(), isEmpty, reason: 'cerrar no guarda');
      await unmount(tester);
    });

    testWidgets('editar: el calendario no deja días pasados; la fecha nueva reprograma', (tester) async {
      final host = await pumpList(tester);
      final r = await host.db.insertRecurrence(
          id: 'r1', amountCents: 4500, categoryId: 'vivienda', note: 'Internet', frequency: Frequency.monthly,
          firstDay: day(2026, 9, 8)); // próximo: hoy, 8 oct
      await tester.pumpAndSettle();
      await openEditor(tester, 'r1');
      expect(find.text('Recordatorio'), findsOneWidget);
      expect(find.text('Guardar cambios'), findsOneWidget);
      expect(find.text('jue 8 oct'), findsOneWidget);
      await pickDue(tester, 7); // ayer: deshabilitado
      expect(find.text('jue 8 oct'), findsOneWidget);
      await pickDue(tester, 20);
      await save(tester);
      final after = await host.db.select(host.db.recurrences).getSingle();
      expect((after.nextDue, after.anchorDay), ('2026-10-20', 20));
      expect(host.notifier.scheduled[r.notificationId * 10]!.at, DateTime(2026, 10, 17, 9));
      expect(await host.db.select(host.db.entries).get(), isEmpty);
      await unmount(tester);
    });

    testWidgets('320×568 dp, letra ×1.3: frecuencia, fecha y nota visibles sin scroll', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpList(tester, size: const Size(320, 568));
      await openNew(tester);
      expect(tester.takeException(), isNull, reason: 'overflow');
      for (final k in ['entry.repeat', 'entry.date', 'entry.addNote', 'entry.save']) {
        expect(find.byKey(Key(k)).hitTestable(), findsOneWidget, reason: '$k tapado o fuera de la vista');
      }
      final firstChip = tester.getRect(find.byKey(const Key('pick.comida'))).top;
      expect(tester.getRect(find.byKey(const Key('entry.date'))).top, lessThan(firstChip),
          reason: 'la fila de ajustes va antes de las categorías');
      // Las categorías de abajo quedan bajo el teclado: la barra avisa y con
      // scroll se llega a la última.
      final scroll = tester.state<ScrollableState>(
          find.descendant(of: find.byKey(const Key('entry.scroll')), matching: find.byType(Scrollable)));
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(tester.widget<Scrollbar>(find.byKey(const Key('entry.scrollbar'))).thumbVisibility, isTrue);
      await tester.scrollUntilVisible(find.byKey(const Key('pick.otros')), 50,
          scrollable: find.descendant(of: find.byKey(const Key('entry.scroll')), matching: find.byType(Scrollable)));
      await tester.tap(find.byKey(const Key('pick.otros')));
      await tester.pump();
      await unmount(tester);
    });
  });

  group('fix5: Por pagar, acciones y estado', () {
    /// Home con datos (hoy: 8 oct 2026) y recordatorios con su próximo pago.
    Future<AppDatabase> home(WidgetTester tester, Map<String, DateTime> dues,
        {Size size = const Size(411, 914), int cents = 4500}) async {
      final seed = await h.seeded(Mode.variable);
      for (final (i, MapEntry(key: id, value: due)) in dues.entries.indexed) {
        await seed.db.insertRecurrence(
            id: id, amountCents: cents + i, categoryId: 'vivienda', note: id, frequency: Frequency.monthly, firstDue: due);
      }
      await st.pumpApp(tester, seed, size: size);
      return seed.db;
    }

    Finder status(String text) => find.descendant(of: find.byKey(const Key('home.due')), matching: find.text(text));
    Color colorOf(WidgetTester tester, Finder f) => tester.widget<Text>(f).style!.color!;

    testWidgets('sin pagos cerca no aparece', (tester) async {
      await home(tester, {'lejos': day(2026, 10, 16)}); // en 8 días
      expect(find.byKey(const Key('home.due')), findsNothing);
      await h.unmount(tester);
    });

    testWidgets('filas: vencidos primero, estado y color por días; máximo 3 y "Ver todos (N)"', (tester) async {
      await home(tester, {
        'luz': day(2026, 10, 11), // en 3 días
        'agua': day(2026, 10, 15), // en 7 días: entra, pero es la cuarta
        'gym': day(2026, 10, 8), // hoy
        'cable': day(2026, 9, 8), // vencido hace 30 días: sep y oct pendientes
        'lejos': day(2026, 10, 16), // en 8 días: no
      });
      expect(find.text('Por pagar'), findsOneWidget);
      final rows = ['cable', 'gym', 'luz'];
      for (final id in rows) {
        expect(find.byKey(Key('home.due.$id')), findsOneWidget);
      }
      expect(find.byKey(const Key('home.due.agua')), findsNothing, reason: 'máximo 3');
      final tops = [for (final id in rows) tester.getRect(find.byKey(Key('home.due.$id'))).top];
      expect(tops, [...tops]..sort(), reason: 'el más viejo arriba');
      final p = Palette.light;
      expect(colorOf(tester, status('vencido hace 30 días · 2 pagos pendientes')), p.expenseFg);
      expect(colorOf(tester, status('vence hoy')), p.expenseFg);
      expect(colorOf(tester, status('en 3 días')), p.amberFg);
      expect(find.text('Ver todos (5)'), findsOneWidget);
      await tester.tap(find.text('Ver todos (5)'));
      await tester.pumpAndSettle();
      expect(find.byType(RemindersScreen), findsOneWidget);
      expect(find.text('Cada mes · en 7 días'), findsOneWidget, reason: 'la lista también muestra el estado');
      expect(find.text('Cada mes · próximo 16 oct'), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('a 4-7 días: neutro', (tester) async {
      await home(tester, {'agua': day(2026, 10, 12)});
      expect(colorOf(tester, status('en 4 días')), Palette.light.inkMuted);
      await h.unmount(tester);
    });

    Future<void> openActions(WidgetTester tester, String id) async {
      await tester.ensureVisible(find.byKey(Key('home.due.$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('home.due.$id')));
      await tester.pumpAndSettle();
    }

    testWidgets('acciones: título, estado y las 4 opciones', (tester) async {
      await home(tester, {'Internet': day(2026, 10, 6)});
      await openActions(tester, 'Internet');
      expect(find.text('Internet (Vivienda)'), findsOneWidget);
      expect(find.text('S/ 45.00 · vencido hace 2 días'), findsOneWidget);
      expect(find.text('Cada mes · venció el mar 6 oct'), findsOneWidget);
      for (final label in ['Pagado', 'Saltar este mes', 'Editar', 'Borrar']) {
        expect(find.text(label), findsOneWidget);
      }
      await h.unmount(tester);
    });

    testWidgets('Saltar: avanza sin crear gasto; Deshacer la devuelve', (tester) async {
      final db = await home(tester, {'gym': day(2026, 10, 8)});
      final before = (await db.select(db.entries).get()).length;
      await openActions(tester, 'gym');
      await tester.tap(find.byKey(const Key('reminder.skip')));
      await tester.pumpAndSettle();
      expect((await db.select(db.recurrences).getSingle()).nextDue, '2026-11-08');
      expect((await db.select(db.entries).get()).length, before);
      expect(find.text('Saltado. Próximo: 8 nov'), findsOneWidget);
      expect(find.byKey(const Key('home.due')), findsNothing, reason: 'ya no está por pagar');
      await tester.tap(find.text('Deshacer'));
      await tester.pumpAndSettle();
      expect((await db.select(db.recurrences).getSingle()).nextDue, '2026-10-08');
      expect(find.byKey(const Key('home.due.gym')), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('Pagado sin gasto parecido: hoja precargada; al guardar crea el gasto y avanza', (tester) async {
      final db = await home(tester, {'gym': day(2026, 10, 8)}, cents: 7777);
      final before = (await db.select(db.entries).get()).length;
      await openActions(tester, 'gym');
      await tester.tap(find.byKey(const Key('reminder.pay')));
      await tester.pumpAndSettle();
      expect(find.text('¿Ya lo registraste?'), findsNothing);
      expect(find.descendant(of: find.byKey(const Key('entry.amount')), matching: find.text('S/ 77.77')), findsOneWidget);
      await save(tester);
      expect((await db.select(db.entries).get()).length, before + 1);
      expect((await db.select(db.recurrences).getSingle()).nextDue, '2026-11-08');
      await h.unmount(tester);
    });

    testWidgets('E1 Pagado con gasto parecido: "Sí, es ese" avanza sin crear otro; "Registrar otro" abre la hoja',
        (tester) async {
      final db = await home(tester, {'gym': day(2026, 10, 8)}, cents: 7777);
      await db.insertManualEntry(
          id: 'pagado', kind: EntryKind.expense, amountCents: 7777, day: day(2026, 10, 5), pickId: 'vivienda',
          now: DateTime(2026, 10, 5));
      await tester.pumpAndSettle();
      final before = (await db.select(db.entries).get()).length;
      await openActions(tester, 'gym');
      await tester.tap(find.byKey(const Key('reminder.pay')));
      await tester.pumpAndSettle();
      expect(find.text('¿Ya lo registraste?'), findsOneWidget);
      expect(find.text('Anotaste S/ 77.77 en Vivienda el 5 oct.'), findsOneWidget);
      await tester.tap(find.text('Registrar otro'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('entry.save')), findsOneWidget, reason: 'la hoja precargada');
      await tester.tap(find.byKey(const Key('entry.close')));
      await tester.pumpAndSettle();
      expect((await db.select(db.recurrences).getSingle()).nextDue, '2026-10-08', reason: 'cerrar no paga');
      await openActions(tester, 'gym');
      await tester.tap(find.byKey(const Key('reminder.pay')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sí, es ese'));
      await tester.pumpAndSettle();
      expect((await db.select(db.recurrences).getSingle()).nextDue, '2026-11-08');
      expect((await db.select(db.entries).get()).length, before, reason: 'no crea otro gasto');
      await h.unmount(tester);
    });

    testWidgets('Borrar confirma y lo quita', (tester) async {
      final db = await home(tester, {'gym': day(2026, 10, 8)});
      await openActions(tester, 'gym');
      await tester.tap(find.byKey(const Key('reminder.delete')));
      await tester.pumpAndSettle();
      expect(find.text('¿Borrar este recordatorio?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reminders.delete.confirm')));
      await tester.pumpAndSettle();
      expect(await db.select(db.recurrences).get(), isEmpty);
      expect(find.byKey(const Key('home.due')), findsNothing);
      await h.unmount(tester);
    });

    testWidgets('Editar un vencido: el calendario abre en hoy y no deja días pasados', (tester) async {
      final db = await home(tester, {'gym': day(2026, 10, 6)});
      await openActions(tester, 'gym');
      await tester.tap(find.byKey(const Key('reminder.edit')));
      await tester.pumpAndSettle();
      expect(find.text('mar 6 oct'), findsOneWidget);
      await tester.tap(find.byKey(const Key('entry.date')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final dialog = find.byType(DatePickerDialog);
      await tester.tap(find.descendant(of: dialog, matching: find.text('7')));
      await tester.tap(find.descendant(of: dialog, matching: find.text('Aceptar')));
      await tester.pumpAndSettle();
      expect(find.text('jue 8 oct'), findsOneWidget, reason: 'el 7 está deshabilitado: queda hoy');
      await save(tester);
      expect((await db.select(db.recurrences).getSingle()).nextDue, '2026-10-08');
      await h.unmount(tester);
    });

    testWidgets('320×568 dp, letra ×1.3: el bloque entra y sus filas se tocan', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await home(tester, {'cable': day(2026, 9, 8), 'gym': day(2026, 10, 8)}, size: const Size(320, 568));
      expect(tester.takeException(), isNull, reason: 'overflow');
      await tester.scrollUntilVisible(find.byKey(const Key('home.due.gym')), 100,
          scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.byKey(const Key('home.due.gym')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home.due.gym')).hitTestable(), findsOneWidget, reason: 'no bajo los botones');
      await h.unmount(tester);
    });
  });
}
