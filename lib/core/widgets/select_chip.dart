import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Chip de selección del Historial (4B) y de la calculadora (4E): visible 32,
/// área táctil 48, radio 8. Elegido: fondo ink.
class SelectChip extends StatelessWidget {
  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.leading,
    this.semanticsLabel,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticsLabel ?? label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 48, // área táctil; el chip visible mide 32
          // widthFactor: 1 → el chip mide lo que su texto, también dentro de un Wrap.
          child: Center(
            widthFactor: 1,
            child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : Motion.lightChange,
            curve: Motion.easeOut,
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            decoration: BoxDecoration(
              color: selected ? p.ink : Colors.transparent,
              borderRadius: BorderRadius.circular(Radii.chip),
              border: Border.all(color: selected ? p.ink : p.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 6)],
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.label.copyWith(color: selected ? p.surface : p.ink),
                  ),
                ),
              ],
            ),
          ),
          ),
        ),
      ),
    );
  }
}
