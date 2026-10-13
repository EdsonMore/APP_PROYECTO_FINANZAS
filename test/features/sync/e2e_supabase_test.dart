import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/sync/push.dart';
import 'package:saldo_claro/features/sync/remote.dart';
import 'package:saldo_claro/features/sync/supabase_auth_gateway.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// De punta a punta contra saldoclaro-test (NUNCA contra producción).
//
// PENDIENTE: necesita el SMTP propio configurado (para crear cuentas reales
// con código). Hasta entonces queda en skip. Para correrlo:
//   1. En saldoclaro-test: Authentication → Add user (Auto Confirm) con un
//      correo y contraseña de prueba.
//   2. Quitar el `skip` de abajo y correr:
//      flutter test test/features/sync/e2e_supabase_test.dart \
//        --dart-define=E2E_URL=<url de saldoclaro-test> \
//        --dart-define=E2E_KEY=<anon key de saldoclaro-test> \
//        --dart-define=E2E_EMAIL=<correo> --dart-define=E2E_PASSWORD=<contraseña>
//   Las claves van por --dart-define: no se escriben en el repo ni se imprimen.
const _skip = 'Pendiente: SMTP propio del usuario (ver tasks/todo.md, Fase 3B)';

const _url = String.fromEnvironment('E2E_URL');
const _key = String.fromEnvironment('E2E_KEY');
const _email = String.fromEnvironment('E2E_EMAIL');
const _password = String.fromEnvironment('E2E_PASSWORD');

void main() {
  test('entrar, subir los datos del teléfono y verlos en el servidor (RLS: solo los propios)', () async {
    if (_url.isEmpty || _key.isEmpty || _email.isEmpty || _password.isEmpty) {
      fail('Faltan los --dart-define E2E_URL, E2E_KEY, E2E_EMAIL y E2E_PASSWORD');
    }
    final client = SupabaseClient(_url, _key);
    final auth = SupabaseAuthGateway(client);
    await auth.signIn(_email, _password);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.completeOnboarding(mode: Mode.variable);
    await db.insertManualEntry(
        id: 'e2e-${DateTime.now().millisecondsSinceEpoch}', kind: EntryKind.expense, amountCents: 1250,
        day: day(2026, 10, 8), pickId: 'comida', now: DateTime.now());

    final r = await Pusher(db, SupabaseSyncRemote(client)).push();
    expect(r.failed, 0, reason: r.errors.map((e) => '${e.table}/${e.id}: ${e.code}').join(', '));
    expect(r.stoppedByNetwork, isFalse);

    final categories = await client.from('categories').select('id');
    expect(categories, hasLength(6), reason: 'RLS: solo las 6 de la semilla de este usuario');
    await auth.signOut();
  }, skip: _skip);
}
