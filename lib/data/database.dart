// drift define los CHECK referenciando la propia columna; es el patrón documentado.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../domain/metrics.dart';

part 'database.g.dart';

// Esquema v1. Contrato en SPEC.md §Modelo de datos.
// Dinero en centavos enteros; fechas de evento como 'YYYY-MM-DD' local;
// timestamps como epoch ms.

enum Origin { manual, auto }

enum GoalKind { percent, fixed, cushion }

/// Columnas comunes de los catálogos (categorías de gasto y fuentes de ingreso).
mixin _Catalog on Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();
  TextColumn get icon => text()();
  TextColumn get colorHex => text()();
  IntColumn get sortOrder => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class Categories extends Table with _Catalog {}

class Sources extends Table with _Catalog {}

@TableIndex(name: 'idx_entries_on', columns: {#occurredOn})
@TableIndex(name: 'idx_entries_kind_on', columns: {#kind, #occurredOn})
class Entries extends Table {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<EntryKind>().check(kind.isIn(const ['income', 'expense']))();
  IntColumn get amountCents => integer().check(amountCents.isBiggerThanValue(0))();
  TextColumn get occurredOn => text().withLength(min: 10, max: 10)();
  TextColumn get categoryId => text().nullable().references(Categories, #id)();
  TextColumn get sourceId => text().nullable().references(Sources, #id)();
  TextColumn get note => text().nullable()();
  TextColumn get origin =>
      textEnum<Origin>().withDefault(const Constant('manual')).check(origin.isIn(const ['manual', 'auto']))();
  TextColumn get accountLabel => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK ((kind = 'expense' AND category_id IS NOT NULL AND source_id IS NULL) "
            "OR (kind = 'income' AND source_id IS NOT NULL AND category_id IS NULL))",
      ];
}

/// Una sola fila (id = 1), creada al terminar el onboarding.
class Settings extends Table {
  IntColumn get id => integer().check(id.equals(1))();
  TextColumn get mode => textEnum<Mode>().check(mode.isIn(const ['stable', 'variable', 'survival']))();
  TextColumn get spaceName => text().nullable()();
  IntColumn get runwayWindowDays =>
      integer().withDefault(const Constant(14)).check(runwayWindowDays.isBetweenValues(7, 90))();
  IntColumn get incomeWindowDays =>
      integer().withDefault(const Constant(30)).check(incomeWindowDays.isIn(const [30, 60, 90]))();
  IntColumn get openingBalanceCents => integer().nullable()();

  /// Instante (epoch ms) en que se fijó el saldo inicial. Ver [Opening].
  IntColumn get openingBalanceAt => integer().nullable()();
  BoolColumn get onboardingDone => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Techo mensual recurrente por categoría.
class Budgets extends Table {
  TextColumn get categoryId => text().references(Categories, #id)();
  IntColumn get capCents => integer().check(capCents.isBiggerThanValue(0))();

  @override
  Set<Column> get primaryKey => {categoryId};
}

class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get kind => textEnum<GoalKind>().check(kind.isIn(const ['percent', 'fixed', 'cushion']))();

  /// percent: puntos básicos (1000 = 10 %) · fixed/cushion: centavos.
  IntColumn get value => integer().check(value.isBiggerThanValue(0))();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

// id, nombre, icono (IconCatalog), color. Colores provisionales: los fija dataviz en 1c.
const _defaultCategories = [
  ('comida', 'Comida', 'restaurant', '#C2410C'),
  ('transporte', 'Transporte', 'directions_bus', '#1D4ED8'),
  ('vivienda', 'Vivienda', 'receipt', '#047857'),
  ('ocio', 'Ocio', 'movie', '#7C3AED'),
  ('salud', 'Salud', 'healing', '#BE123C'),
  ('otros', 'Otros', 'local_mall', '#525252'),
];

const _defaultSources = [
  ('chamba', 'Chamba', 'payments', '#047857'),
  ('venta', 'Venta', 'shopping_cart', '#1D4ED8'),
  ('familiar', 'Familiar', 'favorite', '#BE123C'),
  ('prestamo', 'Préstamo', 'account_balance', '#B45309'),
  ('otro', 'Otro', 'redeem', '#525252'),
];

@DriftDatabase(tables: [Categories, Sources, Entries, Settings, Budgets, Goals])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'saldoclaro'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await batch((b) {
            for (final (i, (id, name, icon, color)) in _defaultCategories.indexed) {
              b.insert(categories, CategoriesCompanion.insert(
                  id: id, name: name, icon: icon, colorHex: color, sortOrder: i, isDefault: const Value(true)));
            }
            for (final (i, (id, name, icon, color)) in _defaultSources.indexed) {
              b.insert(sources, SourcesCompanion.insert(
                  id: id, name: name, icon: icon, colorHex: color, sortOrder: i, isDefault: const Value(true)));
            }
          });
        },
        beforeOpen: (_) => customStatement('PRAGMA foreign_keys = ON'),
      );

  /// Cierra el onboarding: crea (o reemplaza) la fila única de settings.
  Future<void> completeOnboarding({required Mode mode, String? spaceName}) =>
      into(settings).insertOnConflictUpdate(SettingsCompanion.insert(
        id: const Value(1),
        mode: mode,
        spaceName: Value(spaceName),
        runwayWindowDays: const Value(14),
        incomeWindowDays: const Value(30),
        onboardingDone: const Value(true),
      ));

  Stream<Setting?> watchSettings() => (select(settings)..where((s) => s.id.equals(1))).watchSingleOrNull();
}

/// 'YYYY-MM-DD' ↔ día del dominio.
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseIsoDay(String s) => day(int.parse(s.substring(0, 4)), int.parse(s.substring(5, 7)), int.parse(s.substring(8, 10)));

extension EntryToMovement on Entry {
  Movement toMovement() => Movement(
        kind: kind,
        cents: amountCents,
        day: parseIsoDay(occurredOn),
        categoryId: categoryId,
        createdAt: DateTime.fromMillisecondsSinceEpoch(createdAt),
      );
}

extension SettingOpening on Setting {
  Opening? get opening => openingBalanceCents == null || openingBalanceAt == null
      ? null
      : Opening(cents: openingBalanceCents!, setAt: DateTime.fromMillisecondsSinceEpoch(openingBalanceAt!));
}
