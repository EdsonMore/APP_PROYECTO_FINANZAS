import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/home/providers.dart';

final today = day(2026, 10, 8);
const cats = [
  Category(id: 'comida', name: 'Comida', icon: 'restaurant', colorHex: '#000', sortOrder: 0, archived: false, isDefault: true),
  Category(id: 'ocio', name: 'Ocio', icon: 'movie', colorHex: '#000', sortOrder: 1, archived: false, isDefault: true),
];
const srcs = [
  Source(id: 'chamba', name: 'Chamba', icon: 'payments', colorHex: '#000', sortOrder: 0, archived: false, isDefault: true),
];
var _n = 0;

Entry e(EntryKind kind, int soles, DateTime d, {String? cat, String? src, String? note, Origin origin = Origin.manual}) {
  _n++;
  return Entry(
    id: 'e$_n',
    kind: kind,
    amountCents: soles * 100,
    occurredOn: isoDay(d),
    categoryId: kind == EntryKind.expense ? (cat ?? 'comida') : null,
    sourceId: kind == EntryKind.income ? (src ?? 'chamba') : null,
    note: note,
    origin: origin,
    createdAt: _n,
    updatedAt: _n,
  );
}

Setting settings(Mode mode, {String? name}) =>
    Setting(id: 1, mode: mode, spaceName: name, runwayWindowDays: 14, incomeWindowDays: 30, onboardingDone: true);

DateTime ago(int n) => today.subtract(Duration(days: n));

HomeSummary build(Mode mode, List<Entry> entries, {List<Budget> budgets = const [], String? name}) => buildHomeSummary(
    settings: settings(mode, name: name), entries: entries, categories: cats, sources: srcs, budgets: budgets, today: today);

void main() {
  setUpAll(() => initializeDateFormatting('es_PE'));

  test('sin datos → bienvenida, título por defecto, bloques vacíos', () {
    final s = build(Mode.stable, const []);
    expect(s.title, 'Mis cuentas');
    expect(s.headline.kind, HeadlineKind.welcome);
    expect(s.headline.value, 'Empecemos');
    expect(s.light.text, 'Aún sin movimientos');
    expect(s.light.amounts, 'Entró S/ 0.00 · Salió S/ 0.00');
    expect(s.top, isEmpty);
    expect(s.recents, isEmpty);
  });

  test('nombre del espacio', () => expect(build(Mode.stable, const [], name: 'Casa').title, 'Casa'));

  group('Estable', () {
    const budgets = [Budget(categoryId: 'comida', capCents: 50000), Budget(categoryId: 'ocio', capCents: 30000)];

    test('con techos e ingreso en el mes → "Te queda" + porcentaje', () {
      final s = build(Mode.stable, [e(EntryKind.income, 1000, day(2026, 10, 1)), e(EntryKind.expense, 160, ago(1))],
          budgets: budgets);
      expect(s.headline.kind, HeadlineKind.budget);
      expect(s.headline.lead, 'Te queda');
      expect(s.headline.value, 'S/ 640.00');
      expect(s.headline.secondary, 'del presupuesto de octubre');
      expect(s.headline.budgetPercent, 20);
      expect(s.headline.overBudget, isFalse);
    });

    test('pasado del techo → "Te pasaste por" con el exceso', () {
      final s = build(Mode.stable, [e(EntryKind.income, 1000, day(2026, 10, 1)), e(EntryKind.expense, 920, ago(1))],
          budgets: budgets);
      expect(s.headline.lead, 'Te pasaste por');
      expect(s.headline.value, 'S/ 120.00');
      expect(s.headline.overBudget, isTrue);
      expect(s.headline.budgetPercent, 115);
    });

    test('con techos pero sin ingreso en el mes → cae a "Gastaste" (regla F)', () {
      final s = build(Mode.stable, [e(EntryKind.income, 1000, day(2026, 9, 20)), e(EntryKind.expense, 160, ago(1))],
          budgets: budgets);
      expect(s.headline.kind, HeadlineKind.spent);
      expect(s.headline.lead, 'Gastaste');
      expect(s.headline.value, 'S/ 160.00');
    });

    test('sin techos → "Gastaste S/ X" + "en octubre. Te alcanza para…"', () {
      final s = build(Mode.stable, [
        e(EntryKind.income, 1000, ago(13)),
        for (var i = 0; i < 14; i++) e(EntryKind.expense, 10, ago(i)),
      ]);
      expect(s.headline.kind, HeadlineKind.spent);
      expect(s.headline.value, 'S/ 80.00'); // 8 días de octubre × S/ 10
      expect(s.headline.secondary, 'en octubre. Te alcanza para ~86 días.');
    });
  });

  group('Variable y Supervivencia', () {
    List<Entry> data() => [
          e(EntryKind.income, 1000, ago(13)),
          for (var i = 0; i < 14; i++) e(EntryKind.expense, 10, ago(i)),
        ];

    test('Variable → "Te alcanza para ~86 días" + ingreso típico y gasto 30d', () {
      final s = build(Mode.variable, data());
      expect(s.headline.lead, 'Te alcanza para');
      expect(s.headline.value, '~86 días');
      expect(s.headline.stats.map((x) => x.label), ['Ingreso típico 30d', 'Gasto 30d']);
      expect(s.headline.stats.map((x) => x.amount), ['S/ 2,142.86', 'S/ 300.00']);
    });

    test('Supervivencia → "Gastas ~S/ 10.00 al día."', () {
      final s = build(Mode.survival, data());
      expect(s.headline.value, '~86 días');
      expect(s.headline.secondary, 'Gastas ~S/ 10.00 al día.');
      expect(s.headline.stats, isEmpty);
    });

    test('balance ≤ 0 → "Sin colchón"', () {
      final s = build(Mode.survival, [e(EntryKind.expense, 50, ago(1))]);
      expect(s.headline.value, 'Sin colchón');
      expect(s.headline.lead, isNull);
    });

    test('runway > 999 → "+999 días"', () {
      final s = build(Mode.variable, [e(EntryKind.income, 100000, ago(13)), e(EntryKind.expense, 1, ago(0))]);
      expect(s.headline.value, '+999 días');
    });

    test('plural y singular de días', () {
      final many = build(Mode.survival, [
        e(EntryKind.income, 30, ago(13)),
        for (var i = 0; i < 14; i++) e(EntryKind.expense, 1, ago(i)),
      ]);
      expect(many.headline.value, '~16 días');
      final one = build(Mode.survival, [e(EntryKind.income, 151, ago(13)), e(EntryKind.expense, 140, ago(0))]);
      expect(one.headline.value, '~1 día');
    });

    test('pocos días de datos → "Estimado"', () {
      final s = build(Mode.survival, [e(EntryKind.income, 100, ago(2)), e(EntryKind.expense, 10, ago(0))]);
      expect(s.headline.secondary, contains('Estimado con pocos días de datos.'));
    });
  });

  test('semáforo: los textos aprobados (opción A)', () {
    expect(build(Mode.variable, [e(EntryKind.income, 100, ago(1))]).light.text, 'Entra más que sale');
    expect(build(Mode.variable, [e(EntryKind.income, 80, ago(1)), e(EntryKind.expense, 100, ago(1))]).light.text,
        'Sale un poco más');
    expect(build(Mode.variable, [e(EntryKind.expense, 100, ago(1))]).light.text, 'Sale más que entra');
  });

  test('top 3: montos y fracción relativa a la primera', () {
    final s = build(Mode.variable, [e(EntryKind.expense, 200, ago(1)), e(EntryKind.expense, 50, ago(2), cat: 'ocio')]);
    expect(s.top.map((t) => t.name), ['Comida', 'Ocio']);
    expect(s.top.map((t) => t.amount), ['S/ 200.00', 'S/ 50.00']);
    expect(s.top.map((t) => t.fraction), [1.0, 0.25]);
  });

  test('recientes: signo, fecha corta, nota, nombre y Auto', () {
    final s = build(Mode.variable, [
      e(EntryKind.expense, 12, ago(0), note: 'Menú del día'),
      e(EntryKind.income, 80, ago(1)),
      e(EntryKind.expense, 45, ago(2), cat: 'ocio', origin: Origin.auto),
    ]);
    expect(s.recents.map((r) => r.amount), ['− S/ 12.00', '+ S/ 80.00', '− S/ 45.00']);
    expect(s.recents.map((r) => r.subtitle), ['hoy · Menú del día', 'ayer', '6 oct']);
    expect(s.recents.map((r) => r.name), ['Comida', 'Chamba', 'Ocio']);
    expect(s.recents.map((r) => r.isAuto), [false, false, true]);
    expect(s.recents[1].isIncome, isTrue);
  });
}
