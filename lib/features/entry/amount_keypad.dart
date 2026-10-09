import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import 'amount_input.dart';

/// Monto tecleado: "S/ " + lo tecleado (ink) + completado guía (inkMuted).
/// Vacío se ve "S/ 0.00" todo en gris.
class AmountDisplay extends StatelessWidget {
  const AmountDisplay({super.key, required this.amount});
  final AmountInput amount;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final d = amount.display;
    final typedColor = amount.isEmpty ? p.inkMuted : p.ink;
    return Semantics(
      label: 'Monto: S/ ${d.typed.isEmpty ? '0' : d.typed}${d.ghost}',
      excludeSemantics: true,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text.rich(TextSpan(style: AppType.amountInput, children: [
          TextSpan(text: 'S/ ', style: TextStyle(color: typedColor)),
          TextSpan(text: d.typed, style: TextStyle(color: p.ink)),
          TextSpan(text: d.ghost, style: TextStyle(color: p.inkMuted)),
        ])),
      ),
    );
  }
}

/// Teclado numérico propio (0–9, ".", ⌫). Lo comparten el registro y el saldo inicial.
class AmountKeypad extends StatelessWidget {
  const AmountKeypad({super.key, required this.keyHeight, required this.onKey, required this.onBackspace, required this.onClear});
  final double keyHeight;
  final ValueChanged<String> onKey;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) => Column(children: [
        for (final (i, row) in _rows.indexed) ...[
          if (i > 0) const SizedBox(height: Space.xs),
          Row(children: [
            for (final k in row)
              Expanded(
                child: k == '⌫'
                    ? _Key(
                        key: const Key('key.backspace'),
                        height: keyHeight,
                        semanticsLabel: 'Borrar',
                        onTap: onBackspace,
                        onLongPress: onClear,
                        child: Icon(Icons.backspace_outlined, size: 24, color: context.palette.ink),
                      )
                    : _Key(
                        key: Key('key.$k'),
                        height: keyHeight,
                        semanticsLabel: k == '.' ? 'Punto decimal' : k,
                        onTap: () => onKey(k),
                        child: Text(k, style: AppType.keypad.copyWith(color: context.palette.ink)),
                      ),
              ),
          ]),
        ],
      ]);
}

/// Tecla: fondo Palette.border al tocar (pointer-down), sin escala.
class _Key extends StatefulWidget {
  const _Key({
    super.key,
    required this.height,
    required this.semanticsLabel,
    required this.onTap,
    this.onLongPress,
    required this.child,
  });
  final double height;
  final String semanticsLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  @override
  State<_Key> createState() => _KeyState();
}

class _KeyState extends State<_Key> {
  bool _down = false;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: widget.semanticsLabel,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _down = true),
          onTapUp: (_) => setState(() => _down = false),
          onTapCancel: () => setState(() => _down = false),
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: AnimatedContainer(
            duration: Motion.press,
            height: widget.height,
            decoration: BoxDecoration(
              color: _down ? context.palette.border : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.button),
            ),
            child: Center(child: widget.child),
          ),
        ),
      );
}
