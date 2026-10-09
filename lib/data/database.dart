// drift define los CHECK referenciando la propia columna; es el patrón documentado.
// ignore_for_file: recursive_getters

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:drift_flutter/drift_flutter.dart';

import '../domain/metrics.dart';

import 'database.steps.dart';

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

/// Cuentas (Yape, BCP, crédito, efectivo). Vacía hasta la Fase 3: sin UI ni
/// semilla. Existe desde la v2 para no reconstruir `entries` cuando llegue la
/// FK con datos reales. A diferencia de categorías y fuentes, las crea el
/// usuario: `created_at` sirve para ordenarlas.
class Accounts extends Table with _Catalog {
  IntColumn get createdAt => integer()();
}

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

  /// Siempre null hasta la Fase 3 (multi-cuenta). Si se borra la cuenta, el
  /// movimiento se conserva sin cuenta.
  TextColumn get accountId => text().nullable().references(Accounts, #id, onDelete: KeyAction.setNull)();
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

/// Semillas v1: (id, nombre, icono de IconCatalog, color). Expuestas para tests.
// id, nombre, icono (IconCatalog), color. Colores provisionales: los fija dataviz en 1c.
const defaultCategories = [
  ('comida', 'Comida', 'restaurant', '#C2410C'),
  ('transporte', 'Transporte', 'directions_bus', '#1D4ED8'),
  ('vivienda', 'Vivienda', 'home', '#047857'),
  ('ocio', 'Ocio', 'movie', '#7C3AED'),
  ('salud', 'Salud', 'healing', '#BE123C'),
  ('otros', 'Otros', 'category', '#525252'),
];

const defaultSources = [
  ('chamba', 'Chamba', 'payments', '#047857'),
  ('venta', 'Venta', 'shopping_cart', '#1D4ED8'),
  ('familiar', 'Familiar', 'favorite', '#BE123C'),
  ('prestamo', 'Préstamo', 'account_balance', '#B45309'),
  ('otro', 'Otro', 'redeem', '#525252'),
];

@DriftDatabase(tables: [Categories, Sources, Entries, Settings, Budgets, Goals, Accounts])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'saldoclaro'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await batch((b) {
            for (final (i, (id, name, icon, color)) in defaultCategories.indexed) {
              b.insert(categories, CategoriesCompanion.insert(
                  id: id, name: name, icon: icon, colorHex: color, sortOrder: i, isDefault: const Value(true)));
            }
            for (final (i, (id, name, icon, color)) in defaultSources.indexed) {
              b.insert(sources, SourcesCompanion.insert(
                  id: id, name: name, icon: icon, colorHex: color, sortOrder: i, isDefault: const Value(true)));
            }
          });
        },
        onUpgrade: (m, from, to) async {
          // Una transacción: si un paso falla, la base vuelve entera a la
          // versión anterior (drift no envuelve la migración por su cuenta y
          // solo sube user_version si todo termina bien).
          await transaction(() => stepByStep(from1To2: migrateV1ToV2)(m, from, to));
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          // Solo en debug: una migración no debe dejar referencias rotas.
          if (kDebugMode && details.hadUpgrade) {
            final broken = await customSelect('PRAGMA foreign_key_check').get();
            if (broken.isNotEmpty) throw StateError('foreign_key_check: ${broken.map((r) => r.data).toList()}');
          }
        },
      );

  /// v1 → v2: tabla `accounts` vacía, `entries.account_id` nulo con FK y el
  /// ícono de "Otros" corregido solo si sigue siendo el original.
  /// Usa las tablas tal como eran en v2 ([Schema2]): una v3 que cambie
  /// `entries` no rompe este paso.
  @visibleForTesting
  Future<void> migrateV1ToV2(Migrator m, Schema2 schema) async {
    await m.createTable(schema.accounts); // primero: account_id la referencia
    await m.addColumn(schema.entries, schema.entries.accountId); // ADD COLUMN, sin reconstruir la tabla
    await customUpdate(
      "UPDATE categories SET icon = 'category' WHERE id = 'otros' AND icon = 'local_mall'",
      updates: {categories},
    );
  }

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

  Future<void> _updateSettings(SettingsCompanion c) => (update(settings)..where((s) => s.id.equals(1))).write(c);

  Future<void> setMode(Mode mode) => _updateSettings(SettingsCompanion(mode: Value(mode)));

  /// null = sin nombre (el Home muestra "Mis cuentas").
  Future<void> setSpaceName(String? name) => _updateSettings(SettingsCompanion(spaceName: Value(name)));

  Future<void> setRunwayWindow(int days) => _updateSettings(SettingsCompanion(runwayWindowDays: Value(days)));

  // ---- Catálogos (categorías de gasto y fuentes de ingreso).
  // Dos tablas con las mismas columnas: [kind] elige cuál.

  /// Todos los ítems (activos y archivados) en su orden.
  Future<List<CatalogItem>> catalog(EntryKind kind) async {
    if (kind == EntryKind.expense) {
      final rows = await (select(categories)..orderBy([(c) => OrderingTerm(expression: c.sortOrder)])).get();
      return [for (final r in rows) (id: r.id, name: r.name, icon: r.icon, archived: r.archived)];
    }
    final rows = await (select(sources)..orderBy([(s) => OrderingTerm(expression: s.sortOrder)])).get();
    return [for (final r in rows) (id: r.id, name: r.name, icon: r.icon, archived: r.archived)];
  }

  Future<int> _nextSortOrder(EntryKind kind) async {
    final expr = kind == EntryKind.expense ? categories.sortOrder.max() : sources.sortOrder.max();
    final q = kind == EntryKind.expense ? (selectOnly(categories)..addColumns([expr])) : (selectOnly(sources)..addColumns([expr]));
    final max = await q.map((r) => r.read(expr)).getSingle();
    return (max ?? -1) + 1;
  }

  /// Nuevo ítem al final del orden. Color neutro: la paleta llega en 1c (dataviz).
  Future<void> addCatalogItem(EntryKind kind, {required String id, required String name, required String icon}) async {
    final order = await _nextSortOrder(kind);
    if (kind == EntryKind.expense) {
      await into(categories)
          .insert(CategoriesCompanion.insert(id: id, name: name, icon: icon, colorHex: newItemColor, sortOrder: order));
    } else {
      await into(sources)
          .insert(SourcesCompanion.insert(id: id, name: name, icon: icon, colorHex: newItemColor, sortOrder: order));
    }
  }

  Future<void> updateCatalogItem(EntryKind kind, String id, {required String name, required String icon}) =>
      kind == EntryKind.expense
          ? (update(categories)..where((c) => c.id.equals(id)))
              .write(CategoriesCompanion(name: Value(name), icon: Value(icon)))
          : (update(sources)..where((c) => c.id.equals(id))).write(SourcesCompanion(name: Value(name), icon: Value(icon)));

  /// Archivar no borra: los movimientos viejos siguen apuntando al ítem.
  /// Reactivar lo manda al final de los activos.
  Future<void> setArchived(EntryKind kind, String id, {required bool archived}) async {
    final order = archived ? null : await _nextSortOrder(kind);
    if (kind == EntryKind.expense) {
      await (update(categories)..where((c) => c.id.equals(id))).write(CategoriesCompanion(
          archived: Value(archived), sortOrder: order == null ? const Value.absent() : Value(order)));
    } else {
      await (update(sources)..where((c) => c.id.equals(id))).write(
          SourcesCompanion(archived: Value(archived), sortOrder: order == null ? const Value.absent() : Value(order)));
    }
  }

  /// Saldo inicial: monto e instante SIEMPRE juntos. Un monto sin instante se
  /// ignora en los cálculos (ver [SettingOpening.opening]).
  Future<void> setOpeningBalance({required int cents, required DateTime at}) =>
      (update(settings)..where((s) => s.id.equals(1))).write(SettingsCompanion(
        openingBalanceCents: Value(cents),
        openingBalanceAt: Value(at.millisecondsSinceEpoch),
      ));

  Stream<Setting?> watchSettings() => (select(settings)..where((s) => s.id.equals(1))).watchSingleOrNull();

  /// Categorías (gasto) o fuentes (ingreso) no archivadas, en su orden.
  Future<List<PickOption>> activeOptions(EntryKind kind) async {
    if (kind == EntryKind.expense) {
      final rows = await (select(categories)
            ..where((c) => c.archived.equals(false))
            ..orderBy([(c) => OrderingTerm(expression: c.sortOrder)]))
          .get();
      return [for (final r in rows) (id: r.id, name: r.name, icon: r.icon)];
    }
    final rows = await (select(sources)
          ..where((s) => s.archived.equals(false))
          ..orderBy([(s) => OrderingTerm(expression: s.sortOrder)]))
        .get();
    return [for (final r in rows) (id: r.id, name: r.name, icon: r.icon)];
  }

  /// Categoría/fuente del último movimiento de ese tipo (por created_at).
  Future<String?> lastUsedPick(EntryKind kind) async {
    final e = await (select(entries)
          ..where((e) => e.kind.equalsValue(kind))
          ..orderBy([(e) => OrderingTerm.desc(e.createdAt)])
          ..limit(1))
        .getSingleOrNull();
    return kind == EntryKind.expense ? e?.categoryId : e?.sourceId;
  }

  /// DELETE real (Deshacer del Home): sin borrado lógico.
  Future<int> deleteEntry(String id) => (delete(entries)..where((e) => e.id.equals(id))).go();

  /// Registro manual. [pickId] es category_id o source_id según [kind].
  Future<Entry> insertManualEntry({
    required String id,
    required EntryKind kind,
    required int amountCents,
    required DateTime day,
    required String pickId,
    String? note,
    required DateTime now,
  }) {
    final ms = now.millisecondsSinceEpoch;
    return into(entries).insertReturning(EntriesCompanion.insert(
      id: id,
      kind: kind,
      amountCents: amountCents,
      occurredOn: isoDay(day),
      categoryId: Value(kind == EntryKind.expense ? pickId : null),
      sourceId: Value(kind == EntryKind.income ? pickId : null),
      note: Value(note),
      origin: const Value(Origin.manual),
      createdAt: ms,
      updatedAt: ms,
    ));
  }
}

typedef PickOption = ({String id, String name, String icon});
typedef CatalogItem = ({String id, String name, String icon, bool archived});

/// Color de los ítems creados por el usuario hasta que 1c defina la paleta.
const newItemColor = '#525252';

/// 'YYYY-MM-DD' ↔ día del dominio.
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime parseIsoDay(String s) => day(int.parse(s.substring(0, 4)), int.parse(s.substring(5, 7)), int.parse(s.substring(8, 10)));

extension EntryToMovement on Entry {
  Movement toMovement() => Movement(
        id: id,
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
