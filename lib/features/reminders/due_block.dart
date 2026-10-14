import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/icon_catalog.dart';
import '../../core/widgets/text_link.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/recurrence.dart';
import '../home/providers.dart' show categoriesStreamProvider;
import 'actions_sheet.dart';
import 'reminders_screen.dart';
import 'service.dart';

/// Hasta 7 días antes, el pago aparece en "Por pagar" (E4).
const dueWindowDays = 7;
const _maxRows = 3;

/// "vencido hace 30 días · 2 pagos pendientes" (E3).
String dueLine(Recurrence r, DateTime today) {
  final due = parseIsoDay(r.nextDue);
  final pending = pendingPeriods(due, r.frequency, anchorDay: r.anchorDay, today: today);
  return '${dueStatus(daysToDue(due, today))}${pending > 1 ? ' · $pending pagos pendientes' : ''}';
}

/// fix5: Home, arriba del semáforo (E5). Vencidos (el más viejo arriba) y los
/// que vencen en 7 días o menos; sin ninguno, no aparece.
class DueBlock extends ConsumerWidget {
  const DueBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(recurrencesStreamProvider).value ?? const <Recurrence>[];
    final today = ref.watch(todayProvider);
    // La lista ya viene ordenada por próximo pago: los vencidos quedan arriba.
    final due = [for (final r in all) if (daysToDue(parseIsoDay(r.nextDue), today) <= dueWindowDays) r];
    if (due.isEmpty) return const SizedBox.shrink();
    final p = context.palette;
    final cats = {for (final c in ref.watch(categoriesStreamProvider).value ?? const <Category>[]) c.id: c};
    return Padding(
      key: const Key('home.due'),
      padding: const EdgeInsets.only(bottom: Space.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Semantics(header: true, child: Text('Por pagar', style: AppType.heading.copyWith(color: p.ink))),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(Radii.card),
            border: Border.all(color: p.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final r in due.take(_maxRows)) _DueRow(r: r, category: cats[r.categoryId], today: today),
            if (due.length > _maxRows)
              Align(
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: const Offset(-Space.lg, 0), // TextLink trae 16 de padding
                  child: TextLink(
                    key: const Key('home.due.all'),
                    label: 'Ver todos (${all.length})',
                    semanticsLabel: 'Ver todos los recordatorios, ${all.length}',
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute<void>(builder: (_) => const RemindersScreen())),
                  ),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({required this.r, required this.category, required this.today});
  final Recurrence r;
  final Category? category;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final name = (r.note?.trim().isNotEmpty ?? false) ? r.note!.trim() : (category?.name ?? 'Gasto');
    final color = dueColor(p, dueTone(daysToDue(parseIsoDay(r.nextDue), today)));
    final line = dueLine(r, today);
    final amount = Formatters.soles(r.amountCents);
    return Semantics(
      button: true,
      label: '$name, $amount, $line',
      excludeSemantics: true,
      child: InkWell(
        key: Key('home.due.${r.id}'),
        onTap: () => showReminderActions(context, r),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Space.sm),
            child: Row(children: [
              Icon(IconCatalog.iconFor(category?.icon ?? ''), size: 20, color: p.inkMuted),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.label.copyWith(color: p.ink)),
                  const SizedBox(height: 2),
                  // El texto dice el estado; el color y el punto lo refuerzan.
                  Row(children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: Space.xs),
                    Flexible(child: Text(line, style: AppType.caption.copyWith(color: color))),
                  ]),
                ]),
              ),
              const SizedBox(width: Space.md),
              Text(amount, style: AppType.amount.copyWith(color: p.ink)),
            ]),
          ),
        ),
      ),
    );
  }
}
