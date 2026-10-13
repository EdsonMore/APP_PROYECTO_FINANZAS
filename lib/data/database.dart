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

/// Columnas de sync (Fase 3, SPEC §Sync). updated_at: epoch ms del último
/// cambio local, siempre creciente (ver [AppDatabase.bumped]); 0 solo como
/// default técnico de SQLite al agregar la columna, ninguna fila queda así.
/// synced_at: updated_at de la última versión subida o bajada; NULL = nunca.
/// Pendiente de subir = synced_at IS NULL OR synced_at < updated_at.
mixin _Synced on Table {
  IntColumn get updatedAt => integer().withDefault(const Constant(0))();
  IntColumn get syncedAt => integer().nullable()();
}

class Categories extends Table with _Catalog, _Synced {}

class Sources extends Table with _Catalog, _Synced {}

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

  /// Ver [_Synced] (entries ya tenía updated_at desde la v1).
  IntColumn get syncedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
        "CHECK ((kind = 'expense' AND category_id IS NOT NULL AND source_id IS NULL) "
            "OR (kind = 'income' AND source_id IS NOT NULL AND category_id IS NULL))",
      ];
}

/// Una sola fila (id = 1), creada al terminar el onboarding.
class Settings extends Table with _Synced {
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
class Budgets extends Table with _Synced {
  TextColumn get categoryId => text().references(Categories, #id)();
  IntColumn get capCents => integer().check(capCents.isBiggerThanValue(0))();

  @override
  Set<Column> get primaryKey => {categoryId};
}

/// Borrados que faltan subir (Fase 3). Solo se anota lo que llegó a
/// sincronizarse: lo que nunca salió del teléfono no existe en el servidor.
/// Al subirse, la lápida se elimina. Las filas se borran de verdad en local,
/// así que ninguna consulta de la app tiene que filtrar borrados.
class Tombstones extends Table {
  /// Tabla de la fila borrada: 'entries' o 'budgets' (lo único que la app
  /// borra; lo demás se archiva). No se llama table_name: choca con
  /// Table.tableName en el código que genera drift.
  TextColumn get entity => text().check(entity.isIn(const ['entries', 'budgets']))();

  /// id del movimiento, o category_id del techo.
  TextColumn get recordId => text().named('row_id')();
  IntColumn get deletedAt => integer()();

  @override
  Set<Column> get primaryKey => {entity, recordId};
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
// id, nombre, icono (IconCatalog), slot de la paleta categórica (tokens.dart).
const defaultCategories = [
  ('comida', 'Comida', 'restaurant', 'cat:1'),
  ('transporte', 'Transporte', 'directions_bus', 'cat:2'),
  ('vivienda', 'Vivienda', 'home', 'cat:3'),
  ('ocio', 'Ocio', 'movie', 'cat:4'),
  ('salud', 'Salud', 'healing', 'cat:5'),
  ('otros', 'Otros', 'category', 'cat:6'),
];

const defaultSources = [
  ('chamba', 'Chamba', 'payments', '#047857'),
  ('venta', 'Venta', 'shopping_cart', '#1D4ED8'),
  ('familiar', 'Familiar', 'favorite', '#BE123C'),
  ('prestamo', 'Préstamo', 'account_balance', '#B45309'),
  ('otro', 'Otro', 'redeem', '#525252'),
];

@DriftDatabase(tables: [Categories, Sources, Entries, Settings, Budgets, Goals, Accounts, Tombstones])
class AppDatabase extends _$AppDatabase {
  /// [clock]: epoch ms "ahora". Inyectable para tests; por defecto, la hora real.
  AppDatabase([QueryExecutor? executor, int Function()? clock])
      : _now = clock ?? _systemNow,
        super(executor ?? driftDatabase(name: 'saldoclaro'));

  final int Function() _now;
  static int _systemNow() => DateTime.now().millisecondsSinceEpoch;

  /// [values] más updated_at = MAX(ahora, updated_at + 1): siempre crece,
  /// aunque el reloj quede quieto (dos cambios en el mismo ms) o retroceda.
  /// Si no creciera, un cambio hecho justo después de sincronizar quedaría
  /// marcado como ya subido. Para UPDATE y para el DO UPDATE de un upsert
  /// (ahí updated_at es el valor de la fila existente).
  @visibleForTesting
  Insertable<D> bumped<D>(Insertable<D> values) => RawValuesInsertable<D>({
        ...values.toColumns(false),
        'updated_at': CustomExpression<int>('MAX(${_now()}, updated_at + 1)'),
      });

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          final now = _now();
          await batch((b) {
            for (final (i, (id, name, icon, color)) in defaultCategories.indexed) {
              b.insert(categories, CategoriesCompanion.insert(
                  id: id, name: name, icon: icon, colorHex: color, sortOrder: i, isDefault: const Value(true),
                  updatedAt: Value(now)));
            }
            for (final (i, (id, name, icon, color)) in defaultSources.indexed) {
              b.insert(sources, SourcesCompanion.insert(
                  id: id, name: name, icon: icon, colorHex: color, sortOrder: i, isDefault: const Value(true),
                  updatedAt: Value(now)));
            }
          });
        },
        onUpgrade: (m, from, to) async {
          // Una transacción: si un paso falla, la base vuelve entera a la
          // versión anterior (drift no envuelve la migración por su cuenta y
          // solo sube user_version si todo termina bien).
          await transaction(() => stepByStep(from1To2: migrateV1ToV2, from2To3: migrateV2ToV3, from3To4: migrateV3ToV4)(m, from, to));
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

  /// v2 → v3, solo datos: cada categoría recibe su slot de la paleta en
  /// `color_hex`. La semilla se sobrescribe sin condición (sus hex eran
  /// provisionales y nunca se mostraron); las del usuario, archivadas
  /// incluidas, toman slots por `sort_order` con [customCategorySlot].
  /// Las fuentes no se tocan.
  @visibleForTesting
  Future<void> migrateV2ToV3(Migrator m, Schema3 schema) async {
    for (final (id, _, _, slot) in defaultCategories) {
      await customUpdate('UPDATE categories SET color_hex = ? WHERE id = ?',
          variables: [Variable(slot), Variable(id)], updates: {categories});
    }
    final custom = await customSelect('SELECT id FROM categories WHERE is_default = 0 ORDER BY sort_order, id').get();
    for (final (k, row) in custom.indexed) {
      await customUpdate('UPDATE categories SET color_hex = ? WHERE id = ?',
          variables: [Variable(customCategorySlot(k)), Variable(row.read<String>('id'))], updates: {categories});
    }
  }

  /// v3 → v4 (Fase 3E): columnas de sync y tabla de lápidas, con ADD COLUMN
  /// (sin reconstruir tablas). Las filas que ya estaban en el teléfono:
  /// updated_at = la hora de la migración (entries conserva el suyo) y
  /// synced_at = NULL, o sea, todo pendiente: al crear la cuenta (3B) se sube.
  /// Sin lápidas: lo borrado antes de la v4 nunca existió en el servidor.
  @visibleForTesting
  Future<void> migrateV3ToV4(Migrator m, Schema4 schema) async {
    await m.addColumn(schema.categories, schema.categories.updatedAt);
    await m.addColumn(schema.categories, schema.categories.syncedAt);
    await m.addColumn(schema.sources, schema.sources.updatedAt);
    await m.addColumn(schema.sources, schema.sources.syncedAt);
    await m.addColumn(schema.entries, schema.entries.syncedAt);
    await m.addColumn(schema.budgets, schema.budgets.updatedAt);
    await m.addColumn(schema.budgets, schema.budgets.syncedAt);
    await m.addColumn(schema.settings, schema.settings.updatedAt);
    await m.addColumn(schema.settings, schema.settings.syncedAt);
    await m.createTable(schema.tombstones);
    final now = _now();
    for (final t in ['categories', 'sources', 'budgets', 'settings']) {
      await customStatement('UPDATE $t SET updated_at = ?', [now]);
    }
  }

  /// Cierra el onboarding: crea (o reemplaza) la fila única de settings.
  /// Reemplazar no toca el saldo inicial.
  Future<void> completeOnboarding({required Mode mode, String? spaceName}) => transaction(() async {
        final values = SettingsCompanion(
          mode: Value(mode),
          spaceName: Value(spaceName),
          runwayWindowDays: const Value(14),
          incomeWindowDays: const Value(30),
          onboardingDone: const Value(true),
        );
        if (await _updateSettings(values) == 0) {
          await into(settings).insert(values.copyWith(id: const Value(1), updatedAt: Value(_now())));
        }
      });

  Future<int> _updateSettings(SettingsCompanion c) =>
      (update(settings)..where((s) => s.id.equals(1))).write(bumped(c));

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

  /// Nuevo ítem al final del orden. Una categoría toma el siguiente slot de la
  /// paleta ([customCategorySlot]); una fuente, el color neutro.
  Future<void> addCatalogItem(EntryKind kind, {required String id, required String name, required String icon}) async {
    final order = await _nextSortOrder(kind);
    if (kind == EntryKind.expense) {
      final k = await (selectOnly(categories)
            ..addColumns([categories.id.count()])
            ..where(categories.isDefault.equals(false)))
          .map((r) => r.read(categories.id.count())!)
          .getSingle();
      await into(categories).insert(CategoriesCompanion.insert(
          id: id, name: name, icon: icon, colorHex: customCategorySlot(k), sortOrder: order, updatedAt: Value(_now())));
    } else {
      await into(sources).insert(SourcesCompanion.insert(
          id: id, name: name, icon: icon, colorHex: newItemColor, sortOrder: order, updatedAt: Value(_now())));
    }
  }

  Future<void> updateCatalogItem(EntryKind kind, String id, {required String name, required String icon}) =>
      kind == EntryKind.expense
          ? (update(categories)..where((c) => c.id.equals(id)))
              .write(bumped(CategoriesCompanion(name: Value(name), icon: Value(icon))))
          : (update(sources)..where((c) => c.id.equals(id)))
              .write(bumped(SourcesCompanion(name: Value(name), icon: Value(icon))));

  /// Archivar no borra: los movimientos viejos siguen apuntando al ítem.
  /// Reactivar lo manda al final de los activos.
  Future<void> setArchived(EntryKind kind, String id, {required bool archived}) async {
    final order = archived ? null : await _nextSortOrder(kind);
    if (kind == EntryKind.expense) {
      await (update(categories)..where((c) => c.id.equals(id))).write(bumped(CategoriesCompanion(
          archived: Value(archived), sortOrder: order == null ? const Value.absent() : Value(order))));
    } else {
      await (update(sources)..where((c) => c.id.equals(id))).write(bumped(
          SourcesCompanion(archived: Value(archived), sortOrder: order == null ? const Value.absent() : Value(order))));
    }
  }

  /// Techo mensual de una categoría (crea o reemplaza). [cents] > 0: lo exige
  /// el CHECK de la tabla. En la misma transacción borra la lápida de ese
  /// techo si la hay: el techo nuevo le gana a un "Quitar techo" anterior.
  Future<void> setBudget(String categoryId, int cents) => transaction(() async {
        await into(budgets).insert(
          BudgetsCompanion.insert(categoryId: categoryId, capCents: cents, updatedAt: Value(_now())),
          onConflict: DoUpdate((_) => bumped(BudgetsCompanion(capCents: Value(cents)))),
        );
        await (delete(tombstones)
              ..where((t) => t.entity.equals('budgets') & t.recordId.equals(categoryId)))
            .go();
      });

  /// Quitar techo. Si ya se había sincronizado, deja lápida (misma transacción).
  Future<void> removeBudget(String categoryId) => transaction(() async {
        final row = await (select(budgets)..where((b) => b.categoryId.equals(categoryId))).getSingleOrNull();
        await (delete(budgets)..where((b) => b.categoryId.equals(categoryId))).go();
        if (row?.syncedAt != null) await _tombstone('budgets', categoryId);
      });

  Future<void> _tombstone(String table, String id) => into(tombstones)
      .insertOnConflictUpdate(TombstonesCompanion.insert(entity: table, recordId: id, deletedAt: _now()));

  /// Saldo inicial: monto e instante SIEMPRE juntos. Un monto sin instante se
  /// ignora en los cálculos (ver [SettingOpening.opening]).
  Future<void> setOpeningBalance({required int cents, required DateTime at}) => _updateSettings(SettingsCompanion(
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

  /// DELETE real (Deshacer del Home): sin borrado lógico. Si el movimiento ya
  /// se había sincronizado, deja lápida para borrarlo también en el servidor
  /// (misma transacción).
  Future<int> deleteEntry(String id) => transaction(() async {
        final row = await (select(entries)..where((e) => e.id.equals(id))).getSingleOrNull();
        final n = await (delete(entries)..where((e) => e.id.equals(id))).go();
        if (row?.syncedAt != null) await _tombstone('entries', id);
        return n;
      });

  // ---- Sync (Fase 3B): lo que necesita push(). La bajada llega en la 3C.

  /// Tablas que se sincronizan, en el orden de subida (FK del servidor:
  /// catálogos antes que movimientos y techos), con su clave local.
  static const syncTables = {
    'categories': 'id',
    'sources': 'id',
    'settings': 'id',
    'entries': 'id',
    'budgets': 'category_id',
  };

  static String _syncKey(String table) =>
      syncTables[table] ?? (throw ArgumentError.value(table, 'table', 'no se sincroniza'));

  /// Filas pendientes de subir (synced_at NULL o menor que updated_at), tal
  /// como están en SQLite.
  Future<List<Map<String, Object?>>> pendingRows(String table) async {
    final key = _syncKey(table);
    final rows = await customSelect(
            'SELECT * FROM $table WHERE synced_at IS NULL OR synced_at < updated_at ORDER BY $key')
        .get();
    return [for (final r in rows) r.data];
  }

  /// Marca como subidas las filas confirmadas, con el updated_at QUE SE MANDÓ.
  /// Si la fila cambió mientras se subía, su updated_at ya es mayor y sigue
  /// pendiente. Nunca baja un synced_at.
  Future<void> markSynced(String table, List<(Object, int)> sent) async {
    final key = _syncKey(table);
    await transaction(() async {
      for (final (id, updatedAt) in sent) {
        await customUpdate(
          'UPDATE $table SET synced_at = ? WHERE $key = ? AND (synced_at IS NULL OR synced_at < ?)',
          variables: [Variable(updatedAt), Variable(id), Variable(updatedAt)],
        );
      }
    });
  }

  Future<List<Tombstone>> pendingTombstones() =>
      (select(tombstones)..orderBy([(t) => OrderingTerm(expression: t.entity), (t) => OrderingTerm(expression: t.recordId)]))
          .get();

  /// Borra la lápida ya subida, solo si no cambió mientras tanto.
  Future<void> dropTombstone(Tombstone t) => (delete(tombstones)
        ..where((x) => x.entity.equals(t.entity) & x.recordId.equals(t.recordId) & x.deletedAt.equals(t.deletedAt)))
      .go();

  /// Al cerrar sesión o borrar la cuenta: todo vuelve a quedar pendiente y
  /// las lápidas se descartan. Así, si después se entra con OTRA cuenta,
  /// se sube todo (las filas no quedan "sincronizadas" con la anterior).
  Future<void> detachSync() => transaction(() async {
        for (final t in syncTables.keys) {
          await customUpdate('UPDATE $t SET synced_at = NULL');
        }
        await delete(tombstones).go();
      });

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

/// Color de las fuentes creadas por el usuario (las fuentes no usan la paleta).
const newItemColor = '#525252';

/// Slot de la k-ésima categoría del usuario (k desde 0): 7, 8, 9 y luego se
/// reutilizan 1, 2… Con barras rotuladas un color repetido no confunde.
String customCategorySlot(int k) => 'cat:${(k + 6) % 9 + 1}';

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
