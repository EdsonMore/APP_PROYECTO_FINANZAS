import 'package:flutter_test/flutter_test.dart';

import 'package:saldo_claro/core/models/category.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/models/transaction_type.dart';
import 'package:saldo_claro/core/services/insights_engine.dart';
import 'package:saldo_claro/core/services/rule_categorizer.dart';
import 'package:saldo_claro/core/utils/regex_parser.dart';

Category _category(String name, {List<String> keywords = const [], TransactionType type = TransactionType.expense}) {
  return Category(
    id: name,
    userId: 'u1',
    name: name,
    type: type,
    icon: 'category',
    colorHex: '8E44AD',
    keywords: keywords,
  );
}

Transaction _tx({
  required double amount,
  required TransactionType type,
  String? merchant,
  DateTime? at,
}) {
  return Transaction(
    id: 't${amount}_$merchant',
    userId: 'u1',
    accountId: 'a1',
    amount: amount,
    type: type,
    rawText: '',
    merchantOrPerson: merchant,
    sourceApp: 'Yape',
    source: TransactionSource.auto,
    createdAt: at ?? DateTime.now(),
  );
}

void main() {
  group('RuleCategorizer', () {
    test('clasifica por keyword de cine a "Enamorada / Pareja"', () {
      final cats = [
        _category('Restaurantes', keywords: ['restaurante', 'donde rosa']),
        _category('Enamorada / Pareja',
            keywords: ['cine', 'cinemark', 'cineplanet', 'flores', 'regalo']),
      ];

      final result = RuleCategorizer.classify(
        text: 'Cinemark Sala 3',
        categories: cats,
        fallbackType: TransactionType.expense,
      );

      expect(result, isNotNull);
      expect(result!.name, 'Enamorada / Pareja');
    });

    test('prioriza la keyword más específica', () {
      final cats = [
        _category('Compras', keywords: ['tienda']),
        _category('Enamorada / Pareja', keywords: ['restaurante dona rosa']),
        _category('Alimentos', keywords: ['restaurante']),
      ];

      final result = RuleCategorizer.classify(
        text: 'Pago en Restaurante Dona Rosa',
        categories: cats,
        fallbackType: TransactionType.expense,
      );

      expect(result, isNotNull);
      expect(result!.name, 'Enamorada / Pareja');
    });

    test('retorna null si no hay keyword coincidente', () {
      final result = RuleCategorizer.classify(
        text: 'Pago en Farmacia Inkafarma',
        categories: [_category('Alimentos', keywords: ['restaurante'])],
        fallbackType: TransactionType.expense,
      );
      expect(result, isNull);
    });
  });

  group('InsightsEngine', () {
    test('detecta gastos hormiga pequeños', () {
      final tx = [
        _tx(amount: 7.50, merchant: 'Starbucks', type: TransactionType.expense),
        _tx(amount: 4.00, merchant: 'Helado', type: TransactionType.expense),
        _tx(amount: 100.00, merchant: 'Supermercado', type: TransactionType.expense),
      ];

      final insights = InsightsEngine().detectAntExpenses(tx);

      expect(insights, hasLength(1));
      expect(insights.first.type, 'ant');
      expect(insights.first.amount, closeTo(11.50, 0.001));
    });

    test('módulo Especial Pareja suma solo la categoría objetivo', () {
      final now = DateTime.now();
      final tx = [
        _tx(amount: 30.00, merchant: 'Cinemark', type: TransactionType.expense, at: now),
        _tx(amount: 12.00, merchant: 'Starbucks', type: TransactionType.expense, at: now),
      ];

      final (total, count, name) = InsightsEngine().coupleModule(tx, ['Enamorada / Pareja']);

      expect(name, 'Enamorada / Pareja');
      expect(total, 30.00);
      expect(count, 1);
    });

    test('proyección mensual basada en gasto diario promedio', () {
      final now = DateTime.now();
      final tx = [
        _tx(amount: 50.00, merchant: 'Restaurante', type: TransactionType.expense, at: now),
      ];

      final proj = InsightsEngine().projectSpending(tx);

      expect(proj.thisMonth, 50.00);
      expect(proj.thisWeek, 50.00);
      expect(proj.monthlyProjected, greaterThan(0));
    });
  });

  group('RegexParser - apps nuevas (fallback genérico)', () {
    test('Interbank: pago a comercio', () {
      final result = RegexParser.parse(
        title: 'Interbank',
        text: 'Realizaste un pago por S/ 45.00 en Plaza Vea',
        packageName: 'com.interbank.bond',
      );
      expect(result, isNotNull);
      expect(result!.amount, 45.00);
      expect(result.isExpense, isTrue);
    });

    test('BBVA: transferencia recibida', () {
      final result = RegexParser.parse(
        title: 'BBVA',
        text: 'Recibiste un abono de S/ 600.00 de Carlos Gomez',
        packageName: 'pe.com.bbva.bbvacontigo',
      );
      expect(result, isNotNull);
      expect(result!.amount, 600.00);
      expect(result.isExpense, isFalse);
    });
  });
}