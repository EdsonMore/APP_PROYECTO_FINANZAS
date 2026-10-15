import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
// No está en el repo (.gitignore): ver README, "Cómo compilar".
import 'core/config/secrets.dart';
import 'features/ai/ai_client.dart';
import 'features/entry/draft_store.dart';
import 'features/reminders/notifier.dart';
import 'features/reminders/service.dart';
import 'features/sync/providers.dart';
import 'features/sync/remote.dart';
import 'features/sync/supabase_auth_gateway.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_PE');
  Intl.defaultLocale = 'es_PE';
  LicenseRegistry.addLicense(_fontLicenses);
  final prefs = await SharedPreferences.getInstance();
  // Sin sesión guardada no hace ninguna llamada de red (solo lee el
  // almacenamiento local). debug: false → nunca imprime logs de auth.
  final supabase = await Supabase.initialize(
    url: Secrets.supabaseUrl,
    publishableKey: Secrets.supabaseAnonKey,
    authOptions: const FlutterAuthClientOptions(detectSessionInUri: false),
    debug: false,
  );
  runApp(ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      authGatewayProvider.overrideWithValue(SupabaseAuthGateway(supabase.client)),
      syncRemoteProvider.overrideWithValue(SupabaseSyncRemote(supabase.client)),
      reminderNotifierProvider.overrideWithValue(PluginReminderNotifier()),
      aiClientProvider.overrideWithValue(SupabaseAiClient(supabase.client)),
    ],
    child: const App(),
  ));
}

/// La OFL exige distribuir la licencia junto con las fuentes.
Stream<LicenseEntry> _fontLicenses() async* {
  for (final font in ['Newsreader', 'Geist']) {
    yield LicenseEntryWithLineBreaks([font], await rootBundle.loadString('assets/fonts/licenses/OFL-$font.txt'));
  }
}
