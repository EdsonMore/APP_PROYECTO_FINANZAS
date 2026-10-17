import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/insights.dart';
import '../../domain/metrics.dart';
import '../../domain/recurrence.dart';
import '../accounts/providers.dart' show accountBookOf, accountsDataProvider;
import '../home/providers.dart' show categoriesStreamProvider, entriesStreamProvider;
import '../reminders/due_block.dart' show dueWindowDays;
import '../reminders/service.dart' show recurrencesStreamProvider;
import 'ai_client.dart';

/// Un recordatorio, sin su nota (C3: las notas no salen del teléfono).
typedef ReminderFact = ({String categoryId, int cents, Frequency frequency, DateTime due});

/// Lo que la app sabe para armar los paquetes de hechos (5C-Chat). La IA nunca
/// calcula: recibe los números ya hechos, incluidos los derivados que la
/// respuesta puede necesitar (C4), porque la función valida cada "S/ …".
class FactsSource {
  const FactsSource({
    required this.movements,
    required this.today,
    required this.mode,
    this.opening,
    this.book = const AccountBook(),
    this.window = 14,
    this.reminders = const [],
    this.categoryNames = const {},
  });
  final List<Movement> movements;
  final DateTime today;
  final Mode mode;
  final Opening? opening;
  final AccountBook book;
  final int window;
  final List<ReminderFact> reminders;
  final Map<String, String> categoryNames;

  String name(String categoryId) => categoryNames[categoryId] ?? categoryId;
}

int _balance(FactsSource s) => globalBalance(s.movements, today: s.today, opening: s.opening, book: s.book);

int? _runwayDays(FactsSource s, [List<Movement>? movements]) {
  final r = runway(movements ?? s.movements, today: s.today, window: s.window, opening: s.opening, book: s.book);
  return r.status == RunwayStatus.days ? r.days : null;
}

/// Lo que va en todos los paquetes.
Map<String, Object?> baseFacts(FactsSource s) {
  final left = daysLeft(s.movements, today: s.today, opening: s.opening, book: s.book);
  return {
    'mode': s.mode.name,
    'balanceCents': _balance(s),
    'daysLeft': left.days,
    'dailyCents': ?left.dailyCents,
    'monthIncomeCents': incomeInMonth(s.movements, today: s.today),
    'monthSpentCents': spentInMonth(s.movements, today: s.today),
  };
}

List<Map<String, Object?>> _pending(FactsSource s, bool Function(int days, DateTime due) include) {
  final rows = [
    for (final r in s.reminders)
      if (include(daysToDue(r.due, s.today), r.due)) r,
  ]..sort((a, b) => a.due.compareTo(b.due));
  return [
    for (final r in rows) {'category': s.name(r.categoryId), 'amountCents': r.cents, 'daysToDue': daysToDue(r.due, s.today)},
  ];
}

/// C5: lo mismo que el bloque "Por pagar": vencidos y los de 7 días o menos.
List<Map<String, Object?>> _duePending(FactsSource s) => _pending(s, (days, _) => days <= dueWindowDays);

/// "¿Qué me conviene pagar primero?" solo aparece con 2 o más.
int duePendingCount(FactsSource s) => _duePending(s).length;

int _sum(List<Map<String, Object?>> rows) => rows.fold(0, (a, r) => a + (r['amountCents']! as int));

int _monthly(ReminderFact r) => switch (r.frequency) {
      Frequency.weekly => (r.cents * 52 / 12).round(),
      Frequency.monthly => r.cents,
      Frequency.yearly => (r.cents / 12).round(),
    };

String _ym(DateTime m) => '${m.year}-${m.month.toString().padLeft(2, '0')}';

/// Por categoría en los últimos 30 días, de mayor a menor.
List<({String categoryId, int total, int count})> _byCategory30(FactsSource s) {
  final from = s.today.subtract(const Duration(days: 29));
  final total = <String, int>{}, count = <String, int>{};
  for (final m in s.movements) {
    if (m.kind != EntryKind.expense || m.categoryId == null || m.day.isBefore(from) || m.day.isAfter(s.today)) continue;
    total.update(m.categoryId!, (v) => v + m.cents, ifAbsent: () => m.cents);
    count.update(m.categoryId!, (v) => v + 1, ifAbsent: () => 1);
  }
  return [for (final c in total.keys) (categoryId: c, total: total[c]!, count: count[c]!)]
    ..sort((a, b) => b.total.compareTo(a.total));
}

/// Meses cerrados, como mucho los últimos [months], desde el mes del primer
/// movimiento. A diferencia de "Tus meses", el primero cuenta aunque empiece a
/// mitad (partial): si no, quien empezó un 10 llegaba sin meses (fase-5c-chat-fix).
List<({DateTime month, int income, int expense, bool partial})> _closedMonths(FactsSource s, int months) {
  final first = firstDay(s.movements, today: s.today);
  if (first == null) return const [];
  final start = DateTime.utc(first.year, first.month);
  final earliest = DateTime.utc(s.today.year, s.today.month - months);
  final current = DateTime.utc(s.today.year, s.today.month);
  int sum(DateTime m, EntryKind kind) => s.movements
      .where((x) => x.kind == kind && x.day.year == m.year && x.day.month == m.month)
      .fold(0, (a, x) => a + x.cents);
  return [
    for (var m = start.isAfter(earliest) ? start : earliest; m.isBefore(current); m = DateTime.utc(m.year, m.month + 1))
      (month: m, income: sum(m, EntryKind.income), expense: sum(m, EntryKind.expense), partial: m == start && first.day != 1),
  ];
}

/// El paquete de [q]. [amountCents]: el monto que escribió la persona (1 y 2).
Map<String, Object?> factsFor(AiQuestion q, FactsSource s, {int? amountCents}) {
  final base = baseFacts(s);
  final b = base['balanceCents']! as int;
  final x = amountCents ?? 0;
  switch (q) {
    case AiQuestion.canSpend:
      final monthEnd = DateTime.utc(s.today.year, s.today.month + 1, 0);
      final pending = _pending(s, (_, due) => !due.isAfter(monthEnd));
      final total = _sum(pending);
      final after = [...s.movements, Movement(kind: EntryKind.expense, cents: x, day: s.today)];
      return {
        ...base,
        'amountCents': x,
        'balanceAfterCents': b - x,
        'dailyAfterCents': math.max(0, b - x) ~/ (base['daysLeft']! as int),
        'runwayDays': ?_runwayDays(s),
        'runwayAfterDays': ?_runwayDays(s, after),
        'pending': pending,
        'pendingTotalCents': total,
        'balanceAfterPendingCents': b - x - total,
      };
    case AiQuestion.whatIf:
      final income = avgIncome30(s.movements, today: s.today, opening: s.opening);
      final expense = avgExpense30(s.movements, today: s.today, opening: s.opening);
      int? days(int monthly) => b > 0 && monthly > 0 ? b * 30 ~/ monthly : null;
      return {
        ...base,
        'amountCents': x,
        'avgIncome30Cents': income,
        'avgExpense30Cents': expense,
        'expenseWithExtraCents': expense + x,
        'monthlyNetCents': income - expense,
        'monthlyNetWithExtraCents': income - expense - x,
        'runwayDays': ?days(expense),
        'runwayWithExtraDays': ?days(expense + x),
      };
    case AiQuestion.breakEven:
      final expense = avgExpense30(s.movements, today: s.today, window: 90, opening: s.opening);
      final fixed = [for (final r in s.reminders) {'category': s.name(r.categoryId), 'monthlyCents': _monthly(r)}];
      final fixedTotal = fixed.fold(0, (a, f) => a + (f['monthlyCents']! as int));
      return {
        ...base,
        'avgExpense30Cents': expense,
        'fixed': fixed,
        'fixedMonthlyCents': fixedTotal,
        'variableMonthlyCents': math.max(0, expense - fixedTotal),
        'targetCents': expense,
        'targetComfortCents': (expense * 1.1).round(),
        'avgIncome30Cents': avgIncome30(s.movements, today: s.today, window: 90, opening: s.opening),
        'incomeByMonth': [
          for (final m in incomeByClosedMonth(s.movements, today: s.today, months: 3))
            {'month': _ym(m.month), 'incomeCents': m.cents},
        ],
      };
    case AiQuestion.cut:
      final fixedCats = {for (final r in s.reminders) r.categoryId};
      return {
        ...base,
        'categories': [
          for (final c in _byCategory30(s).take(6))
            {
              'category': s.name(c.categoryId),
              'totalCents': c.total,
              'count': c.count,
              'avgTicketCents': (c.total / c.count).round(),
              'halfCents': (c.total / 2).round(),
              'fixed': fixedCats.contains(c.categoryId),
            },
        ],
      };
    case AiQuestion.save:
      final months = _closedMonths(s, 6);
      final surplus = [for (final m in months) if (m.income - m.expense > 0) m.income - m.expense];
      final income30 = avgIncome30(s.movements, today: s.today, opening: s.opening);
      final expense30 = avgExpense30(s.movements, today: s.today, opening: s.opening);
      return {
        ...base,
        'months': [
          for (final m in months)
            {
              'month': _ym(m.month),
              'incomeCents': m.income,
              'expenseCents': m.expense,
              'netCents': m.income - m.expense,
              if (m.partial) 'partial': true,
            },
        ],
        if (surplus.isNotEmpty) 'avgSurplusCents': (surplus.reduce((a, c) => a + c) / surplus.length).round(),
        'surplusMonths': surplus.length,
        'redMonths': months.where((m) => m.income < m.expense).length,
        // Sin meses cerrados (empezó este mes), la referencia sale de los últimos 30 días.
        'avgIncome30Cents': income30,
        'avgExpense30Cents': expense30,
        'net30Cents': income30 - expense30,
        if (months.isNotEmpty)
          'tenPercentIncomeCents': (months.fold(0, (a, m) => a + m.income) / months.length * 0.1).round(),
        'runwayDays': ?_runwayDays(s),
      };
    case AiQuestion.payFirst:
      final pending = _duePending(s);
      final total = _sum(pending);
      return {
        ...base,
        'pending': pending,
        'pendingTotalCents': total,
        'shortfallCents': math.max(0, total - math.max(0, b)),
      };
    case AiQuestion.free:
      return {
        ...base,
        'topCategories': [
          for (final c in _byCategory30(s).take(4)) {'category': s.name(c.categoryId), 'totalCents': c.total},
        ],
        'pending': _duePending(s),
        'avgIncome30Cents': avgIncome30(s.movements, today: s.today, opening: s.opening),
        'avgExpense30Cents': avgExpense30(s.movements, today: s.today, opening: s.opening),
        'runwayDays': ?_runwayDays(s),
      };
  }
}

/// Todo lo necesario para los paquetes; null mientras carga.
final aiFactsSourceProvider = Provider<FactsSource?>((ref) {
  final settings = ref.watch(settingsProvider).value;
  final entries = ref.watch(entriesStreamProvider).value;
  final accounts = ref.watch(accountsDataProvider);
  final reminders = ref.watch(recurrencesStreamProvider).value;
  final categories = ref.watch(categoriesStreamProvider).value;
  if (entries == null || accounts == null || reminders == null || categories == null) return null;
  return FactsSource(
    movements: [for (final e in entries) e.toMovement()],
    today: ref.watch(todayProvider),
    mode: settings?.mode ?? Mode.variable,
    opening: settings?.opening,
    book: accountBookOf(accounts.accounts, accounts.transfers),
    window: settings?.runwayWindowDays ?? 14,
    reminders: [
      for (final r in reminders)
        (categoryId: r.categoryId, cents: r.amountCents, frequency: r.frequency, due: parseIsoDay(r.nextDue)),
    ],
    categoryNames: {for (final c in categories) c.id: c.name},
  );
});
