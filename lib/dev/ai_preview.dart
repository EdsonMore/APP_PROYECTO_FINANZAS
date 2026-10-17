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
import '../domain/recurrence.dart';
import '../features/ai/ai_client.dart';
import '../features/ai/chat_screen.dart';
import '../features/ai/consent.dart';
import '../features/entry/draft_store.dart';
import '../features/settings/settings_screen.dart';
import '../features/sync/providers.dart';

/// Vista previa de 5C-Infra para capturas: base en memoria, sin red.
/// `adb shell am start -n com.saldoclar.app/.MainActivity --es route /consent`
/// Variantes: consent, noaccount, settings (IA sin activar), settings-on,
/// deactivate, chat (3 usadas), chat-low (8 usadas: contador en rojo),
/// chat-limit (10 usadas), chat-cuota (respuesta de la cuota); "-dark" para oscuro.
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
  final chat = variant.startsWith('chat');
  if (variant == 'settings-on' || variant == 'deactivate' || chat) {
    await prefs.setInt('ai.consentVersion', aiConsentVersion);
  }
  final now = DateTime.now();
  final today = day(now.year, now.month, now.day);
  if (chat) {
    // Un mes de datos y dos pagos en "Por pagar" (para "¿Qué me conviene pagar primero?").
    await db.insertManualEntry(
        id: 'in', kind: EntryKind.income, amountCents: 250000, day: today.subtract(const Duration(days: 20)),
        pickId: 'chamba', now: now);
    for (var i = 0; i < 20; i++) {
      await db.insertManualEntry(
          id: 'g$i', kind: EntryKind.expense, amountCents: 2500 + i * 90, day: today.subtract(Duration(days: i)),
          pickId: ['comida', 'transporte', 'ocio'][i % 3], now: now);
    }
    await db.insertRecurrence(
        id: 'r1', amountCents: 4500, categoryId: 'vivienda', frequency: Frequency.monthly,
        firstDue: today.add(const Duration(days: 2)));
    await db.insertRecurrence(
        id: 'r2', amountCents: 8700, categoryId: 'vivienda', frequency: Frequency.monthly,
        firstDue: today.add(const Duration(days: 5)));
  }
  final client = FakeAiClient()
    ..used = switch (variant) {
      'chat-low' || 'chat-low-dark' => 8,
      'chat-limit' => 10,
      _ => 3,
    }
    ..next = variant == 'chat-cuota'
        ? const AiAnswer(
            'Sí: con un ingreso promedio de S/ 2,500.00 y un gasto de S/ 1,800.00 al mes, '
            'después de la cuota te sobrarían S/ 600.00 al mes.',
            6)
        : const AiAnswer(
            'Con cuidado: después de la compra te quedarían S/ 42.94 al día, y en 2 días vence Vivienda por S/ 45.00. '
            'Si las zapatillas pueden esperar a tu próximo ingreso, mejor.',
            6);

  runApp(ProviderScope(
    overrides: [
      databaseProvider.overrideWithValue(db),
      sharedPreferencesProvider.overrideWithValue(prefs),
      accountEmailProvider.overrideWith((ref) => Stream.value(variant == 'noaccount' ? null : 'tu@correo.com')),
      aiClientProvider.overrideWithValue(client),
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
        _ when chat => const AiChatScreen(),
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
