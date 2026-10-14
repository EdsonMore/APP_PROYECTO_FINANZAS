import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
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
      expect(host.notifier.scheduled[r.notificationId]!.at, DateTime(2026, 11, 5, 9));
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

    testWidgets('640 dp: la hoja entra con el chip de Repetir', (tester) async {
      await pumpHost(tester, size: const Size(360, 640));
      await open(tester, 'abrir gasto');
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('entry.repeat')), findsOneWidget);
      expect(find.byKey(const Key('entry.save')).hitTestable(), findsOneWidget);
      await unmount(tester);
    });
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

    testWidgets('tocar edita: cambia la frecuencia y guarda sin crear gastos', (tester) async {
      final db = await openList(tester);
      final before = (await db.select(db.entries).get()).length;
      await tester.tap(find.byKey(const Key('reminders.r1')));
      await tester.pumpAndSettle();
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
}
