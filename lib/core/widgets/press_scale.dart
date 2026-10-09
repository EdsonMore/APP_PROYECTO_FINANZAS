import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Escala al presionar (pointer-down), Motion.pressScale en Motion.press.
class PressScale extends StatefulWidget {
  const PressScale({super.key, required this.child});
  final Widget child;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
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
