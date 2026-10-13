import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
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
import 'package:saldo_claro/features/sync/screens/code_screen.dart';
import 'package:saldo_claro/features/sync/screens/credentials_screens.dart';
import 'package:saldo_claro/features/sync/screens/sync_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import '../home/home_screen_test.dart' as h;

late FakeAuthGateway auth;
late FakeSyncRemote remote;

/// La app real (Home) con la cuenta y el servidor falsos; abre Ajustes →
/// "Sincronizar con la nube".
Future<h.Seed> openSync(WidgetTester tester, {Future<void> Function(h.Seed s)? fill}) async {
  const dpr = 2.625;
  tester.view.physicalSize = const Size(411, 914) * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  final seed = await h.seeded(Mode.variable, fill);
  addTearDown(seed.db.close);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(seed.db),
      sharedPreferencesProvider.overrideWithValue(await SharedPreferences.getInstance()),
      todayProvider.overrideWithValue(h.today),
      authGatewayProvider.overrideWithValue(auth),
      syncRemoteProvider.overrideWithValue(remote),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const HomeScreen()),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byTooltip('Ajustes'));
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const Key('settings.sync')));
  await tester.tap(find.byKey(const Key('settings.sync')));
  await tester.pumpAndSettle();
  return seed;
}

Future<void> type(WidgetTester tester, String fieldKey, String text) =>
    tester.enterText(find.descendant(of: find.byKey(Key(fieldKey)), matching: find.byType(TextField)), text);

Future<void> press(WidgetTester tester, String label) async {
  final b = find.byKey(Key('account.button.$label'));
  await tester.ensureVisible(b);
  await tester.tap(b);
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<int> pending(h.Seed s) async =>
    (await s.db.customSelect('SELECT COUNT(*) AS n FROM entries WHERE synced_at IS NULL OR synced_at < updated_at').getSingle())
        .read<int>('n');

/// Otro teléfono ya subió su semilla, sus ajustes y el movimiento [id].
Future<void> cloudHas(String id) async {
  final other = AppDatabase(NativeDatabase.memory());
  await other.completeOnboarding(mode: Mode.stable);
  await other.insertManualEntry(
      id: id, kind: EntryKind.expense, amountCents: 900, day: day(2026, 10, 8), pickId: 'comida', now: DateTime(2026, 10, 8));
  await Pusher(other, remote).push();
  await other.close();
}

Future<void> signIn(WidgetTester tester) async {
  await tapKey(tester, 'sync.signIn');
  await type(tester, 'signIn.email', 'ana@correo.com');
  await type(tester, 'signIn.password', 'secreto1');
  await press(tester, 'Entrar');
}

Future<List<String>> entryIds(h.Seed s) async => [for (final e in await s.db.select(s.db.entries).get()) e.id]..sort();

Future<void> signUpUntilCode(WidgetTester tester, {String email = 'ana@correo.com'}) async {
  await press(tester, 'Crear cuenta');
  await type(tester, 'signUp.email', email);
  await type(tester, 'signUp.password', 'secreto1');
  await type(tester, 'signUp.repeat', 'secreto1');
  await press(tester, 'Crear cuenta');
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

  testWidgets('fila de Ajustes y pantalla sin cuenta', (tester) async {
    await openSync(tester);
    expect(find.text('Sincronizar con la nube'), findsOneWidget);
    expect(find.byKey(const Key('account.button.Crear cuenta')), findsOneWidget);
    expect(find.byKey(const Key('sync.signIn')), findsOneWidget);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byKey(const Key('settings.sync')), matching: find.text('Sin cuenta')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('settings.sync')), matching: find.text('Activar')), findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('crear cuenta: código malo da error; el bueno conecta y SUBE todo (D2)', (tester) async {
    final seed = await openSync(tester, fill: (s) => s.expense(12, h.ago(1)));
    await signUpUntilCode(tester);
    expect(find.byType(CodeScreen), findsOneWidget);
    expect(find.text('Te enviamos un código de 6 dígitos a ana@correo.com.'), findsOneWidget);

    await type(tester, 'code.field', '000000');
    await press(tester, 'Confirmar');
    expect(find.text('El código no es válido o venció. Pide uno nuevo.'), findsOneWidget);

    await type(tester, 'code.field', '123456');
    await press(tester, 'Confirmar');
    expect(find.byType(SyncScreen), findsOneWidget);
    expect(find.text('Cuenta creada. Tus datos ya están en la nube.'), findsOneWidget);
    expect(find.text('Conectado como ana@correo.com'), findsOneWidget);
    expect(remote.rows['entries'], hasLength(1));
    expect(await pending(seed), 0);
    await h.unmount(tester);
  });

  testWidgets('crear cuenta: validaciones antes de llamar al servidor', (tester) async {
    await openSync(tester);
    await press(tester, 'Crear cuenta');
    await type(tester, 'signUp.email', 'ana');
    await type(tester, 'signUp.password', '123');
    await type(tester, 'signUp.repeat', '1234');
    await press(tester, 'Crear cuenta');
    expect(find.text('Escribe un correo válido.'), findsOneWidget);
    expect(find.text('Mínimo 6 caracteres.'), findsOneWidget);
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    expect(auth.calls, isEmpty);
    await h.unmount(tester);
  });

  testWidgets('crear cuenta con un correo ya registrado: mensaje claro', (tester) async {
    auth.addAccount('ana@correo.com', 'otra123');
    await openSync(tester);
    await signUpUntilCode(tester);
    expect(find.text("Ya existe una cuenta con ese correo. Usa 'Ya tengo cuenta'."), findsOneWidget);
    expect(find.byType(CodeScreen), findsNothing);
    await h.unmount(tester);
  });

  testWidgets('ya tengo cuenta, con datos en la nube y en el teléfono: pregunta (D5) sin subir nada; "Unir" junta todo',
      (tester) async {
    auth.addAccount('ana@correo.com', 'secreto1');
    await cloudHas('nube1');
    final seed = await openSync(tester, fill: (s) => s.expense(12, h.ago(1)));
    final mine = await entryIds(seed);
    await tapKey(tester, 'sync.signIn');
    await type(tester, 'signIn.email', 'ana@correo.com');
    await type(tester, 'signIn.password', 'mala');
    await press(tester, 'Entrar');
    expect(find.text('Correo o contraseña incorrectos.'), findsOneWidget);
    await type(tester, 'signIn.password', 'secreto1');
    remote.upsertCalls.clear();
    await press(tester, 'Entrar');
    expect(find.byType(ChoiceScreen), findsOneWidget);
    expect(find.text('Tu cuenta ya tiene datos'), findsOneWidget);
    expect(remote.upsertCalls, isEmpty, reason: 'nada sube antes de elegir');

    await press(tester, 'Unir con los de este teléfono');
    expect(find.text('Listo. Tus datos se unieron con los de tu cuenta.'), findsOneWidget);
    expect(await entryIds(seed), ([...mine, 'nube1']..sort()));
    expect(remote.rows['entries']!.keys.toSet(), {...mine, 'nube1'});
    expect(find.textContaining('próxima versión'), findsNothing, reason: 'el aviso C1 ya no existe');
    await h.unmount(tester);
  });

  testWidgets('D5 "Usar solo los de la nube": confirma y reemplaza lo del teléfono; "Volver" sin elegir deja la opción en Sincronizar',
      (tester) async {
    auth.addAccount('ana@correo.com', 'secreto1');
    await cloudHas('nube1');
    final seed = await openSync(tester, fill: (s) => s.expense(12, h.ago(1)));
    await signIn(tester);
    expect(find.byType(ChoiceScreen), findsOneWidget);
    await tester.tap(find.byTooltip('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('Tu cuenta ya tiene datos.'), findsOneWidget);
    await press(tester, 'Elegir qué datos usar');

    await tapKey(tester, 'choice.cloud');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(await entryIds(seed), isNot(['nube1']), reason: 'cancelar no borra');
    await tapKey(tester, 'choice.cloud');
    await tapKey(tester, 'choice.cloud.confirm');
    expect(find.text('Listo. Ahora ves los datos de tu cuenta.'), findsOneWidget);
    expect(await entryIds(seed), ['nube1']);
    await h.unmount(tester);
  });

  testWidgets('ya tengo cuenta con la nube vacía: sube todo sin preguntar; el estado y "Sincronizar ahora" se ven',
      (tester) async {
    auth.addAccount('ana@correo.com', 'secreto1');
    final seed = await openSync(tester, fill: (s) => s.expense(12, h.ago(1)));
    await signIn(tester);
    expect(find.text('Entraste a tu cuenta.'), findsOneWidget);
    expect(find.textContaining('Sincronizado a las '), findsOneWidget);
    expect(await pending(seed), 0);
    expect(remote.rows['entries'], hasLength(1));

    await seed.db.insertManualEntry(
        id: 'nuevo', kind: EntryKind.expense, amountCents: 300, day: h.today, pickId: 'comida', now: DateTime.now());
    await press(tester, 'Sincronizar ahora');
    await tester.pumpAndSettle();
    expect(remote.rows['entries']!.keys, contains('nuevo'));
    await h.unmount(tester);
  });

  testWidgets('sesión vencida sin poder renovarla: "Tu sesión venció. Vuelve a entrar." y los datos se quedan', (tester) async {
    auth.addAccount('ana@correo.com', 'secreto1');
    final seed = await openSync(tester, fill: (s) => s.expense(12, h.ago(1)));
    await signIn(tester);
    remote.sessionExpired = true;
    auth.refreshOutcome = RefreshOutcome.invalid;
    await press(tester, 'Sincronizar ahora');
    await tester.pumpAndSettle();
    expect(find.text('Tu sesión venció. Vuelve a entrar.'), findsOneWidget);
    expect(find.byKey(const Key('sync.signIn')), findsOneWidget);
    expect(await seed.db.select(seed.db.entries).get(), hasLength(1));
    await h.unmount(tester);
  });

  testWidgets('C3: si la operación vence, se avisa (sin spinner eterno)', (tester) async {
    auth.addAccount('ana@correo.com', 'secreto1');
    await openSync(tester);
    await tapKey(tester, 'sync.signIn');
    await type(tester, 'signIn.email', 'ana@correo.com');
    await type(tester, 'signIn.password', 'secreto1');
    auth.nextFailure = const AuthFailure(AuthFailureKind.timeout);
    await press(tester, 'Entrar');
    expect(find.text('La conexión está tardando demasiado. Intenta de nuevo.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await h.unmount(tester);
  });

  testWidgets('olvidé mi contraseña: correo → código → contraseña nueva', (tester) async {
    auth.addAccount('ana@correo.com', 'vieja12');
    await openSync(tester);
    await tapKey(tester, 'sync.signIn');
    await type(tester, 'signIn.email', 'ana@correo.com');
    await tapKey(tester, 'signIn.forgot');
    await press(tester, 'Enviar código');
    expect(auth.calls, contains('sendRecoveryCode'));
    await type(tester, 'code.field', '123456');
    await press(tester, 'Confirmar');
    await type(tester, 'newPassword.password', 'nueva123');
    await type(tester, 'newPassword.repeat', 'otra123');
    await press(tester, 'Guardar contraseña');
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    await type(tester, 'newPassword.repeat', 'nueva123');
    await press(tester, 'Guardar contraseña');
    expect(find.text('Contraseña actualizada. Ya entraste a tu cuenta.'), findsOneWidget);
    expect(find.text('Conectado como ana@correo.com'), findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('reenviar código: recién a los 60 s', (tester) async {
    await openSync(tester);
    await signUpUntilCode(tester);
    expect(find.byKey(const Key('code.resend')), findsNothing);
    expect(find.byKey(const Key('code.wait')), findsOneWidget);
    await tester.pump(resendWait);
    await tester.pumpAndSettle();
    await tapKey(tester, 'code.resend');
    expect(auth.calls.last, 'resendSignupCode');
    await h.unmount(tester);
  });

  testWidgets('cerrar sesión: confirma, conserva los datos y todo vuelve a quedar pendiente', (tester) async {
    final seed = await openSync(tester, fill: (s) => s.expense(12, h.ago(1)));
    await signUpUntilCode(tester);
    await type(tester, 'code.field', '123456');
    await press(tester, 'Confirmar');
    expect(await pending(seed), 0);

    await tapKey(tester, 'sync.signOut');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(auth.currentEmail, 'ana@correo.com', reason: 'cancelar no cierra');

    await tapKey(tester, 'sync.signOut');
    await tapKey(tester, 'sync.signOut.confirm');
    expect(auth.currentEmail, isNull);
    expect(find.text('Sesión cerrada. Tus datos siguen en este teléfono.'), findsOneWidget);
    expect(await seed.db.select(seed.db.entries).get(), hasLength(1), reason: 'los datos se quedan');
    expect(await pending(seed), 1, reason: 'otra cuenta recibirá todo');
    await h.unmount(tester);
  });

  testWidgets('borrar cuenta: "borrar" no habilita; "BORRAR" sí; borra, desconecta y conserva los datos', (tester) async {
    final seed = await openSync(tester, fill: (s) => s.expense(12, h.ago(1)));
    await signUpUntilCode(tester);
    await type(tester, 'code.field', '123456');
    await press(tester, 'Confirmar');
    await tapKey(tester, 'sync.delete');

    FilledButton button() => tester.widget<FilledButton>(find.byKey(const Key('account.button.Borrar cuenta')));
    expect(button().onPressed, isNull);
    await type(tester, 'delete.field', 'borrar');
    await tester.pump();
    expect(button().onPressed, isNull, reason: 'tiene que ser exacto');
    await type(tester, 'delete.field', 'BORRAR');
    await tester.pump();
    expect(button().onPressed, isNotNull);
    expect(find.textContaining('saldoclaro.oficial@gmail.com'), findsOneWidget);

    await press(tester, 'Borrar cuenta');
    expect(auth.calls, contains('deleteAccount'));
    expect(auth.hasAccount('ana@correo.com'), isFalse);
    expect(find.text('Cuenta borrada. Tus datos siguen en este teléfono.'), findsOneWidget);
    expect(find.byKey(const Key('account.button.Crear cuenta')), findsOneWidget, reason: 'vuelve a "sin cuenta"');
    expect(await seed.db.select(seed.db.entries).get(), hasLength(1));
    expect(await pending(seed), 1);
    await h.unmount(tester);
  });

  test('nada de la cuenta se imprime: sin print/debugPrint en lib/features/sync; Supabase con debug: false', () {
    for (final f in Directory('lib/features/sync').listSync(recursive: true).whereType<File>()) {
      final s = f.readAsStringSync();
      expect(s, isNot(contains('print(')), reason: f.path);
    }
    expect(File('lib/main.dart').readAsStringSync(), contains('debug: false'));
  });
}
