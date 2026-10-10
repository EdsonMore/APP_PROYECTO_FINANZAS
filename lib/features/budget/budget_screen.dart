import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/budget_bar.dart';
import '../../core/widgets/icon_catalog.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../core/widgets/text_link.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';
import '../entry/amount_input.dart';
import '../entry/amount_keypad.dart';
import '../settings/settings_screen.dart';
import 'providers.dart';

/// Presupuesto (solo modo Estable): techos por categoría contra el gasto del
/// mes calendario. Nunca habla del ingreso. Reglas en SPEC.md §Modos de uso.
class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Si el modo deja de ser Estable con la pantalla abierta, vuelve atrás.
    ref.listen(settingsProvider, (_, next) {
      final mode = next.value?.mode;
      if (mode != null && mode != Mode.stable) Navigator.of(context).maybePop();
    });
    final summary = ref.watch(budgetSummaryProvider);
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: summary.when(
          loading: () => const SizedBox.shrink(),
          error: (_, _) => Center(child: Text('No pude leer tus datos.', style: AppType.body.copyWith(color: p.ink))),
          data: (s) => ListView(
            key: const Key('budget.scroll'),
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
            children: [
              const SubpageHeader(title: 'Presupuesto'),
              Padding(
                // Alineado con el título: chevron (48) + Space.xs.
                padding: const EdgeInsets.only(left: 48 + Space.xs, top: Space.xs),
                child: Text(s.month, style: AppType.caption.copyWith(color: p.inkMuted)),
              ),
              const SizedBox(height: Space.xl),
              if (s.isEmpty)
                _EmptyBlock(summary: s)
              else ...[
                _TotalBlock(summary: s),
                const SizedBox(height: Space.xl),
                for (final r in s.capped) _CappedRow(row: r),
              ],
              if (s.uncapped.isNotEmpty) ...[
                if (!s.isEmpty) Divider(color: p.border, height: Space.xl),
                for (final r in s.uncapped) _UncappedRow(row: r),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TotalBlock extends StatelessWidget {
  const _TotalBlock({required this.summary});
  final BudgetSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = summary.total!;
    final over = t.remainingCents < 0;
    final spent = Formatters.soles(t.spentCents);
    final cap = Formatters.soles(t.capCents);
    return Column(key: const Key('budget.total'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Semantics(
        label: '$spent de $cap, ${t.percent} por ciento usado',
        excludeSemantics: true,
        child: Text.rich(TextSpan(children: [
          // 36 sp: el tamaño menor de FitDisplayText, para que "de S/ Y" quepa en la línea.
          TextSpan(text: spent, style: AppType.display.copyWith(fontSize: 36, color: p.ink)),
          TextSpan(text: '  de $cap', style: AppType.body.copyWith(color: p.inkMuted)),
        ])),
      ),
      const SizedBox(height: Space.md),
      BudgetBar(key: const Key('budget.totalBar'), percent: t.percent, over: over, color: p.ink, height: 8),
      const SizedBox(height: Space.sm),
      if (over)
        _OverLine(key: const Key('budget.totalOver'), text: '${Formatters.soles(-t.remainingCents)} por encima', size: 16)
      else
        Text('Quedan ${Formatters.soles(t.remainingCents)}', style: AppType.caption.copyWith(color: p.inkMuted)),
      if (summary.uncappedSpentCents > 0) ...[
        const SizedBox(height: Space.xs),
        Text('Incluye ${Formatters.soles(summary.uncappedSpentCents)} de categorías sin techo',
            key: const Key('budget.uncappedSpent'), style: AppType.caption.copyWith(color: p.inkMuted)),
      ],
    ]);
  }
}

/// Ícono de alerta + texto, ambos en expenseFg: el exceso nunca va solo con color.
class _OverLine extends StatelessWidget {
  const _OverLine({super.key, required this.text, required this.size});
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.palette.expenseFg;
    return Row(children: [
      Icon(Icons.error_outline, size: size, color: c),
      const SizedBox(width: Space.xs),
      Flexible(child: Text(text, style: AppType.caption.copyWith(color: c))),
    ]);
  }
}

/// Toda la fila es tocable y abre la hoja de edición.
class _RowShell extends StatelessWidget {
  const _RowShell({required this.row, required this.semantics, required this.child});
  final BudgetRow row;
  final String semantics;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantics,
        child: GestureDetector(
          key: Key('budget.row.${row.categoryId}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => showBudgetSheet(context, row),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(padding: const EdgeInsets.symmetric(vertical: Space.md), child: child),
          ),
        ),
      );
}

class _CappedRow extends StatelessWidget {
  const _CappedRow({required this.row});
  final BudgetRow row;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final excess = row.spentCents - row.capCents!;
    final semantics = row.over
        ? '${row.name}, ${Formatters.soles(excess)} de más'
        : '${row.name}, ${Formatters.soles(row.spentCents)} de ${Formatters.soles(row.capCents!)}';
    return _RowShell(
      row: row,
      semantics: semantics,
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(IconCatalog.iconFor(row.icon), size: 20, color: p.ink),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label.copyWith(color: p.ink)),
            ),
            const SizedBox(width: Space.sm),
            Text.rich(TextSpan(style: AppType.amount.copyWith(fontSize: 14), children: [
              TextSpan(text: Formatters.soles(row.spentCents), style: TextStyle(color: p.ink)),
              TextSpan(text: ' / ${Formatters.soles(row.capCents!)}', style: TextStyle(color: p.inkMuted)),
            ])),
          ]),
          const SizedBox(height: Space.sm),
          BudgetBar(
            key: Key('budget.bar.${row.categoryId}'),
            percent: row.percent,
            over: row.over,
            color: categoryColor(row.colorHex, Theme.of(context).brightness),
            height: 4,
          ),
          if (row.over) ...[
            const SizedBox(height: Space.xs),
            _OverLine(key: Key('budget.over.${row.categoryId}'), text: '${Formatters.soles(excess)} de más', size: 14),
          ],
        ]),
      ),
    );
  }
}

class _UncappedRow extends ConsumerWidget {
  const _UncappedRow({required this.row});
  final BudgetRow row;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final suggested = row.suggestedCents;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _RowShell(
        row: row,
        semantics: '${row.name}, sin techo. Definir',
        child: ExcludeSemantics(
          child: Row(children: [
            Icon(IconCatalog.iconFor(row.icon), size: 20, color: p.ink),
            const SizedBox(width: Space.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(row.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label.copyWith(color: p.ink)),
                const SizedBox(height: Space.xs),
                Text('Sin techo', style: AppType.caption.copyWith(color: p.inkMuted)),
              ]),
            ),
            Text('Definir', style: AppType.link.copyWith(color: p.inkMuted)),
          ]),
        ),
      ),
      if (suggested != null)
        Padding(
          padding: const EdgeInsets.only(left: 20 + Space.md),
          child: Row(children: [
            Expanded(
              child: Text('Sugerido por tu historial: ~${Formatters.soles(suggested)}',
                  style: AppType.caption.copyWith(color: p.inkMuted)),
            ),
            // El TextLink trae Space.lg de padding: se corre para alinear el texto con "Definir".
            Transform.translate(
              offset: const Offset(Space.lg, 0),
              child: TextLink(
                key: Key('budget.use.${row.categoryId}'),
                label: 'Usar',
                semanticsLabel: 'Usar ${Formatters.soles(suggested)} como techo de ${row.name}',
                onTap: () {
                  HapticFeedback.lightImpact();
                  ref.read(databaseProvider).setBudget(row.categoryId, suggested);
                },
              ),
            ),
          ]),
        ),
    ]);
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.summary});
  final BudgetSummary summary;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final first = summary.firstToDefine;
    return Column(key: const Key('budget.empty'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Ponle un techo a lo que más gastas y te aviso cuando te acerques.',
          style: AppType.body.copyWith(color: p.ink)),
      const SizedBox(height: Space.lg),
      PressScale(
        child: FilledButton(
          key: const Key('budget.define'),
          onPressed: first == null ? null : () => showBudgetSheet(context, first),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Space.ctaHeight)),
          child: const Text('Definir presupuestos'),
        ),
      ),
      const SizedBox(height: Space.lg),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Hoja de edición del techo

Future<void> showBudgetSheet(BuildContext context, BudgetRow row) {
  final reduced = MediaQuery.disableAnimationsOf(context);
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    sheetAnimationStyle: reduced
        ? const AnimationStyle(duration: Motion.reducedFade, reverseDuration: Motion.reducedFade)
        : const AnimationStyle(
            duration: Duration(milliseconds: 350), reverseDuration: Duration(milliseconds: 250), curve: Motion.emphasized),
    builder: (_) => BudgetSheet(row: row),
  );
}

class BudgetSheet extends ConsumerStatefulWidget {
  const BudgetSheet({super.key, required this.row});
  final BudgetRow row;

  @override
  ConsumerState<BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<BudgetSheet> {
  // Precarga: techo actual; si no hay, el sugerido; si tampoco, vacío.
  late AmountInput _amount = AmountInput.fromCents(widget.row.capCents ?? widget.row.suggestedCents ?? 0);
  bool _saving = false;
  String? _error;

  void _press(String key) {
    final next = _amount.press(key);
    if (next == null) {
      HapticFeedback.lightImpact();
      return;
    }
    setState(() => _amount = next);
  }

  Future<void> _run(Future<void> Function() write) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await write();
      HapticFeedback.lightImpact();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'No se pudo guardar. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final db = ref.read(databaseProvider);
    final row = widget.row;
    final screenH = MediaQuery.sizeOf(context).height;
    final canSave = _amount.cents > 0 && !_saving;
    final suggested = row.suggestedCents;

    final save = FilledButton(
      key: const Key('budget.sheet.save'),
      onPressed: canSave ? () => _run(() => db.setBudget(row.categoryId, _amount.cents)) : null,
      style: FilledButton.styleFrom(
        minimumSize: Size.fromHeight(Space.sheetCtaHeight(screenH)),
        disabledBackgroundColor: p.border,
        disabledForegroundColor: p.inkMuted,
      ),
      child: const Text('Guardar'),
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Column(
          key: const Key('budget.sheet'),
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SheetGrabber(),
            Semantics(header: true, child: Text(row.name, style: AppType.heading.copyWith(color: p.ink))),
            const SizedBox(height: Space.lg),
            AmountDisplay(key: const Key('budget.sheet.amount'), amount: _amount),
            if (suggested != null && suggested != _amount.cents) ...[
              const SizedBox(height: Space.sm),
              ActionChip(
                key: const Key('budget.sheet.suggested'),
                label: Text('Sugerido ~${Formatters.soles(suggested)}'),
                labelStyle: AppType.label.copyWith(color: p.ink),
                backgroundColor: p.surface,
                side: BorderSide(color: p.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.chip)),
                onPressed: () => setState(() => _amount = AmountInput.fromCents(suggested)),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: Space.xs),
              Text(_error!, style: AppType.caption.copyWith(color: p.expenseFg)),
            ],
            const SizedBox(height: Space.lg),
            AmountKeypad(
              keyHeight: Space.keyHeight(screenH),
              onKey: _press,
              onBackspace: () => setState(() => _amount = _amount.backspace()),
              onClear: () => setState(() => _amount = const AmountInput()),
            ),
            const SizedBox(height: Space.md),
            Semantics(hint: canSave ? null : 'Ingresa un monto', child: canSave ? PressScale(child: save) : save),
            if (row.capCents != null) ...[
              const SizedBox(height: Space.sm),
              Center(
                child: TextLink(
                  key: const Key('budget.sheet.remove'),
                  label: 'Quitar techo',
                  semanticsLabel: 'Quitar el techo de ${row.name}',
                  onTap: _saving ? null : () => _run(() => db.removeBudget(row.categoryId)),
                ),
              ),
            ],
            const SizedBox(height: Space.lg),
          ],
        ),
      ),
    );
  }
}
