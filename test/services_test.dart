import 'package:flutter_test/flutter_test.dart';

import 'package:saldo_claro/core/models/category.dart';
import 'package:saldo_claro/core/models/transaction_type.dart';
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