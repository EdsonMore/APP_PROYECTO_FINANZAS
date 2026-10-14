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
import '../features/reminders/lifecycle.dart';
import '../features/reminders/notifier.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/reminders/service.dart';

/// Vista previa de la 4D para capturas: base en memoria, sin red.
/// `adb shell am start -n com.saldoclar.app/.MainActivity --es route /list-dark`
/// Variantes: entry, list, new, editor, confirm, denied, permission, notify; "-dark"
/// para oscuro. "permission" y "notify" usan el plugin real; "notify" adelanta
/// el aviso a 20 s para capturarlo (el texto y el toque son los reales).
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

  final internet = await add('internet', 4500, 'vivienda', 'Internet', Frequency.monthly, 3);
  if (variant != 'notify') {
    await add('luz', 8700, 'vivienda', 'Luz', Frequency.monthly, 9);
    await add('gym', 8000, 'salud', 'Gimnasio', Frequency.monthly, 16);
    await add('futbol', 2000, 'ocio', 'Fulbito', Frequency.weekly, 2);
    await add('soat', 35000, 'transporte', 'SOAT', Frequency.yearly, 140);
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
          'list' => const RemindersScreen(),
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

/// El plugin real, con el aviso adelantado a 20 s.
class _Soon implements ReminderNotifier {
  _Soon(this._inner);
  final ReminderNotifier _inner;

  @override
  Future<void> schedule(
          {required int id, required DateTime at, required String title, required String body, required String payload}) =>
      _inner.schedule(
          id: id, at: DateTime.now().add(const Duration(seconds: 20)), title: title, body: body, payload: payload);

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
