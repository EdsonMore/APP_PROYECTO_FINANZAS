import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/icon_catalog.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart';
import '../home/providers.dart';
import 'catalog_editor.dart';
import 'settings_screen.dart';

/// Categorías de gasto o fuentes de ingreso (mismo widget). No se borra nada:
/// se archiva, para no romper movimientos ya registrados.
class CatalogScreen extends ConsumerWidget {
  const CatalogScreen({super.key, required this.kind});
  final EntryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final isExpense = kind == EntryKind.expense;
    final List<CatalogItem> items = isExpense
        ? [
            for (final c in [...?ref.watch(categoriesStreamProvider).value]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
              (id: c.id, name: c.name, icon: c.icon, archived: c.archived),
          ]
        : [
            for (final s in [...?ref.watch(sourcesStreamProvider).value]..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
              (id: s.id, name: s.name, icon: s.icon, archived: s.archived),
          ];
    final active = items.where((i) => !i.archived).toList();
    final archived = items.where((i) => i.archived).toList();

    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const Key('catalog.scroll'),
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
          children: [
            SubpageHeader(title: isExpense ? 'Categorías de gasto' : 'Fuentes de ingreso'),
            const SizedBox(height: Space.lg),
            // Defensa (decisión b): solo pasa si alguien editó la BD a mano.
            if (active.isEmpty && items.isNotEmpty)
              Padding(
                key: const Key('catalog.noActive'),
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Text(lastActiveText, style: AppType.label.copyWith(color: p.expenseFg)),
              ),
            for (final i in active)
              _CatalogRow(
                key: Key('catalog.${i.id}'),
                item: i,
                link: 'Editar',
                onTap: () => showCatalogEditor(context, kind: kind, items: items, existing: i),
              ),
            const SizedBox(height: Space.md),
            OutlinedButton(
              key: const Key('catalog.add'),
              onPressed: () => showCatalogEditor(context, kind: kind, items: items),
              child: Text(isExpense ? '+ Agregar categoría' : '+ Agregar fuente'),
            ),
            if (archived.isNotEmpty) ...[
              Divider(color: p.border, height: Space.xxl),
              Padding(
                padding: const EdgeInsets.only(bottom: Space.sm),
                child: Semantics(
                  header: true,
                  child: Text('Archivadas', style: AppType.heading.copyWith(color: p.ink)),
                ),
              ),
              for (final i in archived)
                _CatalogRow(
                  key: Key('catalog.${i.id}'),
                  item: i,
                  link: 'Reactivar',
                  muted: true,
                  onTap: () => ref.read(databaseProvider).setArchived(kind, i.id, archived: false),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CatalogRow extends StatelessWidget {
  const _CatalogRow({super.key, required this.item, required this.link, required this.onTap, this.muted = false});
  final CatalogItem item;
  final String link;
  final VoidCallback onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: '${item.name}. $link',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.button),
        child: SizedBox(
          height: 56,
          child: Row(children: [
            Icon(IconCatalog.iconFor(item.icon), size: 20, color: p.inkMuted),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.label.copyWith(color: muted ? p.inkMuted : p.ink)),
            ),
            Text(link, style: AppType.label.copyWith(color: p.inkMuted)),
            const SizedBox(width: Space.xs),
          ]),
        ),
      ),
    );
  }
}
