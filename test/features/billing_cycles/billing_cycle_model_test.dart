import 'package:flutter_test/flutter_test.dart';

import 'package:saldo_claro/features/billing_cycles/models/billing_cycle_model.dart';

void main() {
  group('BillingCategoryX.dbValue', () {
    test('coincide con el CHECK constraint de la BD', () {
      expect(BillingCategory.utilityService.dbValue, 'utility_service');
      expect(BillingCategory.subscription.dbValue, 'subscription');
    });

    test('round-trip fromDb', () {
      expect(
        BillingCategoryX.fromDb(BillingCategory.utilityService.dbValue),
        BillingCategory.utilityService,
      );
      expect(
        BillingCategoryX.fromDb(BillingCategory.subscription.dbValue),
        BillingCategory.subscription,
      );
    });
  });

  group('BillingFrequencyX.dbValue', () {
    test('coincide con el CHECK constraint de la BD', () {
      expect(BillingFrequency.monthly.dbValue, 'monthly');
      expect(BillingFrequency.bimonthly.dbValue, 'bimonthly');
      expect(BillingFrequency.yearly.dbValue, 'yearly');
    });

    test('round-trip fromDb', () {
      for (final f in BillingFrequency.values) {
        expect(BillingFrequencyX.fromDb(f.dbValue), f);
      }
    });

    test('advance meses según frecuencia', () {
      expect(BillingFrequency.monthly.months, 1);
      expect(BillingFrequency.bimonthly.months, 2);
      expect(BillingFrequency.yearly.months, 12);
    });
  });

  group('BillingStatusX.dbValue', () {
    test('coincide con el CHECK constraint de la BD', () {
      expect(BillingStatus.pending.dbValue, 'pending');
      expect(BillingStatus.paid.dbValue, 'paid');
      expect(BillingStatus.overdue.dbValue, 'overdue');
    });
  });

  group('BillingCycle', () {
    final cycle = BillingCycle(
      id: '00000000-0000-0000-0000-000000000000',
      userId: 'user-1',
      title: 'ENOSA - Luz',
      category: BillingCategory.utilityService,
      amount: 85.00,
      dueDate: DateTime(2026, 9, 10),
      frequency: BillingFrequency.monthly,
      supplyNumber: '123456789',
      keywords: const ['enosa', 'luz'],
      createdAt: DateTime(2026, 8, 1),
      updatedAt: DateTime(2026, 8, 1),
    );

    test('toMap usa valores válidos para la BD', () {
      final map = cycle.toMap();
      expect(map['category'], 'utility_service');
      expect(map['frequency'], 'monthly');
      expect(map['status'], 'pending');
      expect(map['due_date'], '2026-09-10');
    });

    test('nextDueDate suma el intervalo mensual', () {
      final next = cycle.nextDueDate();
      expect(next, DateTime(2026, 10, 10));
    });

    test('nextDueDate anual suma 12 meses', () {
      final yearly = cycle.copyWith(frequency: BillingFrequency.yearly);
      expect(yearly.nextDueDate(), DateTime(2027, 9, 10));
    });

    test('fromMap lee keywords de Postgres text[]', () {
      final map = cycle.toMap();
      map['keywords'] = ['enosa', 'luz'];
      final parsed = BillingCycle.fromMap(map);
      expect(parsed.keywords, ['enosa', 'luz']);
      expect(parsed.daysUntilDue, greaterThan(0)); // fecha futura
    });
  });
}