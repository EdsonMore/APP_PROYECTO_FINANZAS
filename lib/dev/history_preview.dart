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
import '../features/entry/draft_store.dart';
import '../features/entry/entry_sheet.dart';
import '../features/history/filters.dart';
import '../features/history/history_screen.dart';

/// Vista previa del Historial (4B) para capturas: base en memoria, sin red.
/// Variante por la ruta inicial (un solo APK):
/// `adb shell am start -n com.saldoclar.app/.MainActivity --es route /filters-dark`
/// Variantes: empty, all, filters, search, noresults, edit; "-dark" para oscuro.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_PE');
  Intl.defaultLocale = 'es_PE';
  final route = PlatformDispatcher.instance.defaultRouteName.replaceFirst('/', '').split('-');
  final variant = route.first.isEmpty ? 'all' : route.first;
  final dark = route.contains('dark');
  final now = DateTime.now();
  final today = day(now.year, now.month, now.day);

  final db = AppDatabase(NativeDatabase.memory());
  await db.completeOnboarding(mode: Mode.variable);
  var n = 0;
  Future<void> add(int cents, int daysAgo, String pick, {String? note, EntryKind kind = EntryKind.expense}) =>
      db.insertManualEntry(
        id: 'p${n++}',
        kind: kind,
        amountCents: cents,
        day: today.subtract(Duration(days: daysAgo)),
        pickId: pick,
        note: note,
        now: now.subtract(Duration(days: daysAgo, minutes: n)),
      );
  if (variant != 'empty') {
    await add(4200, 0, 'comida', note: 'supermercado Plaza Vea');
    await add(350, 0, 'transporte', note: 'combi');
    await add(1850, 1, 'comida', note: 'supermercado');
    await add(3000, 2, 'ocio', note: 'cine');
    await add(80000, 3, 'chamba', kind: EntryKind.income, note: 'diseño de logo');
    await add(2400, 4, 'comida', note: 'menú');
    await add(12000, 6, 'vivienda', note: 'luz');
    await add(3600, 8, 'comida', note: 'super del mes');
    await add(25000, 12, 'venta', kind: EntryKind.income);
    await add(900, 15, 'transporte');
    await add(5500, 21, 'salud', note: 'farmacia');
    await add(2900, 35, 'comida', note: 'supermercado');
  }
  final initial = switch (variant) {
    'filters' => const HistoryFilter(kind: KindFilter.expense, picks: {'comida'}, preset: RangePreset.thisMonth),
    'search' => const HistoryFilter(query: 'super'),
    'noresults' => const HistoryFilter(kind: KindFilter.income, query: 'super'),
    _ => const HistoryFilter(),
  };

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        initialRoute: '/',
        home: variant == 'edit' ? _OpenEdit(db: db) : HistoryScreen(initial: initial),
      ),
    ),
  );
}

class _OpenEdit extends StatefulWidget {
  const _OpenEdit({required this.db});
  final AppDatabase db;

  @override
  State<_OpenEdit> createState() => _OpenEditState();
}

class _OpenEditState extends State<_OpenEdit> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 800), () async {
      final e = await (widget.db.select(widget.db.entries)..where((e) => e.id.equals('p0'))).getSingle();
      if (mounted) await editEntry(context, e);
    });
  }

  @override
  Widget build(BuildContext context) => const HistoryScreen();
}
