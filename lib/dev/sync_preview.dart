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
import '../features/home/home_screen.dart';
import '../features/sync/fake_auth_gateway.dart';
import '../features/sync/providers.dart';
import '../features/sync/push.dart';
import '../features/sync/remote.dart';
import '../features/sync/status.dart';
import '../features/sync/sync_indicator.dart';

/// Vista previa del ícono de sync (3D) para capturas, sin red ni Supabase:
/// base en memoria, cuenta y servidor falsos, estado fijo.
/// Variante por la ruta inicial (un solo APK para todas las capturas):
/// `adb shell am start -n com.saldoclar.app/.MainActivity --es route /offline-dark-sheet`
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_PE');
  Intl.defaultLocale = 'es_PE';
  final route = PlatformDispatcher.instance.defaultRouteName.replaceFirst('/', '').split('-');
  final state = SyncState.values.byName(route.first.isEmpty ? 'ok' : route.first);
  final dark = route.contains('dark'), sheet = route.contains('sheet');
  final now = DateTime.now();
  final today = day(now.year, now.month, now.day);

  final db = AppDatabase(NativeDatabase.memory());
  await db.completeOnboarding(mode: Mode.variable);
  await db.setOpeningBalance(cents: 120000, at: now.subtract(const Duration(days: 15)));
  var n = 0;
  Future<void> spend(int soles, int daysAgo, String cat) => db.insertManualEntry(
    id: 'p${n++}',
    kind: EntryKind.expense,
    amountCents: soles * 100,
    day: today.subtract(Duration(days: daysAgo)),
    pickId: cat,
    now: now,
  );
  await db.insertManualEntry(
    id: 'i0',
    kind: EntryKind.income,
    amountCents: 80000,
    day: today.subtract(const Duration(days: 10)),
    pickId: 'chamba',
    now: now,
  );
  for (var i = 0; i < 14; i++) {
    await spend(18 + i % 3 * 6, i, ['comida', 'transporte', 'comida', 'ocio'][i % 4]);
  }
  final auth = FakeAuthGateway()..addAccount('ana@correo.com', 'secreto1');
  if (state != SyncState.needsLogin) await auth.signIn('ana@correo.com', 'secreto1');
  final remote = FakeSyncRemote();
  await Pusher(db, remote).push(); // todo subido: "Por subir: Nada"
  if (state == SyncState.offline) {
    for (var i = 0; i < 4; i++) {
      await spend(9, 0, 'transporte');
    }
  }
  final status = SyncStatus(
    state,
    lastSyncAt: state == SyncState.offline ? now.subtract(const Duration(hours: 3)) : now,
    issues: 3,
  );

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
        authGatewayProvider.overrideWithValue(auth),
        syncRemoteProvider.overrideWithValue(remote),
        syncStatusProvider.overrideWith((_) => Stream.value(status)),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        initialRoute: '/',
        home: sheet ? const _OpenSheet() : const HomeScreen(),
      ),
    ),
  );
}

class _OpenSheet extends ConsumerStatefulWidget {
  const _OpenSheet();

  @override
  ConsumerState<_OpenSheet> createState() => _OpenSheetState();
}

class _OpenSheetState extends ConsumerState<_OpenSheet> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 800), () {
      if (mounted) showSyncSheet(context, ref);
    });
  }

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
