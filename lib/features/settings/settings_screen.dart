import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';
import '../entry/opening_balance_sheet.dart';
import '../home/providers.dart';
import 'about_screen.dart';
import 'catalog_screen.dart';
import 'csv_exporter.dart';
import 'mode_picker.dart';
import 'name_dialog.dart';
import 'runway_picker.dart';

/// Nombre visible de cada modo (C1). "Supervivencia" también en Insights (1c).
const modeLabels = {Mode.stable: 'Estable', Mode.variable: 'Variable', Mode.survival: 'Supervivencia'};

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exporting = false;

  Future<void> _export(List<Entry> entries) async {
    final categories = ref.read(categoriesStreamProvider).value ?? const [];
    final sources = ref.read(sourcesStreamProvider).value ?? const [];
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _exporting = true);
    try {
      final csv = entriesToCsv(entries, categories: categories, sources: sources);
      await ref.read(csvExporterProvider)(csv, csvFileName(ref.read(todayProvider)));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('No se pudo exportar. Intenta de nuevo.')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final settings = ref.watch(settingsProvider).value;
    final entries = ref.watch(entriesStreamProvider).value ?? const <Entry>[];
    final cats = ref.watch(categoriesStreamProvider).value ?? const <Category>[];
    final srcs = ref.watch(sourcesStreamProvider).value ?? const <Source>[];
    final today = ref.watch(todayProvider);

    final opening = settings?.opening;
    final activeCats = cats.where((c) => !c.archived).length;
    final activeSrcs = srcs.where((s) => !s.archived).length;
    String actives(int n) => n == 1 ? '1 activa' : '$n activas';

    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const Key('settings.scroll'),
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
          children: [
            const SubpageHeader(title: 'Ajustes'),
            const SizedBox(height: Space.lg),
            SettingsRow(
              key: const Key('settings.mode'),
              label: 'Modo de uso',
              value: modeLabels[settings?.mode ?? Mode.variable]!,
              link: 'Cambiar',
              onTap: () => showModePicker(context),
            ),
            SettingsRow(
              key: const Key('settings.name'),
              label: 'Nombre del espacio',
              value: settings?.spaceName ?? defaultSpaceName,
              link: 'Editar',
              onTap: () => showNameDialog(context, settings?.spaceName),
            ),
            SettingsRow(
              key: const Key('settings.opening'),
              label: 'Saldo inicial',
              value: opening == null
                  ? 'Sin definir'
                  : '${Formatters.soles(opening.cents)} · desde ${shortDay(opening.day, today)}',
              link: 'Cambiar',
              onTap: () => showOpeningBalanceSheet(context),
            ),
            SettingsRow(
              key: const Key('settings.runway'),
              label: 'Ventana de runway',
              value: '${settings?.runwayWindowDays ?? 14} días',
              link: 'Cambiar',
              onTap: () => showRunwayPicker(context, settings?.runwayWindowDays ?? 14),
            ),
            Divider(color: p.border, height: Space.xl),
            SettingsRow(
              key: const Key('settings.categories'),
              label: 'Categorías de gasto',
              value: actives(activeCats),
              link: 'Gestionar',
              onTap: () => _push(context, const CatalogScreen(kind: EntryKind.expense)),
            ),
            SettingsRow(
              key: const Key('settings.sources'),
              label: 'Fuentes de ingreso',
              value: actives(activeSrcs),
              link: 'Gestionar',
              onTap: () => _push(context, const CatalogScreen(kind: EntryKind.income)),
            ),
            Divider(color: p.border, height: Space.xl),
            SettingsRow(
              key: const Key('settings.export'),
              label: 'Exportar CSV',
              value: switch (entries.length) {
                0 => 'Todavía no hay movimientos',
                1 => '1 movimiento',
                final n => '$n movimientos',
              },
              link: 'Exportar',
              busy: _exporting,
              onTap: entries.isEmpty || _exporting ? null : () => _export(entries),
            ),
            Divider(color: p.border, height: Space.xl),
            SettingsRow(
              key: const Key('settings.about'),
              label: 'Acerca de y privacidad',
              value: 'Versión $appVersion',
              chevron: true,
              onTap: () => _push(context, const AboutScreen()),
            ),
          ],
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
}

/// "‹  Título" de las pantallas de Ajustes. El chevron vuelve (igual que Atrás).
class SubpageHeader extends StatelessWidget {
  const SubpageHeader({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SizedBox(
      height: 48,
      child: Row(children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          tooltip: 'Volver',
          icon: Icon(Icons.chevron_left, size: 24, color: p.inkMuted),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          style: IconButton.styleFrom(alignment: Alignment.centerLeft),
        ),
        const SizedBox(width: Space.xs),
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.title.copyWith(color: p.ink)),
          ),
        ),
      ]),
    );
  }
}

/// Fila de ajuste: nombre + valor actual a la izquierda, enlace (o chevron) a
/// la derecha. Toda la fila es tocable. [onTap] null = deshabilitada.
class SettingsRow extends StatefulWidget {
  const SettingsRow({
    super.key,
    required this.label,
    required this.value,
    this.link,
    this.chevron = false,
    this.busy = false,
    required this.onTap,
  });

  final String label;
  final String value;
  final String? link;
  final bool chevron;
  final bool busy;
  final VoidCallback? onTap;

  @override
  State<SettingsRow> createState() => _SettingsRowState();
}

class _SettingsRowState extends State<SettingsRow> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = widget.onTap != null;
    final Widget trailing;
    if (widget.busy) {
      trailing = SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: p.inkMuted));
    } else if (widget.chevron) {
      trailing = Icon(Icons.chevron_right, size: 20, color: p.inkMuted);
    } else {
      trailing = Text(widget.link ?? '',
          style: AppType.label.copyWith(color: enabled ? p.inkMuted : p.inkMuted.withValues(alpha: 0.45)));
    }
    return Semantics(
      button: true,
      enabled: enabled,
      label: '${widget.label}, ${widget.value}${widget.link == null ? '' : '. ${widget.link}'}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.press,
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(vertical: Space.md, horizontal: Space.xs),
          decoration: BoxDecoration(
            color: _down ? p.border : Colors.transparent,
            borderRadius: BorderRadius.circular(Radii.button),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.label, style: AppType.label.copyWith(color: p.ink)),
                const SizedBox(height: Space.xs),
                Text(widget.value,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.caption.copyWith(color: p.inkMuted)),
              ]),
            ),
            const SizedBox(width: Space.md),
            trailing,
          ]),
        ),
      ),
    );
  }
}
