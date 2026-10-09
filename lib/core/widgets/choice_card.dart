import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Tarjeta seleccionable: título + descripción. Elegida = borde ink 2 px + check.
/// Respuesta al presionar en el pointer-down (escala + borde), no al soltar.
class ChoiceCard extends StatefulWidget {
  const ChoiceCard({
    super.key,
    required this.title,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<ChoiceCard> createState() => _ChoiceCardState();
}

class _ChoiceCardState extends State<ChoiceCard> {
  bool _pressed = false;

  void _setPressed(bool v) => setState(() => _pressed = v);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final borderWidth = widget.selected ? 2.0 : 1.0;
    return Semantics(
      button: true,
      selected: widget.selected,
      onTapHint: 'Elige y continúa',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? Motion.pressScale : 1,
          duration: Motion.press,
          curve: Motion.easeOut,
          child: AnimatedContainer(
            duration: Motion.lightChange,
            curve: Motion.easeOut,
            constraints: const BoxConstraints(minHeight: 72),
            // El borde de 2 px no debe empujar el contenido.
            padding: EdgeInsets.all(Space.lg - (borderWidth - 1)),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(
                color: widget.selected || _pressed ? p.ink : p.border,
                width: borderWidth,
              ),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(widget.title, style: AppType.heading.copyWith(color: p.ink)),
                  const SizedBox(height: Space.xs),
                  Text(widget.description, style: AppType.caption.copyWith(color: p.inkMuted)),
                ]),
              ),
              if (widget.selected) ...[
                const SizedBox(width: Space.md),
                Icon(Icons.check, color: p.ink, size: 20),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}
