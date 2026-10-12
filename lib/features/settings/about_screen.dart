import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'legal_screen.dart';
import 'settings_screen.dart';

/// Debe coincidir con `version:` de pubspec.yaml (lo verifica un test).
const appVersion = '0.2.0';
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
            const SizedBox(height: Space.xl),
            Divider(color: p.border, height: 1),
            SettingsRow(
              key: const Key('about.privacy'),
              label: 'Política de privacidad',
              value: 'Qué datos guarda la app (ninguno)',
              chevron: true,
              onTap: () => _push(context, const LegalScreen(title: 'Política de privacidad', asset: privacyAsset)),
            ),
            SettingsRow(
              key: const Key('about.terms'),
              label: 'Términos y condiciones',
              value: 'Reglas de uso de la app',
              chevron: true,
              onTap: () => _push(context, const LegalScreen(title: 'Términos y condiciones', asset: termsAsset)),
            ),
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

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}
