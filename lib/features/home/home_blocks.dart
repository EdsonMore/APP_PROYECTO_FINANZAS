import 'package:flutter/material.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/icon_catalog.dart';
import '../../domain/metrics.dart';
import 'providers.dart';

/// Subwidgets del Home, uno por bloque de la ficha. Solo pintan lo que trae
/// [HomeSummary]: ningún cálculo de dinero aquí.

Duration _motion(BuildContext context, Duration d) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key, required this.title, required this.onSettings});
  final String title;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 48,
      child: Row(children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.heading.copyWith(color: p.ink)),
          ),
        ),
        IconButton(
          onPressed: onSettings,
          tooltip: 'Ajustes',
          icon: Icon(Icons.settings_outlined, color: p.inkMuted),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        ),
      ]),
    );
  }
}

/// Número principal a 52 sp; baja a 44 y 36 si no cabe en una línea (C1).
/// Por debajo de 36 no achica: corta con elipsis.
class FitDisplayText extends StatelessWidget {
  const FitDisplayText(this.text, {super.key, required this.color});
  final String text;
  final Color color;

  static const sizes = [52.0, 44.0, 36.0];

  /// Primer tamaño de [sizes] con el que [text] cabe en [maxWidth].
  static double sizeFor(String text, double maxWidth, TextScaler scaler) {
    for (final size in sizes) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: AppType.display.copyWith(fontSize: size)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final fits = tp.width <= maxWidth && !tp.didExceedMaxLines;
      tp.dispose();
      if (fits) return size;
    }
    return sizes.last;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final size = sizeFor(text, constraints.maxWidth, MediaQuery.textScalerOf(context));
        return Text(
          text,
          key: const Key('home.value'),
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: AppType.display.copyWith(fontSize: size, color: color),
        );
      });
}

class NumberBlock extends StatelessWidget {
  const NumberBlock({super.key, required this.headline});
  final Headline headline;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = headline;
    return Semantics(
      container: true,
      label: h.semantics,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: Space.xxl, bottom: Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (h.lead != null) ...[
            Text(h.lead!, style: AppType.body.copyWith(color: p.inkMuted)),
            const SizedBox(height: Space.xs),
          ],
          AnimatedSwitcher(
            duration: _motion(context, Motion.numberChange),
            layoutBuilder: (current, previous) =>
                Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
            child: KeyedSubtree(key: ValueKey(h.value), child: FitDisplayText(h.value, color: p.ink)),
          ),
          if (h.budgetPercent != null) ...[
            const SizedBox(height: Space.md),
            BudgetBar(percent: h.budgetPercent!, over: h.overBudget),
          ],
          if (h.secondary != null) ...[
            const SizedBox(height: Space.sm),
            Text(h.secondary!, style: AppType.caption.copyWith(color: p.inkMuted)),
          ],
          if (h.stats.isNotEmpty) ...[
            const SizedBox(height: Space.sm),
            Wrap(spacing: Space.xl, runSpacing: Space.xs, children: [
              for (final s in h.stats)
                Text.rich(TextSpan(style: AppType.caption.copyWith(color: p.inkMuted), children: [
                  TextSpan(text: '${s.label} '),
                  TextSpan(text: s.amount, style: AppType.amount.copyWith(fontSize: 13, color: p.ink)),
                ])),
            ]),
          ],
        ]),
      ),
    );
  }
}

/// Carril = el techo (por eso lleva fondo). Relleno ink; ámbar al pasar el 100 %.
class BudgetBar extends StatelessWidget {
  const BudgetBar({super.key, required this.percent, required this.over});
  final int percent;
  final bool over;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final target = (percent.clamp(0, 100)) / 100;
    return Semantics(
      label: '$percent % del presupuesto usado',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          key: const Key('home.budgetBar'),
          height: 6,
          child: ColoredBox(
            color: p.track,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: target),
              duration: _motion(context, Motion.numberChange),
              curve: Motion.easeOut,
              builder: (context, v, _) => Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: v,
                  heightFactor: 1,
                  child: ColoredBox(color: over ? p.amberFg : p.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class LightCard extends StatelessWidget {
  const LightCard({super.key, required this.view});
  final LightView view;

  static Color dotColor(Palette p, Light l) => switch (l) {
        Light.none => p.inkMuted,
        Light.green => p.incomeFg,
        Light.amber => p.amberFg,
        Light.red => p.expenseFg,
      };

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      container: true,
      label: 'Últimos 30 días. ${view.text}. ${view.amounts.replaceAll(' · ', ', ')}',
      excludeSemantics: true,
      child: Container(
        key: const Key('home.light'),
        padding: const EdgeInsets.all(Space.lg),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(Radii.card),
          border: Border.all(color: p.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            AnimatedContainer(
              key: const Key('home.lightDot'),
              duration: _motion(context, Motion.lightChange),
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: dotColor(p, view.light), shape: BoxShape.circle),
            ),
            const SizedBox(width: Space.sm),
            Expanded(child: Text(view.text, style: AppType.label.copyWith(color: p.ink))),
            Text('Últimos 30 días', style: AppType.caption.copyWith(color: p.inkMuted)),
          ]),
          const SizedBox(height: Space.xs),
          Text(view.amounts,
              style: AppType.caption.copyWith(color: p.inkMuted, fontFeatures: AppType.tabular)),
        ]),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Semantics(
          header: true,
          child: Text(text, style: AppType.heading.copyWith(color: context.palette.ink)),
        ),
      );
}

class TopCategoriesBlock extends StatelessWidget {
  const TopCategoriesBlock({super.key, required this.rows});
  final List<TopRow> rows;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      key: const Key('home.top'),
      padding: const EdgeInsets.only(top: Space.xl),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const _SectionTitle('En qué se va'),
        for (final (i, r) in rows.indexed) ...[
          if (i > 0) const SizedBox(height: Space.sm),
          Semantics(
            container: true,
            label: '${r.name}, ${r.amount}',
            excludeSemantics: true,
            child: SizedBox(
              height: 44,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Icon(IconCatalog.iconFor(r.icon), size: 18, color: p.inkMuted),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(r.name, style: AppType.label.copyWith(color: p.ink))),
                  Text(r.amount, style: AppType.amount.copyWith(color: p.ink)),
                ]),
                const SizedBox(height: Space.xs),
                // Sin carril de fondo: la barra es comparativa, no un medidor.
                TweenAnimationBuilder<double>(
                  tween: Tween(end: r.fraction),
                  duration: _motion(context, Motion.numberChange),
                  curve: Motion.easeOut,
                  builder: (context, v, _) => FractionallySizedBox(
                    widthFactor: v,
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(color: p.ink, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

class RecentMovementsBlock extends StatelessWidget {
  const RecentMovementsBlock({super.key, required this.rows});
  final List<RecentRow> rows;

  @override
  Widget build(BuildContext context) => Padding(
        key: const Key('home.recents'),
        padding: const EdgeInsets.only(top: Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SectionTitle('Recientes'),
          for (final r in rows) _RecentTile(key: ValueKey(r.id), row: r),
        ]),
      );
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({super.key, required this.row});
  final RecentRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = row;
    // ponytail: solo fundido de entrada; la salida al deshacer es instantánea.
    // Animar salidas exige diffear la lista del stream (AnimatedList).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _motion(context, Motion.numberChange),
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: Semantics(
        container: true,
        label: '${r.name}, ${r.subtitle}, ${r.isIncome ? 'ingreso' : 'gasto'} de ${r.amount.substring(2)}'
            '${r.isAuto ? ', capturado automáticamente' : ''}',
        excludeSemantics: true,
        child: SizedBox(
          height: 56,
          child: Row(children: [
            Icon(IconCatalog.iconFor(r.icon), size: 20, color: p.inkMuted),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(children: [
                  Flexible(
                    child: Text(r.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label.copyWith(color: p.ink)),
                  ),
                  if (r.isAuto) ...[
                    const SizedBox(width: Space.sm),
                    Container(
                      key: const Key('home.autoBadge'),
                      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
                      decoration: BoxDecoration(color: p.border, borderRadius: BorderRadius.circular(Radii.chip)),
                      child: Text('Auto', style: AppType.caption.copyWith(color: p.inkMuted)),
                    ),
                  ],
                ]),
                Text(r.subtitle,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.caption.copyWith(color: p.inkMuted)),
              ]),
            ),
            const SizedBox(width: Space.md),
            Text(r.amount, style: AppType.amount.copyWith(color: r.isIncome ? p.incomeFg : p.expenseFg)),
          ]),
        ),
      ),
    );
  }
}

class OpeningCard extends StatelessWidget {
  const OpeningCard({super.key, required this.onSet, required this.onDismiss});
  final VoidCallback onSet;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      key: const Key('home.openingCard'),
      margin: const EdgeInsets.only(bottom: Space.lg),
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.xs, Space.xs),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text('¿Cuánto tienes hoy?', style: AppType.heading.copyWith(color: p.ink)),
            ),
          ),
          IconButton(
            key: const Key('home.openingCard.close'),
            onPressed: onDismiss,
            tooltip: 'Descartar',
            icon: Icon(Icons.close, size: 20, color: p.inkMuted),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          ),
        ]),
        Padding(
          padding: const EdgeInsets.only(right: Space.md),
          child: Text('Así el cálculo usa tu plata real.', style: AppType.caption.copyWith(color: p.inkMuted)),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('home.openingCard.set'),
            onPressed: onSet,
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(48, 48),
              alignment: Alignment.centerLeft,
              foregroundColor: p.ink,
              textStyle: AppType.label,
            ),
            child: const Text('Poner saldo'),
          ),
        ),
      ]),
    );
  }
}

