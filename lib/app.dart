import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'data/providers.dart';
import 'core/utils/formatters.dart';
import 'domain/metrics.dart';
import 'features/entry/entry_sheet.dart';
import 'features/onboarding/onboarding_screen.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SaldoClaro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const _Root(),
    );
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
          data: (s) => s?.onboardingDone ?? false ? const _Pending('Home') : const OnboardingScreen(),
        );
  }
}

// ponytail: placeholder hasta el Home real. Los botones "Debug" son temporales
// para el día de uso: el primer commit del Home los borra (tasks/todo.md).
class _Pending extends StatelessWidget {
  const _Pending(this.name);
  final String name;

  Future<void> _register(BuildContext context, EntryKind kind) async {
    final e = await showEntrySheet(context, kind);
    if (e == null || !context.mounted) return;
    final what = kind == EntryKind.expense ? 'Gasto' : 'Ingreso';
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$what de ${Formatters.soles(e.amountCents)} guardado')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('$name — Fase 1b'),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => _register(context, EntryKind.expense),
                child: const Text('Debug: registrar gasto'),
              ),
              TextButton(
                onPressed: () => _register(context, EntryKind.income),
                child: const Text('Debug: registrar ingreso'),
              ),
            ]),
          ),
        ),
      );
}
