import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../core/widgets/text_link.dart';
import '../../data/providers.dart';
import 'amount_input.dart';
import 'amount_keypad.dart';

/// Abre "¿Cuánto tienes hoy?". true si se guardó el saldo.
Future<bool> showOpeningBalanceSheet(BuildContext context) async {
  final reduced = MediaQuery.disableAnimationsOf(context);
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    sheetAnimationStyle: reduced
        ? const AnimationStyle(duration: Motion.reducedFade, reverseDuration: Motion.reducedFade)
        : const AnimationStyle(
            duration: Duration(milliseconds: 350), reverseDuration: Duration(milliseconds: 250), curve: Motion.emphasized),
    builder: (_) => const OpeningBalanceSheet(),
  );
  return saved ?? false;
}

/// Saldo inicial: foto del dinero de ahora. S/ 0 es válido (usuario de
/// Supervivencia); solo el monto vacío deshabilita "Guardar saldo".
class OpeningBalanceSheet extends ConsumerStatefulWidget {
  const OpeningBalanceSheet({super.key});

  @override
  ConsumerState<OpeningBalanceSheet> createState() => _OpeningBalanceSheetState();
}

class _OpeningBalanceSheetState extends ConsumerState<OpeningBalanceSheet> {
  AmountInput _amount = const AmountInput();
  bool _saving = false;
  String? _error;

  void _press(String key) {
    final next = _amount.press(key);
    if (next == null) {
      HapticFeedback.lightImpact();
      return;
    }
    setState(() => _amount = next);
  }

  Future<void> _save() async {
    if (_saving || _amount.isEmpty) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(databaseProvider).setOpeningBalance(cents: _amount.cents, at: DateTime.now());
      HapticFeedback.lightImpact();
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final screenH = MediaQuery.sizeOf(context).height;
    final typed = !_amount.isEmpty;
    final canSave = typed && !_saving;
    final ctaH = Space.sheetCtaHeight(screenH);

    final save = FilledButton(
      key: const Key('opening.save'),
      onPressed: canSave ? _save : null,
      style: FilledButton.styleFrom(
        minimumSize: Size.fromHeight(ctaH),
        disabledBackgroundColor: p.border,
        disabledForegroundColor: p.inkMuted,
      ),
      child: const Text('Guardar saldo'),
    );

    Widget sheet = SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Column(
          key: const Key('opening.sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetGrabber(),
            Semantics(
              header: true,
              child: Text('¿Cuánto tienes hoy?', style: AppType.title.copyWith(color: p.ink)),
            ),
            const SizedBox(height: Space.sm),
            Text('Con eso calculo cuántos días te alcanza. Puedes cambiarlo en Ajustes.',
                style: AppType.body.copyWith(color: p.inkMuted)),
            const SizedBox(height: Space.lg),
            AmountDisplay(key: const Key('opening.amount'), amount: _amount),
            if (_error != null) ...[
              const SizedBox(height: Space.xs),
              Text(_error!, style: AppType.caption.copyWith(color: p.expenseFg)),
            ],
            const SizedBox(height: Space.lg),
            AmountKeypad(
              keyHeight: Space.keyHeight(screenH),
              onKey: _press,
              onBackspace: () => setState(() => _amount = _amount.backspace()),
              onClear: () => setState(() => _amount = const AmountInput()),
            ),
            const SizedBox(height: Space.md),
            Semantics(
              hint: typed ? null : 'Ingresa un monto',
              child: canSave ? PressScale(child: save) : save,
            ),
            const SizedBox(height: Space.sm),
            Center(
              child: TextLink(
                label: 'Ahora no',
                semanticsLabel: 'Ahora no, cerrar sin guardar',
                onTap: () => Navigator.of(context).pop(false), // pop directo: cierra aunque haya monto
              ),
            ),
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    );

    // C2: con monto tecleado, ni tocar fuera, ni Atrás, ni deslizar cierran.
    // Tocar fuera y Atrás pasan por maybePop → PopScope. Deslizar llama a
    // Navigator.pop directo, así que se le quita el gesto a la hoja con un
    // detector vertical que gana la arena antes que el de BottomSheet.
    // El detector siempre está (árbol estable); sin callbacks no captura nada.
    void ignore(Object? _) {}
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: typed ? ignore : null,
      onVerticalDragUpdate: typed ? ignore : null,
      onVerticalDragEnd: typed ? ignore : null,
      child: PopScope(canPop: !typed, child: sheet),
    );
  }
}
