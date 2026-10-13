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
import '../features/accounts/account_editor.dart';
import '../features/accounts/accounts_screen.dart';
import '../features/accounts/transfer_sheet.dart';
import '../features/entry/draft_store.dart';
import '../features/entry/entry_sheet.dart';
import '../features/history/filters.dart';
import '../features/history/history_screen.dart';
import '../features/home/home_screen.dart';
import '../features/insights/insights_screen.dart';

/// Vista previa de la 4A para capturas: base en memoria, sin red.
/// `adb shell am start -n com.saldoclar.app/.MainActivity --es route /home-dark`
/// Variantes: accounts, editor, entry, transfer, home, history, history-yape,
/// insights; "-dark" para oscuro.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_PE');
  Intl.defaultLocale = 'es_PE';
  final route = PlatformDispatcher.instance.defaultRouteName.replaceFirst('/', '');
  final dark = route.endsWith('-dark');
  final variant = dark ? route.substring(0, route.length - 5) : (route.isEmpty ? 'home' : route);
  final now = DateTime.now();
  final today = day(now.year, now.month, now.day);

  final db = AppDatabase(NativeDatabase.memory());
  await db.completeOnboarding(mode: Mode.variable);
  final start = now.subtract(const Duration(days: 20));
  await db.insertAccount(id: 'yape', name: 'Yape', icon: 'phone_android');
  await db.setAccountOpening('yape', cents: 90000, at: start);
  await db.insertAccount(id: 'bcp', name: 'BCP', icon: 'account_balance');
  await db.setAccountOpening('bcp', cents: 82050, at: start);
  await db.insertAccount(id: 'efectivo', name: 'Efectivo', icon: 'payments');
  await db.insertAccount(id: 'tarjeta', name: 'Tarjeta vieja', icon: 'credit_card');
  await db.setAccountArchived('tarjeta', archived: true);
  var n = 0;
  Future<void> add(int cents, int daysAgo, String pick, String? acc,
          {EntryKind kind = EntryKind.expense, String? note}) =>
      db.insertManualEntry(
        id: 'p${n++}',
        kind: kind,
        amountCents: cents,
        day: today.subtract(Duration(days: daysAgo)),
        pickId: pick,
        note: note,
        now: now.subtract(Duration(days: daysAgo, minutes: 60 - n)),
        accountId: acc,
      );
  await add(80000, 12, 'chamba', 'yape', kind: EntryKind.income, note: 'diseño de logo');
  for (var i = 0; i < 14; i++) {
    await add(1800 + i % 3 * 600, i, ['comida', 'transporte', 'comida', 'ocio'][i % 4], ['yape', 'efectivo', 'bcp'][i % 3]);
  }
  await add(1200, 0, 'comida', 'yape', note: 'menú');
  await db.insertTransfer(
      id: 't1', fromAccountId: 'yape', toAccountId: 'efectivo', amountCents: 10000, day: today, note: 'al bolsillo');
  await db.insertTransfer(id: 't2', fromAccountId: 'bcp', toAccountId: 'yape', amountCents: 25000, day: today.subtract(const Duration(days: 3)));

  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  final accounts = await db.select(db.accounts).get();
  final transfer = await (db.select(db.transfers)..where((t) => t.id.equals('t1'))).getSingle();

  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db), sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        initialRoute: '/',
        home: switch (variant) {
          'accounts' => const AccountsScreen(),
          'editor' => _Auto(
              open: (c) => showAccountEditor(c, all: accounts, existing: accounts.firstWhere((a) => a.id == 'yape')),
              child: const AccountsScreen()),
          'entry' => _Auto(open: (c) => showEntrySheet(c, EntryKind.expense), child: const HomeScreen()),
          'transfer' => _Auto(open: (c) => showTransferSheet(c, editing: transfer), child: const AccountsScreen()),
          'history' => const HistoryScreen(),
          'history-yape' => const HistoryScreen(initial: HistoryFilter(account: (id: 'yape'))),
          'insights' => const InsightsScreen(),
          _ => const HomeScreen(),
        },
      ),
    ),
  );
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
