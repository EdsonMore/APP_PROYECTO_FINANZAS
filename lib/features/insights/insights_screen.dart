import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/icon_catalog.dart';
import '../../core/widgets/text_link.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';
import '../budget/budget_screen.dart';
import '../settings/settings_screen.dart';
import 'providers.dart';
import 'runway_line.dart';

const suggestedSnackDuration = Duration(seconds: 3);

/// Insights: una sola pantalla con scroll, bloques ordenados por modo
/// (SPEC.md §Insights). La UI no hace cuentas: todo viene de [InsightsSummary].
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> with SingleTickerProviderStateMixin {
  /// Entrada de los bloques: fade + 8 px, escalonados 40 ms, solo la primera vez.
  late final _reveal = AnimationController(vsync: this);
  static const _stagger = Duration(milliseconds: 40);
  static const _each = Duration(milliseconds: 250);

  void _start(int count) {
    if (_reveal.isAnimating || _reveal.value > 0) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _reveal.value = 1;
      return;
    }
    _reveal.duration = _each + _stagger * count;
    _reveal.forward();
  }

  @override
  void dispose() {
    _reveal.dispose();
    super.dispose();
  }

  /// Una animación por bloque, creada solo cuando cambia la cantidad de bloques:
  /// reconstruir por un dato nuevo no crea objetos ni suma listeners (hallazgo 5).
  var _anims = <Animation<double>>[];

  Widget _revealed(int i, int count, Widget child) {
    if (_anims.length != count) {
      final total = (_each + _stagger * count).inMilliseconds;
      _anims = [
        for (var k = 0; k < count; k++)
          _reveal.drive(CurveTween(
              curve: Interval((_stagger * k).inMilliseconds / total,
                  ((_stagger * k) + _each).inMilliseconds / total, curve: Motion.easeOut))),
      ];
    }
    final a = _anims[i];
    return AnimatedBuilder(
      animation: a,
      child: child,
      builder: (context, child) => Opacity(
        opacity: a.value,
        child: Transform.translate(offset: Offset(0, 8 * (1 - a.value)), child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final summary = ref.watch(insightsSummaryProvider);
    return Scaffold(
      body: SafeArea(
        child: summary.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => Center(child: Text('No pude leer tus datos.', style: AppType.body.copyWith(color: p.ink))),
          data: (s) {
            final items = <Widget>[
              // Espacio no separable tras "S/": el monto nunca se parte entre dos líneas.
              Text(s.phrase.replaceAll('S/ ', 'S/\u00A0'),
                  key: const Key('insights.phrase'), style: AppType.title.copyWith(color: p.ink)),
              for (final b in s.blocks) _block(b),
            ];
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _start(items.length);
            });
            return ListView(
              key: const Key('insights.scroll'),
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
              children: [
                const SubpageHeader(title: 'Insights'),
                Padding(
                  padding: const EdgeInsets.only(left: 48 + Space.xs, top: Space.xs),
                  child: Text('Últimos 30 días', style: AppType.caption.copyWith(color: p.inkMuted)),
                ),
                for (final (i, w) in items.indexed)
                  Padding(
                    padding: const EdgeInsets.only(top: Space.xl),
                    child: _revealed(i, items.length, w),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _block(InsightBlock b) => switch (b) {
        BudgetBlock() => _Titled(key: const Key('insights.budget'), title: 'Presupuesto', child: _BudgetBody(b)),
        SpendBlock() => _Titled(key: const Key('insights.spend'), title: 'En qué se fue', child: _SpendBody(b)),
        StreakBlock() => _Titled(key: const Key('insights.streak'), title: 'Racha', child: _StreakBody(b)),
        MonthsBlock() => _Titled(key: const Key('insights.months'), title: 'Tus meses', child: _MonthsBody(b)),
        FlowBlock() => _Titled(key: const Key('insights.flow'), title: 'Entra y sale', child: _FlowBody(b)),
        RunwayBlock() => _Titled(key: const Key('insights.runway'), title: 'Reserva', child: _RunwayBody(b)),
        SuggestedBlock() =>
          _Titled(key: const Key('insights.suggested'), title: 'Techos sugeridos', child: _SuggestedBody(b)),
        ReadingBlock() => _Titled(key: const Key('insights.reading'), title: 'Lectura del mes', child: _ReadingBody(b)),
        ByAccountBlock() => _Titled(key: const Key('insights.byAccount'), title: 'Por cuenta', child: _ByAccountBody(b)),
      };
}

/// Una frase por línea, en inkMuted: es una lectura, no una alerta.
class _ReadingBody extends StatelessWidget {
  const _ReadingBody(this.block);
  final ReadingBlock block;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, line) in block.lines.indexed) ...[
        if (i > 0) const SizedBox(height: Space.sm),
        Text(line, style: AppType.body.copyWith(color: p.inkMuted)),
      ],
    ]);
  }
}

class _ByAccountBody extends StatelessWidget {
  const _ByAccountBody(this.block);
  final ByAccountBlock block;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    String signed(int c) => c < 0 ? '−${Formatters.soles(-c)}' : Formatters.soles(c);
    return Column(children: [
      for (final r in block.rows)
        Padding(
          key: Key('insights.account.${r.name}'),
          padding: const EdgeInsets.only(bottom: Space.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(r.name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label.copyWith(color: p.ink)),
              ),
              Text(signed(r.balance), style: AppType.amount.copyWith(color: r.balance < 0 ? p.expenseFg : p.ink)),
            ]),
            const SizedBox(height: Space.xs),
            Text('Salió ${Formatters.soles(r.outCents)} · Entró ${Formatters.soles(r.inCents)}',
                style: AppType.caption.copyWith(color: p.inkMuted)),
          ]),
        ),
    ]);
  }
}

class _Titled extends StatelessWidget {
  const _Titled({super.key, required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Semantics(header: true, child: Text(title, style: AppType.heading.copyWith(color: context.palette.ink))),
        const SizedBox(height: Space.md),
        child,
      ]);
}

/// Texto de espera de un bloque sin datos suficientes.
class _Waiting extends StatelessWidget {
  const _Waiting(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text, style: AppType.body.copyWith(color: context.palette.inkMuted));
}

void _openBudget(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BudgetScreen()));

class _BudgetBody extends StatelessWidget {
  const _BudgetBody(this.block);
  final BudgetBlock block;

  /// El TextLink trae Space.lg de padding: se corre para alinear el texto al borde.
  Widget _link(BuildContext context, String key, String label) => Align(
        alignment: Alignment.centerRight,
        child: Transform.translate(
          offset: const Offset(Space.lg, 0),
          child: TextLink(key: Key(key), label: label, semanticsLabel: label, onTap: () => _openBudget(context)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (block.summary.total == null) return _link(context, 'insights.defineBudgets', 'Definir presupuestos');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      BudgetTotal(summary: block.summary),
      _link(context, 'insights.seeBudget', 'Ver presupuesto'),
    ]);
  }
}

class _SpendBody extends StatelessWidget {
  const _SpendBody(this.block);
  final SpendBlock block;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final brightness = Theme.of(context).brightness;
    return Column(children: [
      for (final r in block.rows)
        Semantics(
          label: '${r.name}, ${Formatters.soles(r.cents)}, ${r.percent} por ciento',
          excludeSemantics: true,
          child: Padding(
            key: Key('insights.spend.${r.name}'),
            padding: const EdgeInsets.only(bottom: Space.md),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label.copyWith(color: p.ink)),
                ),
                Text.rich(TextSpan(style: AppType.amount.copyWith(fontSize: 14), children: [
                  TextSpan(text: Formatters.soles(r.cents), style: TextStyle(color: p.ink)),
                  TextSpan(text: '  ${r.percent} %', style: TextStyle(color: p.inkMuted)),
                ])),
              ]),
              const SizedBox(height: Space.xs),
              // Sin carril: el largo compara montos (relativo a la fila mayor).
              FractionallySizedBox(
                widthFactor: r.fraction,
                child: Container(
                  key: Key('insights.spendBar.${r.name}'),
                  height: 6,
                  decoration: BoxDecoration(
                    color: categoryColor(r.colorHex, brightness),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ]),
          ),
        ),
    ]);
  }
}

class _StreakBody extends StatelessWidget {
  const _StreakBody(this.block);
  final StreakBlock block;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final limit = 'Tu límite diario: ${Formatters.soles(block.thresholdCents)}';
    if (block.days == 0) {
      // Un día no es una deuda: sin rojo.
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Hoy pasaste tu límite diario.', style: AppType.body.copyWith(color: p.inkMuted)),
        const SizedBox(height: Space.xs),
        Text(limit, style: AppType.caption.copyWith(color: p.inkMuted)),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${block.days} ${block.days == 1 ? 'día' : 'días'} sin pasarte',
          style: AppType.title.copyWith(fontSize: 22, color: p.ink)),
      const SizedBox(height: Space.xs),
      Text(limit, style: AppType.caption.copyWith(color: p.inkMuted)),
    ]);
  }
}

class _MonthsBody extends StatelessWidget {
  const _MonthsBody(this.block);
  final MonthsBlock block;

  @override
  Widget build(BuildContext context) {
    final best = block.best, worst = block.worst;
    if (best == null) return const _Waiting('Cuando cierres dos meses te muestro tu mes típico.');
    final p = context.palette;
    Widget column(String label, MonthIncome m) => Expanded(
          child: Semantics(
            label: '$label: ${Formatters.month(m.month)}, ${Formatters.soles(m.cents)}',
            excludeSemantics: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: AppType.caption.copyWith(color: p.inkMuted)),
              const SizedBox(height: Space.xs),
              Text(Formatters.month(m.month), style: AppType.label.copyWith(color: p.ink)),
              Text(Formatters.soles(m.cents), style: AppType.amount.copyWith(color: p.ink)),
            ]),
          ),
        );
    return Row(children: [
      column('Mejor', best),
      const SizedBox(width: Space.lg),
      // Todos los meses empatan: "Peor" repetiría el mismo monto.
      if (worst != null) column('Peor', worst) else const Spacer(),
    ]);
  }
}

class _FlowBody extends StatelessWidget {
  const _FlowBody(this.block);
  final FlowBlock block;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget figure(String label, int cents) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: AppType.caption.copyWith(color: p.inkMuted)),
            const SizedBox(height: Space.xs),
            Text(Formatters.soles(cents), style: AppType.amount.copyWith(color: p.ink)),
          ]),
        );
    final short = block.diffCents < 0;
    final sentence = short
        ? 'Te faltan ~${Formatters.soles(-block.diffCents)} en un mes típico.'
        : 'Te sobran ~${Formatters.soles(block.diffCents)} en un mes típico.';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        figure('Ingreso típico 30d', block.incomeCents),
        const SizedBox(width: Space.lg),
        figure('Gasto 30d', block.expenseCents),
      ]),
      const SizedBox(height: Space.md),
      Row(children: [
        if (short) ...[
          Icon(Icons.error_outline, size: 16, color: p.expenseFg),
          const SizedBox(width: Space.xs),
        ],
        Flexible(
          child: Text(sentence,
              key: const Key('insights.flowSentence'),
              style: AppType.body.copyWith(color: short ? p.expenseFg : p.ink)),
        ),
      ]),
    ]);
  }
}

class _RunwayBody extends StatelessWidget {
  const _RunwayBody(this.block);
  final RunwayBlock block;

  @override
  Widget build(BuildContext context) {
    final s = block.series;
    final points = s.nonNulls;
    if (s.length < minRunwayPoints || points.isEmpty) {
      return const _Waiting('Necesito una semana de datos para dibujar tu tendencia.');
    }
    final p = context.palette;
    String days(int d) => d >= maxRunwayDays ? '+$maxRunwayDays' : '$d';
    final first = days(points.first);
    final last = s.last;
    final end = last != null
        ? days(last)
        : (block.today.status == RunwayStatus.noCushion ? 'sin reserva' : 'sin gastos recientes');
    final bold = AppType.amount.copyWith(color: p.ink);
    final muted = AppType.body.copyWith(color: p.inkMuted);
    return Semantics(
      label: 'Tu reserva pasó de $first días a ${last != null ? '$end días' : end} en los últimos ${s.length} días',
      excludeSemantics: true,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          key: const Key('insights.runwayLine'),
          height: block.tall ? 140 : 96,
          child: CustomPaint(painter: RunwayLine(series: s, color: p.ink)),
        ),
        const SizedBox(height: Space.sm),
        Text.rich(
          key: const Key('insights.runwayLabel'),
          TextSpan(children: [
            TextSpan(text: first, style: bold),
            TextSpan(text: last != null ? ' → ' : ' días → ', style: muted),
            TextSpan(text: end, style: last != null ? bold : muted),
            if (last != null) TextSpan(text: ' días', style: muted),
          ]),
        ),
      ]),
    );
  }
}

class _SuggestedBody extends StatelessWidget {
  const _SuggestedBody(this.block);
  final SuggestedBlock block;

  @override
  Widget build(BuildContext context) =>
      Column(children: [for (final r in block.rows) _SuggestedTile(key: ValueKey(r.categoryId), row: r)]);
}

/// [Usar]: la fila se desvanece, se guarda el techo y un aviso dice dónde verlo.
class _SuggestedTile extends ConsumerStatefulWidget {
  const _SuggestedTile({super.key, required this.row});
  final SuggestedRow row;

  @override
  ConsumerState<_SuggestedTile> createState() => _SuggestedTileState();
}

class _SuggestedTileState extends ConsumerState<_SuggestedTile> {
  bool _leaving = false;

  Future<void> _save() async {
    final r = widget.row;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(databaseProvider).setBudget(r.categoryId, r.cents);
    } catch (_) {
      // La fila vuelve a verse para poder reintentar.
      if (mounted) setState(() => _leaving = false);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text(saveCapError), behavior: SnackBarBehavior.floating));
      return;
    }
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        key: const Key('insights.suggestedSnack'),
        content: Text('Techo de ${r.name} guardado. Lo verás en Presupuesto cuando cambies a modo Estable.'),
        duration: suggestedSnackDuration,
        behavior: SnackBarBehavior.floating,
      ));
  }

  void _use() {
    if (_leaving) return;
    HapticFeedback.lightImpact();
    if (MediaQuery.disableAnimationsOf(context)) {
      _save();
      return;
    }
    setState(() => _leaving = true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final r = widget.row;
    return AnimatedOpacity(
      opacity: _leaving ? 0 : 1,
      duration: Motion.lightChange,
      onEnd: () {
        if (_leaving) _save();
      },
      child: Row(children: [
        Icon(IconCatalog.iconFor(r.icon), size: 20, color: p.ink),
        const SizedBox(width: Space.md),
        Expanded(child: Text(r.name, style: AppType.label.copyWith(color: p.ink))),
        Text('~${Formatters.soles(r.cents)}', style: AppType.amount.copyWith(fontSize: 14, color: p.ink)),
        Transform.translate(
          offset: const Offset(Space.lg, 0),
          child: TextLink(
            key: Key('insights.use.${r.categoryId}'),
            label: 'Usar',
            semanticsLabel: 'Usar ${Formatters.soles(r.cents)} como techo de ${r.name}',
            onTap: _use,
          ),
        ),
      ]),
    );
  }
}
