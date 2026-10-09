import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Enlace de texto: inkMuted → ink al presionar, en Motion.lightChange. Área ≥ 48×48.
class TextLink extends StatefulWidget {
  const TextLink({super.key, required this.label, required this.semanticsLabel, required this.onTap});
  final String label;
  final String semanticsLabel;
  final VoidCallback? onTap;

  @override
  State<TextLink> createState() => _TextLinkState();
}

class _TextLinkState extends State<TextLink> {
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
