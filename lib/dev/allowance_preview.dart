import 'dart:ui' show PlatformDispatcher;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app.dart';
import '../core/theme/app_theme.dart';
import '../data/database.dart';
import '../data/providers.dart';
import '../domain/metrics.dart';
import '../features/entry/draft_store.dart';
import '../features/home/allowance_sheet.dart';
import '../features/home/home_screen.dart';
import '../features/settings/appearance.dart';
import '../features/settings/settings_screen.dart';

/// Vista previa de la 4E para capturas: base en memoria, sin red.
/// `adb shell am start -n com.saldoclar.app/.MainActivity --es route /calc-over`
/// Variantes: home-variable|stable|survival, settings, appearance, calc,
/// calc-over, calc-noreserve, forced-dark (la App real con Oscuro guardado);
/// "-dark" fuerza el tema oscuro en las demás.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_PE');
  Intl.defaultLocale = 'es_PE';
  final route = PlatformDispatcher.instance.defaultRouteName.replaceFirst('/', '');
  final dark = route.endsWith('-dark') && route != 'forced-dark';
  final variant = dark ? route.substring(0, route.length - 5) : (route.isEmpty ? 'calc' : route);
  final now = DateTime.now();
  final today = day(now.year, now.month, now.day);
  final mode = switch (variant) {
    'home-stable' => Mode.stable,
    'home-survival' || 'calc-noreserve' => Mode.survival,
    _ => Mode.variable,
  };

  final db = AppDatabase(NativeDatabase.memory());
  await db.completeOnboarding(mode: mode);
  await db.setOpeningBalance(cents: 30000, at: now.subtract(const Duration(days: 1)));
  var n = 0;
  Future<void> spend(int cents, int daysAgo, String cat) => db.insertManualEntry(
        id: 'p${n++}',
        kind: EntryKind.expense,
        amountCents: cents,
        day: today.subtract(Duration(days: daysAgo)),
        pickId: cat,
        now: now.subtract(Duration(minutes: 30 - n)),
      );
  await spend(switch (variant) { 'calc-over' => 2600, 'calc-noreserve' => 31000, _ => 2000 }, 0, 'comida');

  final prefs = await SharedPreferences.getInstance();
  variant == 'forced-dark' ? await prefs.setString(themeModeKey, 'dark') : await prefs.remove(themeModeKey);
  final overrides = [databaseProvider.overrideWithValue(db), sharedPreferencesProvider.overrideWithValue(prefs)];
  if (variant == 'forced-dark') return runApp(ProviderScope(overrides: overrides, child: const App()));

  runApp(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        initialRoute: '/',
        home: switch (variant) {
          'settings' => const SettingsScreen(),
          'appearance' => const _Auto(open: showAppearancePicker, child: SettingsScreen()),
          'calc' || 'calc-over' || 'calc-noreserve' => const _Auto(open: showAllowanceSheet, child: HomeScreen()),
          _ => const HomeScreen(),
        },
      ),
    ),
  );
}

class _Auto extends StatefulWidget {
  const _Auto({required this.open, required this.child});
  final Widget child;
  final Future<void> Function(BuildContext) open;

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
