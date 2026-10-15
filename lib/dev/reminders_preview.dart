import 'dart:ui' show PlatformDispatcher;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_theme.dart';
import '../data/database.dart';
import '../data/providers.dart';
import '../domain/metrics.dart';
import '../domain/recurrence.dart';
import '../features/entry/draft_store.dart';
import '../features/entry/entry_sheet.dart';
import '../features/home/home_screen.dart';
import '../features/insights/insights_screen.dart';
import '../features/reminders/lifecycle.dart';
import '../features/reminders/notifier.dart';
import '../features/reminders/actions_sheet.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/reminders/service.dart';

/// Vista previa de la 4D para capturas: base en memoria, sin red.
/// `adb shell am start -n com.saldoclar.app/.MainActivity --es route /list-dark`
/// Variantes: insights y suggest (5AB: 8 semanas de datos y Netflix cada 30 días),
/// home, actions, match, entry, list, new, editor, confirm, denied,
/// permission, notify; "-dark" para oscuro. "permission" y "notify" usan el
/// plugin real; "notify" (Internet vencido hace 2 días) adelanta a 20 s el
/// primer aviso pendiente, un "Pago vencido" (el texto y el toque son los reales).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_PE');
  Intl.defaultLocale = 'es_PE';
  final route = PlatformDispatcher.instance.defaultRouteName.replaceFirst('/', '');
  final dark = route.endsWith('-dark');
  final variant = dark ? route.substring(0, route.length - 5) : (route.isEmpty ? 'list' : route);
  final now = DateTime.now();
  final today = day(now.year, now.month, now.day);

  final db = AppDatabase(NativeDatabase.memory());
  await db.completeOnboarding(mode: Mode.variable);
  for (var i = 0; i < 6; i++) {
    await db.insertManualEntry(
        id: 'e$i',
        kind: EntryKind.expense,
        amountCents: 1500 + i * 400,
        day: today.subtract(Duration(days: i)),
        pickId: ['comida', 'transporte', 'ocio'][i % 3],
        now: now.subtract(Duration(days: i)));
  }
  Future<Recurrence> add(String id, int cents, String cat, String? note, Frequency f, int inDays) async {
    final r = await db.insertRecurrence(
        id: id, amountCents: cents, categoryId: cat, note: note, frequency: f, firstDay: today.add(Duration(days: inDays)));
    await db.setRecurrenceDue(id, today.add(Duration(days: inDays)));
    return r;
  }

  // fix5: un vencido, uno hoy, uno a 3 días, uno a 6 (cuarto: queda en "Ver todos") y uno lejos.
  final internet = await add('internet', 4500, 'vivienda', 'Internet', Frequency.monthly, -2);
  if (variant != 'notify') {
    await add('luz', 8700, 'vivienda', 'Luz', Frequency.monthly, 3);
    await add('gym', 8000, 'salud', 'Gimnasio', Frequency.monthly, 6);
    await add('futbol', 2000, 'ocio', 'Fulbito', Frequency.weekly, 0);
    await add('soat', 35000, 'transporte', 'SOAT', Frequency.yearly, 140);
  }
  if (variant == 'insights' || variant == 'suggest') {
    // 8 semanas de comida (sábados más altos), ingresos de este mes y del
    // anterior, Netflix cada 30 días y un cine que hace subir Ocio este mes.
    Future<void> e(String id, int cents, DateTime d, String pick, {EntryKind kind = EntryKind.expense, String? note}) =>
        db.insertManualEntry(id: id, kind: kind, amountCents: cents, day: d, pickId: pick, note: note, now: now);
    for (var i = 0; i < 56; i++) {
      final d = today.subtract(Duration(days: i));
      await e('g$i', d.weekday == DateTime.saturday ? 6500 : 2000, d, 'comida');
    }
    await e('in0', 250000, DateTime.utc(today.year, today.month - 1, 1), 'chamba', kind: EntryKind.income);
    await e('in1', 250000, DateTime.utc(today.year, today.month, 1), 'chamba', kind: EntryKind.income);
    for (final (i, ago) in [61, 31, 1].indexed) {
      await e('nf$i', 2990, today.subtract(Duration(days: ago)), 'ocio', note: 'Netflix');
    }
    await e('cine', 12000, today.subtract(const Duration(days: 2)), 'ocio', note: 'cine');
  }
  if (variant == 'match') {
    await db.insertManualEntry(
        id: 'pagado', kind: EntryKind.expense, amountCents: 4500, day: today.subtract(const Duration(days: 1)),
        pickId: 'vivienda', now: now);
  }
  final reminder = await (db.select(db.recurrences)..where((r) => r.id.equals(internet.id))).getSingle();

  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  final ReminderNotifier notifier = switch (variant) {
    'notify' => _Soon(PluginReminderNotifier()),
    'permission' => PluginReminderNotifier(),
    'denied' => FakeReminderNotifier()
      ..granted = false
      ..grantOnRequest = false,
    _ => FakeReminderNotifier(),
  };

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(prefs),
        reminderNotifierProvider.overrideWithValue(notifier),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        home: ReminderLifecycle(child: switch (variant) {
          'list' || 'suggest' => const RemindersScreen(),
          'insights' => const InsightsScreen(),
          'actions' => _Auto(open: (c) => showReminderActions(c, reminder), child: const HomeScreen()),
          'match' => _Auto(open: (c) => payReminder(c, reminder), child: const HomeScreen()),
          'new' => _Auto(open: (c) => showEntrySheet(c, EntryKind.expense, newReminder: true), child: const RemindersScreen()),
          'editor' => _Auto(
              open: (c) => showEntrySheet(c, EntryKind.expense, editingReminder: reminder),
              child: const RemindersScreen()),
          'confirm' => _Auto(
              open: (c) => showEntrySheet(c, EntryKind.expense, reminder: reminder), child: const HomeScreen()),
          'entry' || 'denied' || 'permission' =>
            _Auto(open: (c) => showEntrySheet(c, EntryKind.expense), child: const HomeScreen()),
          _ => const ReminderOpener(child: HomeScreen()),
        }),
      ),
    ),
  );
}

/// El plugin real, con el primer aviso adelantado a 20 s (los demás, no: la
/// captura muestra uno solo).
class _Soon implements ReminderNotifier {
  _Soon(this._inner);
  final ReminderNotifier _inner;
  bool _sent = false;

  @override
  Future<void> schedule(
      {required int id, required DateTime at, required String title, required String body, required String payload}) async {
    if (_sent) return;
    _sent = true;
    await _inner.schedule(
        id: id, at: DateTime.now().add(const Duration(seconds: 20)), title: title, body: body, payload: payload);
  }

  @override
  Future<void> init(void Function(String payload) onTap) => _inner.init(onTap);
  @override
  Future<String?> launchPayload() => _inner.launchPayload();
  @override
  Future<bool> permissionGranted() => _inner.permissionGranted();
  @override
  Future<bool> requestPermission() => _inner.requestPermission();
  @override
  Future<void> cancel(int id) => _inner.cancel(id);
  @override
  Future<void> cancelAll() => _inner.cancelAll();
  @override
  Future<void> openSettings() => _inner.openSettings();
}

class _Auto extends StatefulWidget {
  const _Auto({required this.open, required this.child});
  final Future<void> Function(BuildContext) open;
  final Widget child;

  @override
  State<_Auto> createState() => _AutoState();
}

class _AutoState extends State<_Auto> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (mounted) widget.open(context);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
