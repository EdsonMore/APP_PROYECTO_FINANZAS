import 'package:flutter/physics.dart';
import 'package:flutter/widgets.dart';

import '../theme/tokens.dart';

/// Barra de gasto contra techo, compartida por el Home y Presupuesto.
/// Carril = el techo (por eso lleva fondo [Palette.track]). Relleno [color];
/// pasado el 100 % se llena entera en [Palette.expenseFg] (D3 de la 1c).
/// Crece con [Motion.spring] al entrar y al cambiar; con "reducir movimiento",
/// sin animación.
class BudgetBar extends StatefulWidget {
  const BudgetBar({
    super.key,
    required this.percent,
    required this.over,
    required this.color,
    this.height = 6,
    this.semanticsLabel,
  });

  /// 0..∞ (puede pasar de 100).
  final int percent;
  final bool over;
  final Color color;
  final double height;

  /// null = la barra no se anuncia sola (la fila ya lo dice).
  final String? semanticsLabel;

  @override
  State<BudgetBar> createState() => _BudgetBarState();
}

class _BudgetBarState extends State<BudgetBar> with SingleTickerProviderStateMixin {
  late final _c = AnimationController.unbounded(vsync: this);

  double get _target => widget.over ? 1 : widget.percent.clamp(0, 100) / 100;

  void _animate() {
    if (MediaQuery.disableAnimationsOf(context)) {
      _c.value = _target;
    } else {
      _c.animateWith(SpringSimulation(Motion.spring, _c.value, _target, _c.velocity));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.value != _target && !_c.isAnimating) _animate();
  }

  @override
  void didUpdateWidget(BudgetBar old) {
    super.didUpdateWidget(old);
    if (old.percent != widget.percent || old.over != widget.over) _animate();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(widget.height / 2),
      child: SizedBox(
        height: widget.height,
        child: ColoredBox(
          color: p.track,
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: _c.value.clamp(0.0, 1.0),
                heightFactor: 1,
                child: ColoredBox(color: widget.over ? p.expenseFg : widget.color),
              ),
            ),
          ),
        ),
      ),
    );
    final label = widget.semanticsLabel;
    return label == null ? ExcludeSemantics(child: bar) : Semantics(label: label, child: bar);
  }
}
