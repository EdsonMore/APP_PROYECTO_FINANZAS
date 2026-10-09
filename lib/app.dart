import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data/providers.dart';

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'SaldoClaro',
      debugShowCheckedModeBanner: false,
      home: _Root(),
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
          data: (s) => s?.onboardingDone ?? false
              ? const _Pending('Home')
              : const _Pending('Onboarding'),
        );
  }
}

// ponytail: placeholder hasta la Fase 1b (pantallas con wireframe aprobado).
class _Pending extends StatelessWidget {
  const _Pending(this.name);
  final String name;

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text('$name — Fase 1b')));
}
