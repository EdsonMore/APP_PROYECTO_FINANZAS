import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/budget_bar.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../core/widgets/text_link.dart';
import '../../domain/metrics.dart';
import 'settings_screen.dart';

/// Qué hace cada modo. Lo comparten la hoja de info del Home y la pantalla
/// "Modos de uso". Nunca "sueldo" (SPEC §Reglas duras).
const modeExplanations = {
  Mode.stable: 'Para cuando tus ingresos son predecibles (un pago fijo, la quincena, fin de mes). '
      'El Home te muestra cuánto te queda del presupuesto del mes.',
  Mode.variable: 'Para cuando tus ingresos cambian cada mes (chambas, ventas, freelance). '
      'El Home te dice cuántos días te alcanza con tu ritmo de gasto.',
  Mode.survival: 'Para cuando no tienes ingreso fijo ahora. '
      'El Home te dice cuántos días te quedan y cuánto gastas al día.',
};

/// Nota extra de Variable en "Modos de uso": Mixto se guarda como Variable.
const mixedNote = 'Si elegiste "Mixtos" al empezar, estás en este modo.';

/// Hoja del ícono ⓘ del Home: explica el modo actual. No cambia nada.
Future<void> showModeInfoSheet(BuildContext context, Mode mode) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: false, // el asa es SheetGrabber, como en las demás hojas
    sheetAnimationStyle: reduced
        ? const AnimationStyle(duration: Motion.reducedFade, reverseDuration: Motion.reducedFade)
        : const AnimationStyle(
            duration: Duration(milliseconds: 350), reverseDuration: Duration(milliseconds: 250), curve: Motion.emphasized),
    builder: (sheetContext) {
      final p = sheetContext.palette;
      return SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Column(
            key: const Key('modeInfo.sheet'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SheetGrabber(),
              Semantics(
                header: true,
                child: Text('Modo ${modeLabels[mode]}', style: AppType.title.copyWith(color: p.ink)),
              ),
              const SizedBox(height: Space.md),
              Text(modeExplanations[mode]!, style: AppType.body.copyWith(color: p.ink)),
              Align(
                alignment: Alignment.centerRight,
                child: Transform.translate(
                  offset: const Offset(Space.lg, 0),
                  child: TextLink(
                    key: const Key('modeInfo.seeAll'),
                    label: 'Ver todos los modos',
                    semanticsLabel: 'Ver todos los modos',
                    onTap: () {
                      final nav = Navigator.of(sheetContext);
                      nav.pop();
                      nav.push(MaterialPageRoute<void>(builder: (_) => ModesScreen(current: mode)));
                    },
                  ),
                ),
              ),
              const SizedBox(height: Space.md),
            ],
          ),
        ),
      );
    },
  );
}

/// "Modos de uso": los 3 modos con un ejemplo ficticio del Home; el actual con check.
class ModesScreen extends StatelessWidget {
  const ModesScreen({super.key, required this.current});
  final Mode current;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const Key('modes.scroll'),
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
          children: [
            const SubpageHeader(title: 'Modos de uso'),
            for (final m in Mode.values) _ModeBlock(mode: m, isCurrent: m == current),
            const SizedBox(height: Space.xl),
            Text('Cambia el modo en Ajustes → Modo actual.', style: AppType.caption.copyWith(color: p.inkMuted)),
          ],
        ),
      ),
    );
  }
}

class _ModeBlock extends StatelessWidget {
  const _ModeBlock({required this.mode, required this.isCurrent});
  final Mode mode;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final name = modeLabels[mode]!;
    return Padding(
      key: Key('modes.${mode.name}'),
      padding: const EdgeInsets.only(top: Space.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(
          header: true,
          label: isCurrent ? '$name, modo actual' : name,
          excludeSemantics: true,
          child: Row(children: [
            Expanded(child: Text(name, style: AppType.heading.copyWith(color: p.ink))),
            // Check en ink, no en verde: el verde es el color del ingreso.
            if (isCurrent) Icon(Icons.check, key: Key('modes.current.${mode.name}'), size: 20, color: p.ink),
          ]),
        ),
        const SizedBox(height: Space.sm),
        Text(modeExplanations[mode]!, style: AppType.body.copyWith(color: p.ink)),
        if (mode == Mode.variable) ...[
          const SizedBox(height: Space.xs),
          Text(mixedNote, style: AppType.body.copyWith(color: p.ink)),
        ],
        const SizedBox(height: Space.md),
        Text('Ejemplo', style: AppType.caption.copyWith(color: p.inkMuted)),
        const SizedBox(height: Space.xs),
        _Example(mode: mode),
      ]),
    );
  }
}

/// Datos ficticios (el rótulo "Ejemplo" lo aclara): cómo se ve el número del Home.
class _Example extends StatelessWidget {
  const _Example({required this.mode});
  final Mode mode;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (lead, value, extra) = switch (mode) {
      Mode.stable => ('Te queda', 'S/ 640.00', null),
      Mode.variable => ('Te alcanza para', '~23 días', null),
      Mode.survival => ('Te alcanza para', '~12 días', 'Gastas ~S/ 38.00 al día.'),
    };
    return ExcludeSemantics(
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: p.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(lead, style: AppType.caption.copyWith(color: p.inkMuted)),
          Text(value, style: AppType.display.copyWith(fontSize: 28, color: p.ink)),
          if (mode == Mode.stable) ...[
            const SizedBox(height: Space.sm),
            BudgetBar(key: const Key('modes.example.bar'), percent: 64, over: false, color: p.ink),
          ],
          if (extra != null) ...[
            const SizedBox(height: Space.xs),
            Text(extra, style: AppType.caption.copyWith(color: p.inkMuted)),
          ],
        ]),
      ),
    );
  }
}
