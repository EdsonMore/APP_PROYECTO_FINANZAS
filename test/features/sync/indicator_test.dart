import 'dart:async';

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
import 'package:saldo_claro/features/entry/draft_store.dart';
import 'package:saldo_claro/features/home/home_screen.dart';
import 'package:saldo_claro/features/sync/auth_gateway.dart';
import 'package:saldo_claro/features/sync/fake_auth_gateway.dart';
import 'package:saldo_claro/features/sync/providers.dart';
import 'package:saldo_claro/features/sync/push.dart';
import 'package:saldo_claro/features/sync/remote.dart';
import 'package:saldo_claro/features/sync/status.dart';
import 'package:saldo_claro/features/sync/sync_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import '../home/home_screen_test.dart' as h;

late FakeAuthGateway auth;
late FakeSyncRemote remote;

/// El Home con la cuenta y el servidor falsos. [status]: estado fijo (sin
/// motor), para probar cómo se ve cada uno.
Future<h.Seed> pumpHome(
  WidgetTester tester, {
  Stream<SyncStatus>? status,
  Future<void> Function(h.Seed s)? fill,
  ThemeData? theme,
}) async {
  const dpr = 2.625;
  tester.view.physicalSize = const Size(411, 914) * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final seed = await h.seeded(Mode.variable, fill);
  addTearDown(seed.db.close);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(seed.db),
        sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
        todayProvider.overrideWithValue(h.today),
        authGatewayProvider.overrideWithValue(auth),
        syncRemoteProvider.overrideWithValue(remote),
        if (status != null) syncStatusProvider.overrideWith((_) => status),
      ],
      child: MaterialApp(theme: theme ?? AppTheme.light, home: const HomeScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return seed;
}

ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));

Finder icon(SyncState s) => find.byKey(Key('sync.icon.${s.name}'));
final indicator = find.byKey(const Key('sync.indicator'));

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(indicator);
  await tester.pumpAndSettle();
}

Future<void> signedIn() async {
  auth.addAccount('ana@correo.com', 'secreto1');
  await auth.signIn('ana@correo.com', 'secreto1');
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
    auth = FakeAuthGateway();
    remote = FakeSyncRemote();
  });

  group('relativeSyncTime', () {
    final now = DateTime(2026, 10, 13, 14, 30);
    String rel(DateTime? at) => relativeSyncTime(at, now);

    test('sin sync: "Todavía no"', () => expect(rel(null), 'Todavía no'));
    test('menos de un minuto (59 s) y reloj adelantado: "hace un momento"', () {
      expect(rel(now.subtract(const Duration(seconds: 59))), 'hace un momento');
      expect(rel(now.add(const Duration(minutes: 5))), 'hace un momento');
    });
    test('minutos: 60 s → "hace 1 min", 59 min → "hace 59 min"', () {
      expect(rel(now.subtract(const Duration(seconds: 60))), 'hace 1 min');
      expect(rel(now.subtract(const Duration(minutes: 59, seconds: 59))), 'hace 59 min');
    });
    test('horas del mismo día: 60 min → "hace 1 h"', () {
      expect(rel(now.subtract(const Duration(minutes: 60))), 'hace 1 h');
      expect(rel(DateTime(2026, 10, 13, 0, 5)), 'hace 14 h');
    });
    test('pasada la medianoche, menos de una hora sigue en minutos', () {
      expect(relativeSyncTime(DateTime(2026, 10, 12, 23, 50), DateTime(2026, 10, 13, 0, 10)), 'hace 20 min');
    });
    test('ayer: "ayer a las 18:40"', () {
      expect(rel(DateTime(2026, 10, 12, 18, 40)), 'ayer a las 18:40');
      expect(relativeSyncTime(DateTime(2026, 10, 12, 22), DateTime(2026, 10, 13, 0, 30)), 'ayer a las 22:00');
    });
    test('antes de ayer: fecha corta; otro año: con el año', () {
      // Como las demás fechas cortas de la app ('d MMM' en es_PE: sin punto).
      expect(rel(DateTime(2026, 10, 11, 9)), '11 oct');
      expect(rel(DateTime(2025, 12, 31, 9)), '31 dic 2025');
    });
  });

  group('ícono en el header', () {
    for (final (state, color) in [
      (SyncState.syncing, 'inkMuted'),
      (SyncState.ok, 'inkMuted'),
      (SyncState.offline, 'inkMuted'),
      (SyncState.needsLogin, 'expenseFg'),
      (SyncState.needsChoice, 'attention'),
      (SyncState.issues, 'expenseFg'),
    ]) {
      testWidgets('${state.name}: su glifo en $color', (tester) async {
        await signedIn();
        await pumpHome(tester, status: Stream.value(SyncStatus(state, issues: state == SyncState.issues ? 2 : 0)));
        if (state == SyncState.syncing) await tester.pump(spinnerDelay);
        expect(icon(state), findsOneWidget);
        final p = AppTheme.light.extension<Palette>()!;
        final expected = {'inkMuted': p.inkMuted, 'expenseFg': p.expenseFg, 'attention': p.attention}[color];
        final w = tester.widget(icon(state));
        expect(w is Icon ? w.color : (w as CircularProgressIndicator).color, expected);
        await h.unmount(tester);
      });
    }

    testWidgets('off: sin ícono (sin cuenta la app no sincroniza)', (tester) async {
      await pumpHome(tester);
      expect(indicator, findsNothing);
      for (final s in SyncState.values) {
        expect(icon(s), findsNothing);
      }
      await h.unmount(tester);
    });

    testWidgets('modo oscuro: los colores salen de la paleta oscura', (tester) async {
      await signedIn();
      await pumpHome(tester, status: Stream.value(const SyncStatus(SyncState.needsChoice)), theme: AppTheme.dark);
      expect(tester.widget<Icon>(icon(SyncState.needsChoice)).color, AppTheme.dark.extension<Palette>()!.attention);
      await h.unmount(tester);
    });

    testWidgets('C1: badge solo con issues > 1; "9+" desde 10', (tester) async {
      await signedIn();
      final status = StreamController<SyncStatus>();
      addTearDown(status.close);
      await pumpHome(tester, status: status.stream);
      Finder badge(String text) => find.descendant(of: find.byKey(const Key('sync.badge')), matching: find.text(text));

      status.add(const SyncStatus(SyncState.issues, issues: 1));
      await tester.pumpAndSettle();
      expect(icon(SyncState.issues), findsOneWidget);
      expect(find.byKey(const Key('sync.badge')), findsNothing, reason: 'issues(1): sin badge');

      status.add(const SyncStatus(SyncState.issues, issues: 2));
      await tester.pumpAndSettle();
      expect(badge('2'), findsOneWidget);

      status.add(const SyncStatus(SyncState.issues, issues: 10));
      await tester.pumpAndSettle();
      expect(badge('9+'), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('D7: el spinner aparece después de 1 s y se queda al menos 600 ms', (tester) async {
      await signedIn();
      final status = StreamController<SyncStatus>();
      addTearDown(status.close);
      await pumpHome(tester, status: status.stream);
      status.add(const SyncStatus(SyncState.ok));
      await tester.pumpAndSettle();

      // Un sync corto (el polling de 60 s): el header no parpadea.
      status.add(const SyncStatus(SyncState.syncing));
      await tester.pump(const Duration(milliseconds: 300));
      status.add(const SyncStatus(SyncState.ok));
      await tester.pump(const Duration(seconds: 2));
      expect(icon(SyncState.syncing), findsNothing);
      expect(icon(SyncState.ok), findsOneWidget);

      // Uno largo: spinner a los 1 s; termina a los 1.1 s → sigue hasta 1.6 s.
      status.add(const SyncStatus(SyncState.syncing));
      await tester.pump(const Duration(milliseconds: 999));
      expect(icon(SyncState.syncing), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(icon(SyncState.syncing), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 100));
      status.add(const SyncStatus(SyncState.ok));
      await tester.pump(const Duration(milliseconds: 400));
      expect(icon(SyncState.syncing), findsOneWidget, reason: 'mínimo 600 ms');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();
      expect(icon(SyncState.syncing), findsNothing);
      expect(icon(SyncState.ok), findsOneWidget);
      await h.unmount(tester);
    });
  });

  group('hoja', () {
    testWidgets('tocar el ícono abre la hoja: título, última vez y por subir', (tester) async {
      await signedIn();
      final seed = await pumpHome(tester, fill: (s) => s.expense(12, h.ago(1)));
      await container(tester).read(syncEngineProvider).sync();
      await tester.pumpAndSettle();
      expect(icon(SyncState.ok), findsOneWidget);
      await openSheet(tester);
      expect(find.byKey(const Key('syncSheet')), findsOneWidget);
      expect(find.text('Todo sincronizado'), findsOneWidget);
      expect(find.text('hace un momento'), findsOneWidget);
      expect(find.text('Nada'), findsOneWidget);

      // Un cambio nuevo con la hoja abierta: "Por subir" se actualiza solo.
      await seed.expense(5, h.ago(0));
      await tester.pumpAndSettle();
      expect(find.text('1 cambio'), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('"Sincronizar ahora" sincroniza (D5: la hoja queda abierta, sin snackbar)', (tester) async {
      await signedIn();
      await pumpHome(tester, fill: (s) => s.expense(12, h.ago(1)));
      await container(tester).read(syncEngineProvider).sync();
      await tester.pumpAndSettle();
      await openSheet(tester);
      final before = remote.log.length;
      await tester.tap(find.byKey(const Key('account.button.Sincronizar ahora')));
      await tester.pumpAndSettle();
      expect(remote.log.length, greaterThan(before), reason: 'llamó a sync()');
      expect(find.byKey(const Key('syncSheet')), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await h.unmount(tester);
    });

    testWidgets('offline: texto, último sync y cambios por subir', (tester) async {
      await signedIn();
      final seed = await pumpHome(tester);
      await container(tester).read(syncEngineProvider).sync();
      remote.offline = true;
      await seed.expense(5, h.ago(0));
      await seed.expense(6, h.ago(0));
      await container(tester).read(syncEngineProvider).sync();
      await tester.pumpAndSettle();
      expect(icon(SyncState.offline), findsOneWidget);
      await openSheet(tester);
      expect(find.text('Sin conexión'), findsOneWidget);
      expect(
        find.text('Tus cambios se guardan en este teléfono y se subirán cuando vuelva la conexión.'),
        findsOneWidget,
      );
      expect(find.text('hace un momento'), findsOneWidget);
      expect(find.text('2 cambios'), findsOneWidget);
      await h.unmount(tester);
    });

    testWidgets('"Cerrar sesión" solo con sesión; en needsLogin, "Volver a entrar" y "Ahora no"', (tester) async {
      await signedIn();
      await pumpHome(tester);
      await container(tester).read(syncEngineProvider).sync();
      await tester.pumpAndSettle();
      await openSheet(tester);
      expect(find.byKey(const Key('syncSheet.signOut')), findsOneWidget);
      expect(find.byKey(const Key('syncSheet.notNow')), findsNothing);
      Navigator.of(tester.element(find.byKey(const Key('syncSheet')))).pop();
      await tester.pumpAndSettle();

      // La sesión vence y no se puede renovar.
      remote.sessionExpired = true;
      auth.refreshOutcome = RefreshOutcome.invalid;
      await container(tester).read(syncEngineProvider).sync();
      await tester.pumpAndSettle();
      expect(icon(SyncState.needsLogin), findsOneWidget);
      await openSheet(tester);
      expect(find.text('Tu sesión venció'), findsOneWidget);
      expect(find.byKey(const Key('syncSheet.signOut')), findsNothing, reason: 'ya no hay sesión');
      expect(find.byKey(const Key('account.button.Volver a entrar')), findsOneWidget);

      // D8: "Ahora no" cierra la hoja y quita el ícono.
      await tester.tap(find.byKey(const Key('syncSheet.notNow')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('syncSheet')), findsNothing);
      expect(indicator, findsNothing);
      await h.unmount(tester);
    });

    testWidgets('C2: cerrar sesión en needsChoice no pierde datos; off; al volver a entrar se pregunta de nuevo', (
      tester,
    ) async {
      // Otro teléfono ya subió datos a la cuenta; este también tiene.
      final other = AppDatabase(NativeDatabase.memory());
      await other.completeOnboarding(mode: Mode.stable);
      await other.insertManualEntry(
        id: 'nube',
        kind: EntryKind.expense,
        amountCents: 900,
        day: h.ago(2),
        pickId: 'comida',
        now: DateTime(2026, 10, 6),
      );
      await Pusher(other, remote).push();
      await other.close();

      await signedIn();
      final seed = await pumpHome(tester, fill: (s) => s.expense(12, h.ago(1)));
      final engine = container(tester).read(syncEngineProvider);
      await engine.sync();
      await tester.pumpAndSettle();
      expect(icon(SyncState.needsChoice), findsOneWidget);
      final local = [for (final e in await seed.db.select(seed.db.entries).get()) e.id];

      await openSheet(tester);
      expect(find.text('Elige qué datos usar'), findsOneWidget);
      await tester.tap(find.byKey(const Key('syncSheet.signOut')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sync.signOut.confirm')));
      await tester.pumpAndSettle();

      expect([for (final e in await seed.db.select(seed.db.entries).get()) e.id], local, reason: 'los datos se quedan');
      expect(engine.status.state, SyncState.off);
      expect(indicator, findsNothing);
      expect(await seed.db.neverSynced(), isTrue);

      await auth.signIn('ana@correo.com', 'secreto1');
      expect((await engine.sync()).state, SyncState.needsChoice, reason: 'se pregunta de nuevo');
      await h.unmount(tester);
    });
  });
}
