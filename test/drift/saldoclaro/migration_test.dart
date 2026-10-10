// ignore_for_file: unused_local_variable, unused_import
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift_dev/api/migrations_native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/data/database.steps.dart';
import 'package:saldo_claro/domain/metrics.dart' show EntryKind;

import 'generated/schema.dart';
import 'generated/schema_v1.dart' as v1;
import 'generated/schema_v2.dart' as v2;
import 'generated/schema_v3.dart' as v3;

/// La semilla tal como la creaba la v1 ("otros" con la bolsa de compras).
const v1Categories = [
  ('comida', 'Comida', 'restaurant'),
  ('transporte', 'Transporte', 'directions_bus'),
  ('vivienda', 'Vivienda', 'home'),
  ('ocio', 'Ocio', 'movie'),
  ('salud', 'Salud', 'healing'),
  ('otros', 'Otros', 'local_mall'),
];
const v1Sources = [('chamba', 'Chamba'), ('venta', 'Venta'), ('familiar', 'Familiar'), ('prestamo', 'Préstamo'), ('otro', 'Otro')];

late SchemaVerifier verifier;

/// Base v1 real (esquema v1 guardado) con la semilla v1 y lo que agregue [fill].
Future<InitializedSchema> v1Database([Future<void> Function(v1.DatabaseAtV1 db)? fill]) async {
  final schema = await verifier.schemaAt(1);
  final old = v1.DatabaseAtV1(schema.newConnection());
  for (final (i, (id, name, icon)) in v1Categories.indexed) {
    await old.into(old.categories).insert(v1.CategoriesCompanion.insert(
        id: id, name: name, icon: icon, colorHex: '#525252', sortOrder: i, isDefault: const Value(1)));
  }
  for (final (i, (id, name)) in v1Sources.indexed) {
    await old.into(old.sources).insert(v1.SourcesCompanion.insert(
        id: id, name: name, icon: 'payments', colorHex: '#525252', sortOrder: i, isDefault: const Value(1)));
  }
  if (fill != null) await fill(old);
  await old.close();
  return schema;
}

/// Abre la base con la app (corre la migración hasta la última versión) y
/// valida que el esquema resultante sea idéntico al de una instalación nueva.
Future<AppDatabase> migrate(InitializedSchema schema) async {
  final db = AppDatabase(schema.newConnection());
  await verifier.migrateAndValidate(db, 3);
  return db;
}

/// Base v2 real con la semilla tal como la creaba la v2 (hex provisionales),
/// fuentes, y lo que agregue [fill].
Future<InitializedSchema> v2Database([Future<void> Function(v2.DatabaseAtV2 db)? fill]) async {
  const v2Hex = ['#C2410C', '#1D4ED8', '#047857', '#7C3AED', '#BE123C', '#525252'];
  final schema = await verifier.schemaAt(2);
  final old = v2.DatabaseAtV2(schema.newConnection());
  for (final (i, (id, name, icon)) in v1Categories.indexed) {
    await old.into(old.categories).insert(v2.CategoriesCompanion.insert(
        id: id, name: name, icon: icon == 'local_mall' ? 'category' : icon, colorHex: v2Hex[i], sortOrder: i,
        isDefault: const Value(1)));
  }
  for (final (i, (id, name)) in v1Sources.indexed) {
    await old.into(old.sources).insert(v2.SourcesCompanion.insert(
        id: id, name: name, icon: 'payments', colorHex: '#047857', sortOrder: i, isDefault: const Value(1)));
  }
  if (fill != null) await fill(old);
  await old.close();
  return schema;
}

Future<Map<String, String>> colors(AppDatabase db) async =>
    {for (final c in await db.select(db.categories).get()) c.id: c.colorHex};

const seedSlots = {
  'comida': 'cat:1', 'transporte': 'cat:2', 'vivienda': 'cat:3', 'ocio': 'cat:4', 'salud': 'cat:5', 'otros': 'cat:6',
};

Future<String> iconOf(AppDatabase db, String id) async =>
    (await (db.select(db.categories)..where((c) => c.id.equals(id))).getSingle()).icon;

/// Falla a mitad de la v2 (después de crear `accounts`): para probar el rollback.
class FailingMidMigration extends AppDatabase {
  FailingMidMigration(super.e);

  @override
  Future<void> migrateV1ToV2(Migrator m, Schema2 schema) async {
    await m.createTable(schema.accounts);
    throw StateError('falla simulada a mitad de la migración');
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() => verifier = SchemaVerifier(GeneratedHelper()));

  for (final from in [1, 2]) {
    test('v$from → v3 sin datos: el esquema migrado es idéntico al de una instalación nueva', () async {
      final schema = await verifier.schemaAt(from);
      final db = AppDatabase(schema.newConnection());
      await verifier.migrateAndValidate(db, 3);
      await db.close();
    });
  }

  group('v2 → v3 (solo datos: slots de la paleta)', () {
    test('semilla → cat:1…6 sin condición; personalizadas → 7, 8, 9, 1 por sort_order; fuentes intactas', () async {
      final schema = await v2Database((old) async {
        // Orden de inserción distinto al sort_order a propósito; una archivada,
        // una con el neutro, una con un hex cualquiera.
        Future<void> cat(String id, int order, String hex, {bool archived = false}) =>
            old.into(old.categories).insert(v2.CategoriesCompanion.insert(
                id: id, name: id, icon: 'category', colorHex: hex, sortOrder: order, archived: Value(archived ? 1 : 0)));
        await cat('deudas', 9, '#525252');
        await cat('ropa', 6, '#FF0000');
        await cat('mascota', 7, '#525252', archived: true);
        await cat('regalos', 8, '#525252');
        // La semilla renombrada/archivada recibe igual su slot.
        await (old.update(old.categories)..where((c) => c.id.equals('salud')))
            .write(const v2.CategoriesCompanion(name: Value('Farmacia'), archived: Value(1)));
        await old.into(old.entries).insert(v2.EntriesCompanion.insert(
            id: 'e1', kind: 'expense', amountCents: 1250, occurredOn: '2026-10-08', categoryId: const Value('ropa'),
            createdAt: 1, updatedAt: 1));
        await old.into(old.budgets).insert(v2.BudgetsCompanion.insert(categoryId: 'comida', capCents: 60000));
      });

      final db = await migrate(schema);

      expect(await colors(db), {
        ...seedSlots,
        'ropa': 'cat:7', 'mascota': 'cat:8', 'regalos': 'cat:9', 'deudas': 'cat:1',
      });
      final salud = await (db.select(db.categories)..where((c) => c.id.equals('salud'))).getSingle();
      expect((salud.name, salud.archived), ('Farmacia', true), reason: 'solo cambia color_hex');
      expect((await db.select(db.sources).get()).map((s) => s.colorHex), everyElement('#047857'), reason: 'fuentes intactas');
      expect((await db.select(db.entries).getSingle()).categoryId, 'ropa');
      expect((await db.select(db.budgets).getSingle()).capCents, 60000);
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      await db.close();
    });

    test('después de migrar, addCatalogItem sigue la cuenta (k = personalizadas existentes)', () async {
      final db = await migrate(await v2Database((old) async {
        for (final (i, id) in ['a', 'b', 'c'].indexed) {
          await old.into(old.categories).insert(
              v2.CategoriesCompanion.insert(id: id, name: id, icon: 'category', colorHex: '#525252', sortOrder: 6 + i));
        }
      }));
      await db.addCatalogItem(EntryKind.expense, id: 'd', name: 'd', icon: 'category');
      expect((await colors(db))['d'], 'cat:1', reason: 'la cuarta personalizada vuelve al slot 1');
      await db.close();
    });
  });

  test('v1 → v3 de corrido: ícono de "otros" corregido y slots asignados', () async {
    final db = await migrate(await v1Database((old) => old.into(old.categories).insert(
        v1.CategoriesCompanion.insert(id: 'ropa', name: 'Ropa', icon: 'local_mall', colorHex: '#525252', sortOrder: 6))));
    expect(await iconOf(db, 'otros'), 'category');
    expect(await colors(db), {...seedSlots, 'ropa': 'cat:7'});
    expect(await db.select(db.accounts).get(), isEmpty);
    await db.close();
  });

  group('v1 → v2 con datos', () {
    test('no se pierde nada; account_id null; accounts vacía; foreign_key_check limpio (casos 1–3, 12)', () async {
      final schema = await v1Database((old) async {
        await old.into(old.entries).insert(v1.EntriesCompanion.insert(
            id: 'e1',
            kind: 'expense',
            amountCents: 1250,
            occurredOn: '2026-10-08',
            categoryId: const Value('comida'),
            note: const Value('Menú del día'),
            accountLabel: const Value('Yape'),
            createdAt: 1000,
            updatedAt: 1000));
        await old.into(old.entries).insert(v1.EntriesCompanion.insert(
            id: 'e2',
            kind: 'income',
            amountCents: 80000,
            occurredOn: '2025-12-31',
            sourceId: const Value('chamba'),
            origin: const Value('auto'),
            createdAt: 500,
            updatedAt: 700));
        await old.into(old.settings).insert(v1.SettingsCompanion.insert(
            id: const Value(1),
            mode: 'survival',
            spaceName: const Value('Casa 🏠'),
            runwayWindowDays: const Value(21),
            openingBalanceCents: const Value(110000),
            openingBalanceAt: const Value(900),
            onboardingDone: const Value(1)));
        await old.into(old.budgets).insert(v1.BudgetsCompanion.insert(categoryId: 'comida', capCents: 60000));
        await old.into(old.goals).insert(v1.GoalsCompanion.insert(id: 'g1', kind: 'cushion', value: 50000, createdAt: 1));
      });

      final db = await migrate(schema);

      final entries = {for (final e in await db.select(db.entries).get()) e.id: e};
      expect(entries, hasLength(2));
      final e1 = entries['e1']!;
      expect((e1.kind.name, e1.amountCents, e1.occurredOn, e1.categoryId, e1.sourceId, e1.note, e1.origin.name),
          ('expense', 1250, '2026-10-08', 'comida', null, 'Menú del día', 'manual'));
      expect((e1.accountLabel, e1.createdAt, e1.updatedAt), ('Yape', 1000, 1000));
      final e2 = entries['e2']!;
      expect((e2.kind.name, e2.amountCents, e2.occurredOn, e2.sourceId, e2.origin.name, e2.createdAt, e2.updatedAt),
          ('income', 80000, '2025-12-31', 'chamba', 'auto', 500, 700));
      expect(entries.values.map((e) => e.accountId), everyElement(isNull), reason: 'account_id null en todas');

      final s = await db.select(db.settings).getSingle();
      expect((s.mode.name, s.spaceName, s.runwayWindowDays, s.incomeWindowDays, s.openingBalanceCents, s.openingBalanceAt,
              s.onboardingDone),
          ('survival', 'Casa 🏠', 21, 30, 110000, 900, true));
      expect((await db.select(db.budgets).getSingle()).capCents, 60000);
      expect((await db.select(db.goals).getSingle()).value, 50000);

      final cats = await db.select(db.categories).get();
      expect(cats.map((c) => c.id), v1Categories.map((c) => c.$1));
      for (final (id, name, icon) in v1Categories.where((c) => c.$1 != 'otros')) {
        final c = cats.firstWhere((c) => c.id == id);
        expect((c.name, c.icon), (name, icon), reason: '$id intacta');
      }
      expect(await db.select(db.sources).get(), hasLength(5));

      expect(await db.select(db.accounts).get(), isEmpty, reason: 'accounts existe y está vacía');
      expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
      await db.close();
    });

    test('"otros" con la bolsa original → category (caso 4)', () async {
      final db = await migrate(await v1Database());
      expect(await iconOf(db, 'otros'), 'category');
      await db.close();
    });

    test('"otros" personalizada → no se toca (caso 5)', () async {
      final db = await migrate(await v1Database((old) => (old.update(old.categories)..where((c) => c.id.equals('otros')))
          .write(const v1.CategoriesCompanion(icon: Value('redeem')))));
      expect(await iconOf(db, 'otros'), 'redeem');
      await db.close();
    });

    test('categoría del usuario con la bolsa → no se toca: la regla es por id (caso 6)', () async {
      final db = await migrate(await v1Database((old) => old.into(old.categories).insert(
          v1.CategoriesCompanion.insert(id: 'ropa', name: 'Ropa', icon: 'local_mall', colorHex: '#525252', sortOrder: 6))));
      expect(await iconOf(db, 'ropa'), 'local_mall');
      expect(await iconOf(db, 'otros'), 'category');
      await db.close();
    });

    test('"otros" renombrada con la bolsa → ícono corregido, nombre intacto (caso 7)', () async {
      final db = await migrate(await v1Database((old) => (old.update(old.categories)..where((c) => c.id.equals('otros')))
          .write(const v1.CategoriesCompanion(name: Value('Varios')))));
      final c = await (db.select(db.categories)..where((c) => c.id.equals('otros'))).getSingle();
      expect((c.name, c.icon), ('Varios', 'category'));
      await db.close();
    });

    test('"otros" archivada con la bolsa → ícono corregido, sigue archivada (caso 8)', () async {
      final db = await migrate(await v1Database((old) => (old.update(old.categories)..where((c) => c.id.equals('otros')))
          .write(const v1.CategoriesCompanion(archived: Value(1)))));
      final c = await (db.select(db.categories)..where((c) => c.id.equals('otros'))).getSingle();
      expect((c.icon, c.archived), ('category', true));
      await db.close();
    });

    test('base v1 recién instalada (solo semilla): migra sin fallar (caso 9)', () async {
      final db = await migrate(await v1Database());
      expect(await db.select(db.entries).get(), isEmpty);
      expect(await db.select(db.categories).get(), hasLength(6));
      expect(await db.select(db.accounts).get(), isEmpty);
      await db.close();
    });
  });

  test('la FK de account_id funciona después de migrar (caso 11)', () async {
    final db = await migrate(await v1Database());
    Future<void> insert(String id, String? accountId) => db.into(db.entries).insert(EntriesCompanion.insert(
        id: id,
        kind: EntryKind.expense,
        amountCents: 100,
        occurredOn: '2026-10-08',
        categoryId: const Value('comida'),
        accountId: Value(accountId),
        createdAt: 1,
        updatedAt: 1));

    await expectLater(insert('x', 'no-existe'), throwsA(isA<Exception>()), reason: 'cuenta inexistente');
    await db.into(db.accounts).insert(AccountsCompanion.insert(
        id: 'yape', name: 'Yape', icon: 'phone_android', colorHex: '#525252', sortOrder: 0, createdAt: 1));
    await insert('y', 'yape');
    await (db.delete(db.accounts)..where((a) => a.id.equals('yape'))).go();
    final e = await (db.select(db.entries)..where((e) => e.id.equals('y'))).getSingle();
    expect(e.accountId, isNull, reason: 'ON DELETE SET NULL: el movimiento se conserva');
    await db.close();
  });

  test('si la migración falla a mitad, todo vuelve a v1 y se puede reintentar (transacción)', () async {
    final schema = await v1Database((old) => old.into(old.entries).insert(v1.EntriesCompanion.insert(
        id: 'e1', kind: 'expense', amountCents: 1250, occurredOn: '2026-10-08', categoryId: const Value('comida'),
        createdAt: 1, updatedAt: 1)));

    final failing = FailingMidMigration(schema.newConnection());
    await expectLater(failing.customSelect('SELECT 1').get(), throwsStateError);
    await failing.close();

    final raw = schema.rawDatabase;
    expect(raw.userVersion, 1, reason: 'la versión no subió');
    expect(raw.select("SELECT name FROM sqlite_master WHERE name = 'accounts'"), isEmpty, reason: 'CREATE TABLE revertido');
    expect(raw.select('PRAGMA table_info(entries)').map((r) => r['name']), isNot(contains('account_id')));
    expect(raw.select("SELECT icon FROM categories WHERE id = 'otros'").single['icon'], 'local_mall');
    expect(raw.select('SELECT COUNT(*) AS n FROM entries').single['n'], 1);

    // Con la app correcta, la misma base migra bien.
    final db = await migrate(schema);
    expect(await iconOf(db, 'otros'), 'category');
    expect(await db.select(db.entries).get(), hasLength(1));
    await db.close();
  });
}
