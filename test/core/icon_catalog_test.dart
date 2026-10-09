import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/core/widgets/icon_catalog.dart';
import 'package:saldo_claro/data/database.dart';

void main() {
  test('todo ícono del catálogo existe (codePoint != 0)', () {
    for (final icon in IconCatalog.all) {
      expect(icon.codePoint, isNot(0), reason: '$icon no existe');
    }
  });

  test('cada ícono de la semilla v1 está en el catálogo', () {
    for (final (id, _, icon, _) in [...defaultCategories, ...defaultSources]) {
      expect(IconCatalog.items, contains(icon), reason: '$id usa "$icon", que no está en IconCatalog');
    }
  });

  test('Vivienda usa Icons.home', () {
    final vivienda = defaultCategories.firstWhere((c) => c.$1 == 'vivienda');
    expect(IconCatalog.iconFor(vivienda.$3), Icons.home);
  });

  test('Comida y Chamba encabezan la semilla (preselección por defecto)', () {
    expect(defaultCategories.first.$1, 'comida');
    expect(defaultSources.first.$1, 'chamba');
  });

  test('nombre desconocido → fallback, no crash', () {
    expect(IconCatalog.iconFor('no_existe'), IconCatalog.fallback);
    expect(IconCatalog.iconFor(null), IconCatalog.fallback);
  });
}
