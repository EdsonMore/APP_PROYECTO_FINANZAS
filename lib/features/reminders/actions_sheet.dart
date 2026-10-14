import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/sheet_grabber.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart' show EntryKind;
import '../../domain/recurrence.dart';
import '../entry/entry_sheet.dart';
import '../home/home_screen.dart' show showUndoSnack;
import 'service.dart';

/// "Saltar este mes" / "esta semana" / "este año".
const skipLabels = {
  Frequency.weekly: 'Saltar esta semana',
  Frequency.monthly: 'Saltar este mes',
  Frequency.yearly: 'Saltar este año',
};

String _dayMonth(DateTime d, [String pattern = 'd MMM']) =>
    DateFormat(pattern, 'es_PE').format(DateTime(d.year, d.month, d.day));

enum _Action { pay, skip, edit, delete }

/// fix5: tocar un recordatorio (Home "Por pagar" o Ajustes → Recordatorios):
/// Pagado, Saltar, Editar o Borrar.
Future<void> showReminderActions(BuildContext context, Recurrence r) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final db = container.read(databaseProvider);
  final today = container.read(todayProvider);
  final category = await (db.select(db.categories)..where((c) => c.id.equals(r.categoryId))).getSingleOrNull();
  if (!context.mounted) return;
  final due = parseIsoDay(r.nextDue);
  final days = daysToDue(due, today);
  final action = await showModalBottomSheet<_Action>(
    context: context,
    useSafeArea: true,
    showDragHandle: false,
    builder: (sheet) {
      final p = sheet.palette;
      Widget option(_Action a, String label, {Color? color}) => InkWell(
            key: Key('reminder.${a.name}'),
            borderRadius: BorderRadius.circular(Radii.button),
            onTap: () => Navigator.of(sheet).pop(a),
            child: SizedBox(
              height: 52,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(label, style: AppType.body.copyWith(color: color ?? p.ink)),
              ),
            ),
          );
      return SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.gutter, 0, Space.gutter, Space.lg),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SheetGrabber(),
            Semantics(
              header: true,
              child: Text(reminderLabel(r, category?.name), style: AppType.title.copyWith(color: p.ink)),
            ),
            const SizedBox(height: Space.xs),
            Text('${Formatters.soles(r.amountCents)} · ${dueStatus(days)}',
                style: AppType.body.copyWith(color: dueColor(p, dueTone(days)))),
            Text('${frequencyLabels[r.frequency]} · ${days < 0 ? 'venció' : 'vence'} el ${_dayMonth(due, 'EEE d MMM')}',
                style: AppType.caption.copyWith(color: p.inkMuted)),
            const SizedBox(height: Space.lg),
            FilledButton(
              key: const Key('reminder.pay'),
              onPressed: () => Navigator.of(sheet).pop(_Action.pay),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(Space.ctaHeight)),
              child: const Text('Pagado'),
            ),
            const SizedBox(height: Space.sm),
            option(_Action.skip, skipLabels[r.frequency]!),
            option(_Action.edit, 'Editar'),
            option(_Action.delete, 'Borrar', color: p.expenseFg),
          ]),
        ),
      );
    },
  );
  if (action == null || !context.mounted) return;
  final service = container.read(reminderServiceProvider);
  switch (action) {
    case _Action.pay:
      await payReminder(context, r);
    case _Action.skip:
      final messenger = ScaffoldMessenger.maybeOf(context);
      final previous = await service.skip(r.id);
      final next = (await (db.select(db.recurrences)..where((x) => x.id.equals(r.id))).getSingleOrNull())?.nextDue;
      if (previous == null || next == null || messenger == null) return;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          key: const Key('reminder.skippedSnack'),
          content: Text('Saltado. Próximo: ${_dayMonth(parseIsoDay(next))}'),
          persist: false,
          behavior: SnackBarBehavior.floating,
          dismissDirection: DismissDirection.down,
          action: SnackBarAction(label: 'Deshacer', onPressed: () => service.setDue(r.id, previous)),
        ));
    case _Action.edit:
      await showEntrySheet(context, EntryKind.expense, editingReminder: r);
    case _Action.delete:
      if (await confirmDeleteReminder(context, reminderLabel(r, category?.name), r.amountCents)) {
        await service.remove(r);
      }
  }
}

/// Pagado (también al tocar la notificación). E1: si ya hay un gasto igual
/// (categoría y monto) desde el vencimiento anterior, pregunta antes de crear
/// otro; si no, la hoja precargada. Al guardar, el vencimiento avanza.
Future<void> payReminder(BuildContext context, Recurrence r) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final db = container.read(databaseProvider);
  final service = container.read(reminderServiceProvider);
  final messenger = ScaffoldMessenger.maybeOf(context);
  final match = await service.findPayment(r, today: container.read(todayProvider));
  if (match != null) {
    final category = await (db.select(db.categories)..where((c) => c.id.equals(r.categoryId))).getSingleOrNull();
    if (!context.mounted) return;
    final useIt = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Ya lo registraste?'),
        content: Text('Anotaste ${Formatters.soles(match.amountCents)} en ${category?.name ?? 'Gasto'} '
            'el ${_dayMonth(parseIsoDay(match.occurredOn))}.'),
        actions: [
          TextButton(
              key: const Key('reminder.match.other'),
              onPressed: () => Navigator.of(c).pop(false),
              child: const Text('Registrar otro')),
          TextButton(
              key: const Key('reminder.match.same'),
              onPressed: () => Navigator.of(c).pop(true),
              child: const Text('Sí, es ese')),
        ],
      ),
    );
    if (useIt == null) return; // cerró sin elegir
    if (useIt) return service.confirmed(r.id);
  }
  if (!context.mounted) return;
  final entry = await showEntrySheet(context, EntryKind.expense, reminder: r);
  if (entry != null && messenger != null) showUndoSnack(messenger, db, entry);
}

Future<bool> confirmDeleteReminder(BuildContext context, String label, int cents) async {
  final p = context.palette;
  return await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('¿Borrar este recordatorio?'),
          content: Text('$label, ${Formatters.soles(cents)}.'),
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
}

/// Rojo si venció o vence hoy, ámbar a 1-3 días (el del semáforo), neutro después.
Color dueColor(Palette p, DueTone t) => switch (t) {
      DueTone.overdue => p.expenseFg,
      DueTone.soon => p.amberFg,
      DueTone.later => p.inkMuted,
    };
