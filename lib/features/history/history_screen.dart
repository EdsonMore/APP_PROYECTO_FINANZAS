import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/icon_catalog.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../core/widgets/text_link.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';
import '../entry/entry_sheet.dart';
import '../home/home_blocks.dart';
import '../home/home_screen.dart' show deletedSnackDuration;
import '../home/providers.dart';
import '../settings/settings_screen.dart';
import 'filters.dart';

/// Historial (4B): todos los movimientos, con filtros, búsqueda en vivo,
/// edición (tocar) y borrado (deslizar + confirmación). Filtra en memoria
/// sobre el mismo stream que el Home (H2).
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key, this.initial = const HistoryFilter()});

  /// Filtro con el que abre (por defecto, todo). Lo usan las capturas.
  final HistoryFilter initial;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late HistoryFilter _f = widget.initial;
  late final _query = TextEditingController(text: widget.initial.query);

  /// C2: una fila deslizada sale de la lista en el mismo frame. Si esperara al
  /// stream de la base, Flutter vería un Dismissible ya descartado en el árbol.
  final _removed = <String>{};

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _set(HistoryFilter f) => setState(() => _f = f);

  void _reset() {
    _query.clear();
    _set(const HistoryFilter());
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final entriesAsync = ref.watch(entriesStreamProvider);
    final catsAsync = ref.watch(categoriesStreamProvider);
    final srcsAsync = ref.watch(sourcesStreamProvider);
    final today = ref.watch(todayProvider);
    final ready = entriesAsync.hasValue && catsAsync.hasValue && srcsAsync.hasValue;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, 0),
              child: SubpageHeader(title: 'Historial'),
            ),
            if (ready)
              ..._body(context, p, entriesAsync.value!, catsAsync.value!, srcsAsync.value!, today)
            else
              const Expanded(child: SizedBox()),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(
    BuildContext context,
    Palette p,
    List<Entry> entries,
    List<Category> cats,
    List<Source> srcs,
    DateTime today,
  ) {
    final all = [
      for (final e in entries)
        if (!_removed.contains(e.id)) e,
    ];
    final catById = {for (final c in cats) c.id: c};
    final srcById = {for (final s in srcs) s.id: s};
    final filtered = applyFilter(
      all,
      _f,
      today: today,
      catNames: {for (final c in cats) c.id: c.name},
      srcNames: {for (final s in srcs) s.id: s.name},
    );
    final choices = pickChoices(_f.kind, cats, srcs, all);

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, 0),
        child: _SearchField(
          controller: _query,
          onChanged: (q) => _set(_f.copyWith(query: q)),
        ),
      ),
      const SizedBox(height: Space.xs),
      // Tipo y Fecha en una fila deslizable: en 320 dp, o con un rango largo
      // ("Últimos 30 días"), no caben; "Fecha" asoma cortado y se desliza.
      SingleChildScrollView(
        key: const Key('history.filters'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
        child: Row(
          children: [
            for (final (k, label) in const [
              (KindFilter.all, 'Todos'),
              (KindFilter.expense, 'Gastos'),
              (KindFilter.income, 'Ingresos'),
            ]) ...[
              _Chip(
                key: Key('history.kind.${k.name}'),
                label: label,
                selected: _f.kind == k,
                // Otro tipo, otros chips: los marcados se limpian.
                onTap: () => _set(HistoryFilter(kind: k, preset: _f.preset, custom: _f.custom, query: _f.query)),
              ),
              const SizedBox(width: Space.sm),
            ],
            const SizedBox(width: Space.sm),
            _Chip(
              key: const Key('history.date'),
              label: rangeLabel(_f.preset, custom: _f.custom),
              semanticsLabel: 'Fecha: ${rangeLabel(_f.preset, custom: _f.custom)}. Cambiar',
              leading: Icon(
                Icons.calendar_today_outlined,
                size: 16,
                color: _f.preset == RangePreset.all ? p.ink : p.surface,
              ),
              selected: _f.preset != RangePreset.all,
              onTap: () => _pickRange(context, all, today),
            ),
          ],
        ),
      ),
      if (choices.isNotEmpty)
        // Pocos chips: se construyen todos (sin ListView perezoso).
        SingleChildScrollView(
          key: const Key('history.picks'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
          child: Row(
            children: [
              for (final c in choices) ...[
                _Chip(
                  key: Key('history.pick.${c.id}'),
                  label: c.name,
                  selected: _f.picks.contains(c.id),
                  leading: c.isCategory
                      ? Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: categoryColor(c.colorHex, Theme.of(context).brightness),
                            shape: BoxShape.circle,
                          ),
                        )
                      : Icon(IconCatalog.iconFor(c.icon), size: 16, color: _f.picks.contains(c.id) ? p.surface : p.ink),
                  onTap: () => _set(
                    _f.copyWith(picks: _f.picks.contains(c.id) ? ({..._f.picks}..remove(c.id)) : {..._f.picks, c.id}),
                  ),
                ),
                const SizedBox(width: Space.sm),
              ],
              if (_f.picks.isNotEmpty)
                _Chip(
                  key: const Key('history.clearPicks'),
                  label: 'Limpiar',
                  selected: false,
                  onTap: () => _set(_f.copyWith(picks: const {})),
                ),
            ],
          ),
        ),
      if (all.isNotEmpty && filtered.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
          child: _Totals(totals: totalsOf(filtered), kind: _f.kind),
        ),
      Expanded(
        child: all.isEmpty
            ? _Empty(
                key: const Key('history.empty'),
                title: 'Todavía no hay movimientos.',
                body: 'Registra tu primer gasto o ingreso desde el Inicio.',
              )
            : filtered.isEmpty
            ? _Empty(
                key: const Key('history.noResults'),
                title: 'Nada con estos filtros.',
                action: TextLink(
                  key: const Key('history.resetFilters'),
                  label: 'Quitar filtros',
                  semanticsLabel: 'Quitar filtros',
                  onTap: _reset,
                ),
              )
            : _list(context, p, filtered, catById, srcById, today),
      ),
    ];
  }

  Widget _list(
    BuildContext context,
    Palette p,
    List<Entry> filtered,
    Map<String, Category> catById,
    Map<String, Source> srcById,
    DateTime today,
  ) {
    final items = <Object>[
      for (final g in groupByDay(filtered)) ...[g.day, ...g.entries],
    ];
    return ListView.builder(
      key: const Key('history.list'),
      padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.xl),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is DateTime) {
          return Padding(
            key: Key('history.day.${isoDay(item)}'),
            padding: EdgeInsets.only(top: i == 0 ? Space.lg : Space.xl, bottom: Space.sm),
            child: Semantics(
              header: true,
              child: Text(
                dayHeader(item, today),
                style: AppType.label.copyWith(color: p.inkMuted, fontWeight: FontWeight.w600),
              ),
            ),
          );
        }
        final e = item as Entry;
        final row = movementRow(e, catById, srcById, today, withDay: false);
        return Dismissible(
          key: ValueKey('history.dismiss.${e.id}'),
          direction: DismissDirection.endToStart,
          // C2: Dismissible espera este Future antes de descartar; false (o
          // cerrar el diálogo sin elegir) devuelve la fila a su lugar.
          confirmDismiss: (_) => _confirmDelete(context, e, row.name),
          onDismissed: (_) => _delete(e),
          background: Container(
            color: p.expenseBg,
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: Space.lg),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_outline, size: 20, color: p.expenseFg),
                const SizedBox(width: Space.sm),
                Text('Borrar', style: AppType.label.copyWith(color: p.expenseFg)),
              ],
            ),
          ),
          child: ColoredBox(
            color: p.canvas, // tapa el fondo rojo mientras la fila está quieta
            child: MovementTile(
              key: Key('history.row.${e.id}'),
              row: row,
              fadeIn: false,
              onTap: () => editEntry(context, e),
              actions: {
                const CustomSemanticsAction(label: 'Borrar'): () async {
                  if (await _confirmDelete(context, e, row.name)) _delete(e);
                },
              },
            ),
          ),
        );
      },
    );
  }

  Future<bool> _confirmDelete(BuildContext context, Entry e, String name) async {
    final p = context.palette;
    final d = parseIsoDay(e.occurredOn);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Borrar este movimiento?'),
        content: Text(
          '$name, ${Formatters.soles(e.amountCents)}, '
          '${DateFormat('d MMM', 'es_PE').format(DateTime(d.year, d.month, d.day))}. No se puede deshacer.',
        ),
        actions: [
          TextButton(
            key: const Key('history.delete.cancel'),
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            key: const Key('history.delete.confirm'),
            onPressed: () => Navigator.of(c).pop(true),
            style: TextButton.styleFrom(foregroundColor: p.expenseFg),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _delete(Entry e) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _removed.add(e.id));
    await ref.read(databaseProvider).deleteEntry(e.id); // deja lápida si ya estaba sincronizado
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          key: Key('history.deletedSnack'),
          content: Text('Movimiento eliminado'),
          duration: deletedSnackDuration,
          behavior: SnackBarBehavior.floating,
          dismissDirection: DismissDirection.down,
        ),
      );
  }

  Future<void> _pickRange(BuildContext context, List<Entry> all, DateTime today) async {
    final chosen = await showModalBottomSheet<RangePreset>(
      context: context,
      useSafeArea: true,
      showDragHandle: false,
      sheetAnimationStyle: MediaQuery.disableAnimationsOf(context)
          ? const AnimationStyle(duration: Motion.reducedFade, reverseDuration: Motion.reducedFade)
          : const AnimationStyle(
              duration: Duration(milliseconds: 350),
              reverseDuration: Duration(milliseconds: 250),
              curve: Motion.emphasized,
            ),
      builder: (sheet) {
        final p = sheet.palette;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SheetGrabber(),
                Semantics(
                  header: true,
                  child: Text('Fecha', style: AppType.title.copyWith(color: p.ink)),
                ),
                const SizedBox(height: Space.sm),
                for (final r in RangePreset.values)
                  Semantics(
                    button: true,
                    selected: r == _f.preset,
                    child: InkWell(
                      key: Key('range.${r.name}'),
                      borderRadius: BorderRadius.circular(Radii.button),
                      onTap: () => Navigator.of(sheet).pop(r),
                      child: SizedBox(
                        height: 52,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(rangeLabel(r), style: AppType.body.copyWith(color: p.ink)),
                            ),
                            if (r == _f.preset) Icon(Icons.check, size: 20, color: p.ink),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (chosen == null || !context.mounted) return;
    if (chosen != RangePreset.custom) return _set(_f.copyWith(preset: chosen));

    DateTime local(DateTime d) => DateTime(d.year, d.month, d.day);
    final days = [for (final e in all) parseIsoDay(e.occurredOn)];
    final first = [today.subtract(const Duration(days: 730)), ...days].reduce((a, b) => a.isBefore(b) ? a : b);
    final last = [today, ...days].reduce((a, b) => a.isAfter(b) ? a : b);
    final current = _f.custom;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: local(first),
      lastDate: local(last),
      initialDateRange: current == null ? null : DateTimeRange(start: local(current.from), end: local(current.to)),
    );
    if (picked == null) return;
    _set(_f.copyWith(preset: RangePreset.custom, custom: (from: dayOf(picked.start), to: dayOf(picked.end))));
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radii.button),
      borderSide: BorderSide(color: c),
    );
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        key: const Key('history.search'),
        controller: controller,
        onChanged: onChanged,
        style: AppType.body.copyWith(color: p.ink),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Buscar movimientos',
          hintStyle: AppType.body.copyWith(color: p.inkMuted),
          prefixIcon: Icon(Icons.search, size: 20, color: p.inkMuted),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  key: const Key('history.search.clear'),
                  tooltip: 'Borrar búsqueda',
                  icon: Icon(Icons.close, size: 20, color: p.inkMuted),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
          filled: true,
          fillColor: p.surface,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: Space.md),
          border: border(p.border),
          enabledBorder: border(p.border),
          focusedBorder: border(p.ink),
        ),
      ),
    );
  }
}

/// Chip de filtro: visible 32, área táctil 48, radio 8. Elegido: fondo ink.
class _Chip extends StatelessWidget {
  const _Chip({
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
        child: Container(
          height: 48, // área táctil; el chip visible mide 32
          alignment: Alignment.center,
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
    );
  }
}

/// H7 y C3: "N movimientos · Gastos S/ X · Ingresos S/ Y" en una línea si
/// cabe; si no, el conteo arriba y los montos abajo. Montos completos, nunca
/// abreviados.
class _Totals extends StatelessWidget {
  const _Totals({required this.totals, required this.kind});
  final Totals totals;
  final KindFilter kind;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // El mismo estilo resuelto para medir y para pintar: si no, lo heredado del tema
    // (p. ej. el espaciado de letras) hace que lo medido no coincida con lo pintado.
    final base = DefaultTextStyle.of(context).style.merge(
      AppType.label.copyWith(color: p.inkMuted, fontWeight: FontWeight.w400),
    );
    TextSpan amount(String label, int cents, Color c) => TextSpan(
      children: [
        TextSpan(text: '$label '),
        TextSpan(
          text: Formatters.soles(cents).replaceAll(' ', '\u00A0'), // un monto nunca se parte
          style: AppType.amount.copyWith(fontSize: base.fontSize, color: c),
        ),
      ],
    );
    final count = TextSpan(text: totals.count == 1 ? '1 movimiento' : '${totals.count} movimientos');
    final sums = TextSpan(
      children: [
        if (kind != KindFilter.income) amount('Gastos', totals.expenseCents, p.expenseFg),
        if (kind == KindFilter.all) const TextSpan(text: ' · '),
        if (kind != KindFilter.expense) amount('Ingresos', totals.incomeCents, p.incomeFg),
      ],
    );
    final oneLine = TextSpan(
      style: base,
      children: [
        count,
        const TextSpan(text: ' · '),
        sums,
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: oneLine,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        )..layout();
        final fits = painter.width <= constraints.maxWidth;
        painter.dispose();
        if (fits) return Text.rich(oneLine, key: const Key('history.totals.oneLine'));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(style: base, children: [count]),
              key: const Key('history.totals.count'),
            ),
            Text.rich(
              TextSpan(style: base, children: [sums]),
              key: const Key('history.totals.sums'),
            ),
          ],
        );
      },
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({super.key, required this.title, this.body, this.action});
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxxl, Space.gutter, 0),
      child: Column(
        children: [
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.body.copyWith(color: p.ink),
          ),
          if (body != null) ...[
            const SizedBox(height: Space.sm),
            Text(
              body!,
              textAlign: TextAlign.center,
              style: AppType.body.copyWith(color: p.inkMuted),
            ),
          ],
          ?action,
        ],
      ),
    );
  }
}
