import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../core/widgets/text_link.dart';
import '../entry/draft_store.dart' show sharedPreferencesProvider;
import '../settings/legal_screen.dart';
import '../sync/providers.dart' show accountEmailProvider;
import '../sync/screens/sync_screen.dart';
import 'ai_client.dart';

const _versionKey = 'ai.consentVersion';
const _atKey = 'ai.consentAt';

/// ¿Aceptó la versión vigente? Solo en este teléfono (I5); la función además
/// exige la versión en cada consulta.
final aiConsentProvider = StateProvider<bool>(
    (ref) => ref.watch(sharedPreferencesProvider).getInt(_versionKey) == aiConsentVersion);

/// Antes de cualquier uso de la IA. Sin cuenta (I1), ofrece crearla; sin
/// consentimiento, lo pide. true = puede seguir.
Future<bool> ensureAiConsent(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final email = await container.read(accountEmailProvider.future);
  if (!context.mounted) return false;
  if (email == null) {
    await _sheet<void>(context, (sheet) => const _NoAccountSheet());
    return false;
  }
  if (container.read(aiConsentProvider)) return true;
  final accepted = await _sheet<bool>(context, (sheet) => const _ConsentSheet()) ?? false;
  if (!accepted) return false;
  final prefs = container.read(sharedPreferencesProvider);
  await prefs.setInt(_versionKey, aiConsentVersion);
  await prefs.setString(_atKey, DateTime.now().toIso8601String());
  container.read(aiConsentProvider.notifier).state = true;
  return true;
}

/// I2: Ajustes → Inteligencia artificial → Desactivar. Borra el consentimiento
/// de este teléfono; no toca nada más.
Future<void> showDeactivateAiSheet(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final off = await _sheet<bool>(context, (sheet) => const _DeactivateSheet()) ?? false;
  if (!off) return;
  final prefs = container.read(sharedPreferencesProvider);
  await prefs.remove(_versionKey);
  await prefs.remove(_atKey);
  container.read(aiConsentProvider.notifier).state = false;
}

Future<T?> _sheet<T>(BuildContext context, WidgetBuilder builder) => showModalBottomSheet<T>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          child: builder(sheet),
        ),
      ),
    );

class _ConsentSheet extends StatefulWidget {
  const _ConsentSheet();

  @override
  State<_ConsentSheet> createState() => _ConsentSheetState();
}

class _ConsentSheetState extends State<_ConsentSheet> {
  bool _checked = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetGrabber(),
      Semantics(header: true, child: Text('Antes de usar la IA', style: AppType.title.copyWith(color: p.ink))),
      const SizedBox(height: Space.sm),
      Text(
        'Para responderte, enviamos a Google números resumidos que calcula tu teléfono (totales, promedios, '
        'saldo, pagos pendientes) y tu pregunta. No enviamos tus movimientos uno por uno, tus notas ni tu correo.',
        style: AppType.body.copyWith(color: p.inkMuted),
      ),
      const SizedBox(height: Space.md),
      MergeSemantics(
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Checkbox(
            key: const Key('ai.consent.check'),
            value: _checked,
            onChanged: (v) => setState(() => _checked = v ?? false),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _checked = !_checked),
              child: Padding(
                padding: const EdgeInsets.only(top: Space.md),
                child: Text('Acepto que mis datos agregados se envíen a Google para responder.',
                    style: AppType.body.copyWith(color: p.ink)),
              ),
            ),
          ),
        ]),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextLink(
          key: const Key('ai.consent.policy'),
          label: 'Política de privacidad',
          semanticsLabel: 'Leer la política de privacidad',
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => const LegalScreen(title: 'Política de privacidad', asset: privacyAsset))),
        ),
      ),
      const SizedBox(height: Space.md),
      FilledButton(
        key: const Key('ai.consent.continue'),
        onPressed: _checked ? () => Navigator.of(context).pop(true) : null,
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Space.ctaHeight)),
        child: const Text('Continuar'),
      ),
      TextButton(
        key: const Key('ai.consent.notNow'),
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Ahora no'),
      ),
    ]);
  }
}

class _NoAccountSheet extends StatelessWidget {
  const _NoAccountSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetGrabber(),
      Semantics(
        header: true,
        child: Text('Para usar la IA necesitas una cuenta', style: AppType.title.copyWith(color: p.ink)),
      ),
      const SizedBox(height: Space.sm),
      Text('Así cuidamos el límite de consultas de cada persona.', style: AppType.body.copyWith(color: p.inkMuted)),
      const SizedBox(height: Space.lg),
      FilledButton(
        key: const Key('ai.account.create'),
        onPressed: () {
          final nav = Navigator.of(context);
          nav.pop();
          nav.push(SyncScreen.route());
        },
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Space.ctaHeight)),
        child: const Text('Crear cuenta'),
      ),
      TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Ahora no')),
    ]);
  }
}

class _DeactivateSheet extends StatelessWidget {
  const _DeactivateSheet();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SheetGrabber(),
      Semantics(header: true, child: Text('Desactivar la IA', style: AppType.title.copyWith(color: p.ink))),
      const SizedBox(height: Space.sm),
      Text('Ya no enviaremos nada a Google. Puedes volver a activarla cuando quieras.',
          style: AppType.body.copyWith(color: p.inkMuted)),
      const SizedBox(height: Space.lg),
      FilledButton(
        key: const Key('ai.deactivate'),
        onPressed: () => Navigator.of(context).pop(true),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Space.ctaHeight)),
        child: const Text('Desactivar'),
      ),
    ]);
  }
}
