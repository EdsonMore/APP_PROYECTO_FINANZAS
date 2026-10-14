import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/icon_catalog.dart';
import '../../core/widgets/text_link.dart';
import '../../data/database.dart';
import '../../domain/metrics.dart' show EntryKind;
import '../entry/entry_sheet.dart';
import '../home/providers.dart' show categoriesStreamProvider;
import '../settings/settings_screen.dart' show SubpageHeader;
import 'service.dart';

/// Ajustes → Recordatorios (4D): los pagos que se repiten. Tocar edita; deslizar
/// borra. Solo viven en este teléfono (R2).
class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final list = ref.watch(recurrencesStreamProvider).value;
    final cats = ref.watch(categoriesStreamProvider).value ?? const <Category>[];
    final granted = ref.watch(notificationsGrantedProvider).value ?? true;
    if (list == null) return const Scaffold(body: SizedBox());
    final byId = {for (final c in cats) c.id: c};

    return Scaffold(
      body: SafeArea(
        child: ListView(
          key: const Key('reminders.scroll'),
          padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
          children: [
            const SubpageHeader(title: 'Recordatorios'),
            const SizedBox(height: Space.lg),
            if (!granted && list.isNotEmpty)
              Padding(
                key: const Key('reminders.noPermission'),
                padding: const EdgeInsets.only(bottom: Space.md),
                child: Row(children: [
                  Expanded(
                    child: Text('Activa las notificaciones para que te avisemos.',
                        style: AppType.caption.copyWith(color: p.inkMuted)),
                  ),
                  TextLink(
                    key: const Key('reminders.openSettings'),
                    label: 'Abrir ajustes',
                    semanticsLabel: 'Abrir ajustes de notificaciones',
                    onTap: () => ref.read(reminderNotifierProvider).openSettings(),
                  ),
                ]),
              ),
            if (list.isEmpty)
              Padding(
                key: const Key('reminders.empty'),
                padding: const EdgeInsets.symmetric(vertical: Space.xl),
                child: Text(
                  'Sin recordatorios',
                  style: AppType.body.copyWith(color: p.inkMuted),
                ),
              ),
            for (final r in list) _ReminderTile(r: r, category: byId[r.categoryId]),
            const SizedBox(height: Space.md),
            OutlinedButton(
              key: const Key('reminders.add'),
              onPressed: () => showEntrySheet(context, EntryKind.expense, newReminder: true),
              child: const Text('Nuevo recordatorio'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.r, required this.category});
  final Recurrence r;
  final Category? category;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final label = reminderLabel(r, category?.name);
    final due = parseIsoDay(r.nextDue);
    final when = '${frequencyLabels[r.frequency]} · próximo '
        '${DateFormat('d MMM', 'es_PE').format(DateTime(due.year, due.month, due.day))}';
    final amount = Formatters.soles(r.amountCents);
    Future<bool> confirm() async =>
        await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('¿Borrar este recordatorio?'),
            content: Text('$label, $amount.'),
            actions: [
              TextButton(
                key: const Key('reminders.delete.cancel'),
                onPressed: () => Navigator.of(c).pop(false),
                child: const Text('Cancelar'),
              ),
              TextButton(
                key: const Key('reminders.delete.confirm'),
                onPressed: () => Navigator.of(c).pop(true),
                style: TextButton.styleFrom(foregroundColor: p.expenseFg),
                child: const Text('Borrar'),
              ),
            ],
          ),
        ) ??
        false;
    Future<void> remove() => ref.read(reminderServiceProvider).remove(r);

    return Dismissible(
      key: ValueKey('reminders.dismiss.${r.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => confirm(),
      onDismissed: (_) => remove(),
      background: Container(
        color: p.expenseBg,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: Space.lg),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.delete_outline, size: 20, color: p.expenseFg),
          const SizedBox(width: Space.sm),
          Text('Borrar', style: AppType.label.copyWith(color: p.expenseFg)),
        ]),
      ),
      child: Semantics(
        button: true,
        label: '$label, $amount, $when',
        excludeSemantics: true,
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Borrar'): () async {
            if (await confirm()) remove();
          },
        },
        child: ColoredBox(
          color: p.canvas,
          child: InkWell(
            key: Key('reminders.${r.id}'),
            onTap: () => showEntrySheet(context, EntryKind.expense, editingReminder: r),
            borderRadius: BorderRadius.circular(Radii.button),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 64),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: Space.sm),
                child: Row(children: [
                  Icon(IconCatalog.iconFor(category?.icon ?? ''), size: 20, color: p.inkMuted),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label.copyWith(color: p.ink)),
                      const SizedBox(height: Space.xs),
                      Text(when,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.caption.copyWith(color: p.inkMuted)),
                    ]),
                  ),
                  const SizedBox(width: Space.md),
                  Text(amount, style: AppType.amount.copyWith(color: p.ink)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
