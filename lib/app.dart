import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'data/providers.dart';
import 'features/home/home_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/reminders/lifecycle.dart';
import 'features/settings/appearance.dart';
import 'features/sync/providers.dart';

class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'SaldoClaro',
      debugShowCheckedModeBanner: false,
      // La app es solo en español: los textos de Material (calendarios,
      // "Aceptar"/"Cancelar") siguen a es_PE aunque el teléfono esté en otro idioma.
      locale: const Locale('es', 'PE'),
      supportedLocales: const [Locale('es', 'PE')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider), // 4E: Sistema / Claro / Oscuro
      // Con "reducir movimiento", el cambio de tema es instantáneo.
      themeAnimationDuration:
          MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : const Duration(milliseconds: 200),
      home: const SyncLifecycle(child: ReminderLifecycle(child: _Root())),
    );
  }
}

/// Monta los disparadores de sync (Fase 3C) mientras la app vive. Sin
/// cuenta no hace nada: ni timers ni red.
class SyncLifecycle extends ConsumerWidget {
  const SyncLifecycle({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncSchedulerProvider);
    return child;
  }
}

/// Sin login ni permisos: onboarding si no terminó, si no Home.
class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(settingsProvider).when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (e, _) => Scaffold(body: Center(child: Text('No se pudo abrir la base local.\n$e'))),
          data: (s) => s?.onboardingDone ?? false ? const ReminderOpener(child: HomeScreen()) : const OnboardingScreen(),
        );
  }
}
