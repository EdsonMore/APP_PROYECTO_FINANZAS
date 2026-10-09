import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Asa de arrastre de las hojas inferiores (32×4, Palette.border).
class SheetGrabber extends StatelessWidget {
  const SheetGrabber({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Space.sm),
        child: Center(
          child: Container(
            width: 32,
            height: 4,
            decoration: BoxDecoration(color: context.palette.border, borderRadius: BorderRadius.circular(2)),
          ),
        ),
      );
}
