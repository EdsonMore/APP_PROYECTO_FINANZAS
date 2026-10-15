import 'dart:ui' show PlatformDispatcher;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme/app_theme.dart';
import '../data/database.dart';
import '../data/providers.dart';
import '../domain/metrics.dart';
import '../features/ai/ai_client.dart';
import '../features/ai/consent.dart';
import '../features/entry/draft_store.dart';
import '../features/settings/settings_screen.dart';
import '../features/sync/providers.dart';

/// Vista previa de 5C-Infra para capturas: base en memoria, sin red.
/// `adb shell am start -n com.saldoclar.app/.MainActivity --es route /consent`
/// Variantes: consent, noaccount, settings (IA sin activar), settings-on,
/// deactivate; "-dark" para oscuro.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_PE');
  Intl.defaultLocale = 'es_PE';
  final route = PlatformDispatcher.instance.defaultRouteName.replaceFirst('/', '');
  final dark = route.endsWith('-dark');
  final variant = dark ? route.substring(0, route.length - 5) : (route.isEmpty ? 'consent' : route);

  final db = AppDatabase(NativeDatabase.memory());
  await db.completeOnboarding(mode: Mode.variable);
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();
  if (variant == 'settings-on' || variant == 'deactivate') await prefs.setInt('ai.consentVersion', aiConsentVersion);

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      accountEmailProvider.overrideWith((ref) => Stream.value(variant == 'noaccount' ? null : 'tu@correo.com')),
      aiClientProvider.overrideWithValue(FakeAiClient()),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('es', 'PE'),
      supportedLocales: const [Locale('es', 'PE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: switch (variant) {
        'consent' || 'noaccount' => _Auto(open: ensureAiConsent),
        'deactivate' => _Auto(open: showDeactivateAiSheet),
        _ => const SettingsScreen(),
      },
    ),
  ));
}

class _Auto extends StatefulWidget {
  const _Auto({required this.open});
  final Future<Object?> Function(BuildContext) open;

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
  Widget build(BuildContext context) => const SettingsScreen();
}
