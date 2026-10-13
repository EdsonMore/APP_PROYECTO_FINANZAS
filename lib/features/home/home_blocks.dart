import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/budget_bar.dart';
import '../../core/widgets/icon_catalog.dart';
import '../../core/widgets/text_link.dart';
import '../accounts/accounts_screen.dart' show AccountRow;
import '../../domain/metrics.dart';
import 'providers.dart';

/// Subwidgets del Home, uno por bloque de la ficha. Solo pintan lo que trae
/// [HomeSummary]: ningún cálculo de dinero aquí.

Duration _motion(BuildContext context, Duration d) => MediaQuery.disableAnimationsOf(context) ? Duration.zero : d;

class HomeHeader extends StatelessWidget {
  const HomeHeader(
      {super.key,
      required this.title,
      required this.onInfo,
      required this.onInsights,
      required this.onSettings,
      this.sync = const SizedBox.shrink()});
  final String title;

  /// Ícono de estado de sync (3D), en el grupo derecho antes de Insights.
  final Widget sync;

  /// ⓘ junto al nombre: explica el modo actual.
  final VoidCallback onInfo;
  final VoidCallback onInsights;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 48,
      child: Row(children: [
        Expanded(
          child: Row(children: [
            Flexible(
              child: Semantics(
                header: true,
                child: Text(title,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.heading.copyWith(color: p.ink)),
              ),
            ),
            IconButton(
              key: const Key('home.modeInfo'),
              onPressed: onInfo,
              tooltip: 'Cómo funciona tu modo',
              icon: Icon(Icons.info_outline, size: 18, color: p.inkMuted),
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ]),
        ),
        sync,
        IconButton(
          onPressed: onInsights,
          tooltip: 'Insights',
          icon: Icon(Icons.insights_outlined, color: p.inkMuted),
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
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
  const NumberBlock({super.key, required this.headline, this.onTap});
  final Headline headline;

  /// Solo el bloque de presupuesto es tocable (abre Presupuesto).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = headline;
    return Semantics(
      container: true,
      button: onTap != null,
      label: h.semantics,
      hint: onTap != null ? 'Abre Presupuesto' : null,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
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
            if (h.context != null) ...[
              const SizedBox(height: Space.xs),
              Text(h.context!,
                  key: const Key('home.context'),
                  style: AppType.caption.copyWith(color: h.contextUrgent ? p.expenseFg : p.inkMuted)),
            ],
            if (h.budgetPercent != null) ...[
              const SizedBox(height: Space.md),
              BudgetBar(key: const Key('home.budgetBar'), percent: h.budgetPercent!, over: h.overBudget, color: p.ink),
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
  const RecentMovementsBlock({super.key, required this.rows, this.onTapRow, this.onSeeAll});
  final List<RecentRow> rows;

  /// Tocar un movimiento lo abre para editar (4B).
  final void Function(String id)? onTapRow;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) => Padding(
        key: const Key('home.recents'),
        padding: const EdgeInsets.only(top: Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Expanded(child: _SectionTitle('Recientes')),
            if (onSeeAll != null)
              Transform.translate(
                // TextLink trae 16 de padding: el texto queda alineado al margen.
                offset: const Offset(Space.lg, -Space.md),
                child: TextLink(
                    key: const Key('home.seeAll'), label: 'Ver todo', semanticsLabel: 'Ver todo el historial', onTap: onSeeAll),
              ),
          ]),
          for (final r in rows)
            MovementTile(key: ValueKey(r.id), row: r, onTap: onTapRow == null ? null : () => onTapRow!(r.id)),
        ]),
      );
}

/// Fila de un movimiento: Recientes del Home e Historial (4B).
class MovementTile extends StatelessWidget {
  const MovementTile({super.key, required this.row, this.onTap, this.fadeIn = true, this.actions = const {}});
  final RecentRow row;
  final VoidCallback? onTap;

  /// Fundido de entrada (Recientes). El Historial no lo usa: con cientos de
  /// filas, el fundido al hacer scroll molesta.
  final bool fadeIn;

  /// Acciones extra para lectores de pantalla (p. ej. "Borrar" en el Historial).
  final Map<CustomSemanticsAction, VoidCallback> actions;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = row;
    final tile = Semantics(
        container: true,
        button: onTap != null,
        label: '${r.name}${r.subtitle.isEmpty ? '' : ', ${r.subtitle}'}, '
            '${r.isTransfer ? 'transferencia de ${r.amount}' : '${r.isIncome ? 'ingreso' : 'gasto'} de ${r.amount.substring(2)}'}'
            '${r.isAuto ? ', capturado automáticamente' : ''}',
        onTap: onTap,
        customSemanticsActions: actions,
        excludeSemantics: true,
        child: GestureDetector(
         behavior: HitTestBehavior.opaque,
         onTap: onTap,
         child: SizedBox(
          height: 56,
          child: Row(children: [
            Icon(r.isTransfer ? Icons.swap_horiz : IconCatalog.iconFor(r.icon), size: 20, color: p.inkMuted),
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
                if (r.subtitle.isNotEmpty)
                  Text(r.subtitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.caption.copyWith(color: p.inkMuted)),
              ]),
            ),
            const SizedBox(width: Space.md),
            Text(r.amount,
                style: AppType.amount.copyWith(color: r.isTransfer ? p.ink : (r.isIncome ? p.incomeFg : p.expenseFg))),
          ]),
         ),
        ),
      );
    if (!fadeIn) return tile;
    // ponytail: solo fundido de entrada; la salida al deshacer es instantánea.
    // Animar salidas exige diffear la lista del stream (AnimatedList).
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: _motion(context, Motion.numberChange),
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: tile,
    );
  }
}

/// Bloque "Cuentas" (4A): después del semáforo, solo si hay cuentas. Tocar
/// una fila abre el Historial filtrado por esa cuenta.
class AccountsBlock extends StatelessWidget {
  const AccountsBlock({super.key, required this.rows, required this.onTap});
  final List<AccountView> rows;
  final void Function(String? id) onTap;

  @override
  Widget build(BuildContext context) => Padding(
        key: const Key('home.accounts'),
        padding: const EdgeInsets.only(top: Space.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _SectionTitle('Cuentas'),
          for (final r in rows)
            AccountRow(
              key: Key('home.account.${r.id ?? 'unassigned'}'),
              icon: r.icon,
              name: r.name,
              balance: r.balance,
              onTap: () => onTap(r.id),
            ),
        ]),
      );
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

