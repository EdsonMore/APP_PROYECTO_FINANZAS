import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/utils/formatters.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/insights.dart';
import '../../domain/metrics.dart' show EntryKind;
import '../../domain/recurrence.dart';
import '../entry/draft_store.dart' show sharedPreferencesProvider;
import '../entry/entry_sheet.dart';
import '../home/providers.dart' show categoriesStreamProvider, entriesStreamProvider;
import 'service.dart';

/// H5: los descartados ("No, gracias"), solo en este teléfono.
const dismissedSuggestionsKey = 'reminders.dismissedSuggestions';
const _maxSuggestions = 2;

final dismissedSuggestionsProvider = StateProvider<Set<String>>(
    (ref) => {...?ref.watch(sharedPreferencesProvider).getStringList(dismissedSuggestionsKey)});

/// 5AB: pagos que se repiten cada mes (H3) sin recordatorio igual (misma
/// categoría y monto) ni descartados. Máximo 2.
final suggestedRemindersProvider = Provider<List<RecurringPayment>>((ref) {
  final entries = ref.watch(entriesStreamProvider).value ?? const <Entry>[];
  final existing = {for (final r in ref.watch(recurrencesStreamProvider).value ?? const <Recurrence>[]) '${r.categoryId}|${r.amountCents}'};
  final dismissed = ref.watch(dismissedSuggestionsProvider);
  final paid = <PaidExpense>[
    for (final e in entries)
      if (e.kind == EntryKind.expense && e.categoryId != null)
        (categoryId: e.categoryId!, cents: e.amountCents, day: parseIsoDay(e.occurredOn), note: e.note, accountId: e.accountId),
  ];
  return [
    for (final p in recurringPayments(paid, today: ref.watch(todayProvider)))
      if (!existing.contains(p.key) && !dismissed.contains(p.key)) p,
  ].take(_maxSuggestions).toList();
});

/// "¿Crear recordatorio para Internet cada mes?" — Crear abre el editor
/// precargado (H4: confirma el usuario); No, gracias la descarta (H5).
class SuggestionCard extends ConsumerWidget {
  const SuggestionCard({super.key, required this.payment});
  final RecurringPayment payment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.palette;
    final cats = ref.watch(categoriesStreamProvider).value ?? const <Category>[];
    final category = cats.where((c) => c.id == payment.categoryId).firstOrNull?.name ?? 'Gasto';
    final name = payment.note ?? category;
    return Container(
      key: Key('reminders.suggest.${payment.key}'),
      margin: const EdgeInsets.only(bottom: Space.md),
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.xs),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(Radii.card),
        border: Border.all(color: p.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('¿Crear recordatorio para $name cada mes?', style: AppType.label.copyWith(color: p.ink)),
        const SizedBox(height: Space.xs),
        Text('${Formatters.soles(payment.cents)} · el ${payment.anchorDay} de cada mes',
            style: AppType.caption.copyWith(color: p.inkMuted)),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          TextButton(
            key: const Key('reminders.suggest.dismiss'),
            onPressed: () => _dismiss(ref),
            child: const Text('No, gracias'),
          ),
          const SizedBox(width: Space.xs),
          TextButton(
            key: const Key('reminders.suggest.create'),
            onPressed: () => _create(context, ref),
            child: const Text('Crear'),
          ),
        ]),
      ]),
    );
  }

  void _dismiss(WidgetRef ref) {
    final next = {...ref.read(dismissedSuggestionsProvider), payment.key};
    ref.read(dismissedSuggestionsProvider.notifier).state = next;
    ref.read(sharedPreferencesProvider).setStringList(dismissedSuggestionsKey, next.toList());
  }

  /// Próximo pago: el mismo día del mes siguiente al último pago, nunca antes de hoy.
  void _create(BuildContext context, WidgetRef ref) {
    final today = ref.read(todayProvider);
    var due = nextDue(payment.last, Frequency.monthly, anchorDay: payment.anchorDay);
    while (due.isBefore(today)) {
      due = nextDue(due, Frequency.monthly, anchorDay: payment.anchorDay);
    }
    showEntrySheet(context, EntryKind.expense,
        newReminder: true,
        reminderDraft: (
          cents: payment.cents,
          categoryId: payment.categoryId,
          accountId: payment.accountId,
          note: payment.note,
          due: due,
        ));
  }
}
