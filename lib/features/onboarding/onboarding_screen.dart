import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/choice_card.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';

const spaceNameMaxLength = 30;

// El lint no evalúa con `unicode: true`; la regex es válida (cubierta por tests).
// ignore: valid_regexps
final _emoji = RegExp(r'[\p{Extended_Pictographic}\u{FE0F}\u{200D}\u{1F3FB}-\u{1F3FF}\u{1F1E6}-\u{1F1FF}]', unicode: true);

/// Normaliza el nombre del espacio: sin emojis, trim, vacío → null.
/// Error si supera [spaceNameMaxLength] caracteres visibles.
({String? value, String? error}) validateSpaceName(String raw) {
  final v = raw.replaceAll(_emoji, '').trim();
  if (v.isEmpty) return (value: null, error: null);
  if (v.characters.length > spaceNameMaxLength) return (value: null, error: 'Máximo $spaceNameMaxLength caracteres');
  return (value: v, error: null);
}

const _options = [
  (IncomeProfile.stable, 'Estables', 'Me pagan un monto fijo: mensual, quincenal o semanal.'),
  (IncomeProfile.variable, 'Variables', 'Chambas, ventas o freelance. Cambia cada mes.'),
  // Mixto → mode 'variable'. Su "Chamba favorita" ya es la primera fuente (SPEC.md §Modos).
  (IncomeProfile.mixed, 'Mixtos', 'Un monto fijo más extras que varían.'),
  (IncomeProfile.none, 'Sin ingreso fijo ahora', 'Entra plata de vez en cuando, o nada por ahora.'),
];

/// Onboarding de 2 pasos. No escribe nada hasta "Empezar"/"Omitir"; al
/// escribir settings, el root (app.dart) pasa solo al Home.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> with SingleTickerProviderStateMixin {
  /// 0 = paso 1, 1 = paso 2. Spring desde el valor y velocidad actuales: interrumpible.
  late final _ctrl = AnimationController.unbounded(vsync: this);
  final _name = TextEditingController();
  IncomeProfile? _profile;
  int _step = 0;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _name.dispose();
    super.dispose();
  }

  void _go(int step) {
    setState(() => _step = step);
    if (step == 0) FocusScope.of(context).unfocus();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.animateTo(step.toDouble(), duration: Motion.reducedFade);
    } else {
      _ctrl.animateWith(SpringSimulation(Motion.spring, _ctrl.value, step.toDouble(), _ctrl.velocity));
    }
  }

  Future<void> _choose(IncomeProfile p) async {
    setState(() => _profile = p);
    HapticFeedback.selectionClick();
    await Future<void>.delayed(Motion.lightChange); // deja ver el borde/check antes de avanzar
    if (mounted && _step == 0) _go(1);
  }

  Future<void> _finish({required bool withName}) async {
    if (_saving || _profile == null) return;
    String? name;
    if (withName) {
      final r = validateSpaceName(_name.text);
      if (r.error != null) return setState(() => _error = r.error);
      name = r.value;
    }
    setState(() => _saving = true);
    try {
      await ref.read(databaseProvider).completeOnboarding(mode: modeFor(_profile!), spaceName: name);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('No se pudo guardar. Intenta de nuevo.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0);
      },
      child: Scaffold(
        body: SafeArea(
          child: ClipRect(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final t = _ctrl.value.clamp(0.0, 1.0);
                const eps = 1e-3;
                // Paso 2 entra por la derecha y vuelve a salir por la derecha.
                Widget place(int index, Widget page, double dx, double opacity) => IgnorePointer(
                      ignoring: _step != index,
                      child: reduced
                          ? Opacity(opacity: opacity, child: page)
                          : FractionalTranslation(translation: Offset(dx, 0), child: page),
                    );
                return Stack(children: [
                  if (t < 1 - eps) place(0, _stepOne(), -t, 1 - t),
                  if (t > eps) place(1, _stepTwo(), 1 - t, t),
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(int n) => Semantics(
        label: 'Paso $n de 2',
        excludeSemantics: true,
        child: Text('$n / 2', style: AppType.caption.copyWith(color: context.palette.inkMuted)),
      );

  Widget _titles(String title, String subtitle) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(header: true, child: Text(title, style: AppType.title.copyWith(color: p.ink))),
      const SizedBox(height: Space.sm),
      Text(subtitle, style: AppType.body.copyWith(color: p.inkMuted)),
    ]);
  }

  Widget _stepOne() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.lg),
      children: [
        SizedBox(height: 48, child: Align(alignment: Alignment.centerLeft, child: _header(1))),
        const SizedBox(height: Space.xxl),
        _titles('¿Cómo son tus ingresos?', 'Así ajusto lo que te muestro. Puedes cambiarlo luego en Ajustes.'),
        const SizedBox(height: Space.xl),
        for (final (profile, title, description) in _options) ...[
          ChoiceCard(
            title: title,
            description: description,
            selected: _profile == profile,
            onTap: () => _choose(profile),
          ),
          const SizedBox(height: Space.md),
        ],
      ],
    );
  }

  Widget _stepTwo() {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          height: 48,
          child: Row(children: [
            IconButton(
              onPressed: () => _go(0),
              icon: Icon(Icons.arrow_back, color: p.inkMuted),
              tooltip: 'Volver',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              style: IconButton.styleFrom(alignment: Alignment.centerLeft),
            ),
            _header(2),
          ]),
        ),
        const SizedBox(height: Space.xxl),
        Expanded(
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _titles('¿Le ponemos nombre a tu espacio?', 'Es opcional. Aparece arriba en tu pantalla principal.'),
              const SizedBox(height: Space.xl),
              TextField(
                controller: _name,
                style: AppType.body.copyWith(color: p.ink),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                inputFormatters: [FilteringTextInputFormatter.deny(_emoji)],
                decoration: InputDecoration(
                  hintText: 'Mis cuentas',
                  errorText: _error,
                  contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.lg),
                ),
                onChanged: (v) {
                  final e = validateSpaceName(v).error;
                  if (e != _error) setState(() => _error = e);
                },
                onSubmitted: (_) => _finish(withName: true),
              ),
            ]),
          ),
        ),
        const SizedBox(height: Space.lg),
        _PressScale(
          child: FilledButton(
            onPressed: _saving ? null : () => _finish(withName: true),
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: Space.lg)),
            child: const Text('Empezar'),
          ),
        ),
        const SizedBox(height: Space.sm),
        Center(
          child: _TextLink(
            label: 'Omitir',
            semanticsLabel: 'Omitir nombre del espacio',
            onTap: _saving ? null : () => _finish(withName: false),
          ),
        ),
      ]),
    );
  }
}

/// Escala al presionar (pointer-down), como pide Motion.press.
class _PressScale extends StatefulWidget {
  const _PressScale({required this.child});
  final Widget child;

  @override
  State<_PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<_PressScale> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => setState(() => _down = true),
        onPointerUp: (_) => setState(() => _down = false),
        onPointerCancel: (_) => setState(() => _down = false),
        child: AnimatedScale(
          scale: _down ? Motion.pressScale : 1,
          duration: Motion.press,
          curve: Motion.easeOut,
          child: widget.child,
        ),
      );
}

/// Enlace de texto: inkMuted → ink al presionar, en Motion.lightChange. Área ≥ 48×48.
class _TextLink extends StatefulWidget {
  const _TextLink({required this.label, required this.semanticsLabel, required this.onTap});
  final String label;
  final String semanticsLabel;
  final VoidCallback? onTap;

  @override
  State<_TextLink> createState() => _TextLinkState();
}

class _TextLinkState extends State<_TextLink> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      enabled: widget.onTap != null,
      label: widget.semanticsLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.md, horizontal: Space.lg),
            child: AnimatedDefaultTextStyle(
              duration: Motion.lightChange,
              style: AppType.link.copyWith(color: _down ? p.ink : p.inkMuted),
              child: Text(widget.label, textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
  }
}
