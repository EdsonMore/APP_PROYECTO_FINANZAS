import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'settings_screen.dart';

/// Debe coincidir con `version:` de pubspec.yaml (lo verifica un test).
const appVersion = '0.1.0';
const appBuild = 1;

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
          children: [
            const SubpageHeader(title: 'Acerca de'),
            const SizedBox(height: Space.xl),
            Text('SaldoClaro', style: AppType.title.copyWith(color: p.ink)),
            const SizedBox(height: Space.xs),
            Text('Versión $appVersion ($appBuild)', style: AppType.caption.copyWith(color: p.inkMuted)),
            const SizedBox(height: Space.xl),
            Text('Tus datos se guardan solo en este teléfono. SaldoClaro no usa internet.',
                style: AppType.body.copyWith(color: p.ink)),
            const SizedBox(height: Space.md),
            Text('Política de privacidad: llega en la Fase 2.', style: AppType.body.copyWith(color: p.inkMuted)),
            const SizedBox(height: Space.xl),
            Divider(color: p.border, height: 1),
            SettingsRow(
              key: const Key('about.licenses'),
              label: 'Licencias',
              value: 'Fuentes y librerías de código abierto',
              chevron: true,
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'SaldoClaro',
                applicationVersion: '$appVersion ($appBuild)',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
