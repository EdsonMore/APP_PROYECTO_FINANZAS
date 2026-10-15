import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/core/utils/formatters.dart';
import 'package:saldo_claro/data/database.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/insights/providers.dart';
import 'package:saldo_claro/features/insights/runway_line.dart';

final today = day(2026, 10, 8);
DateTime ago(int n) => today.subtract(Duration(days: n));

Category cat(String id, int slot, {bool archived = false}) => Category(updatedAt: 1, 
    id: id, name: '${id[0].toUpperCase()}${id.substring(1)}', icon: 'category', colorHex: 'cat:$slot',
    sortOrder: slot, archived: archived, isDefault: slot <= 6);

final cats = [
  cat('comida', 1), cat('transporte', 2), cat('vivienda', 3), cat('ocio', 4), cat('salud', 5), cat('otros', 6),
  cat('ropa', 7, archived: true),
];
var _n = 0;

Entry e(EntryKind kind, int soles, DateTime d, {String cat = 'comida'}) {
  _n++;
  return Entry(
    id: 'e$_n',
    kind: kind,
    amountCents: soles * 100,
    occurredOn: isoDay(d),
    categoryId: kind == EntryKind.expense ? cat : null,
    sourceId: kind == EntryKind.income ? 'chamba' : null,
    origin: Origin.manual,
    createdAt: _n,
    updatedAt: _n,
  );
}

InsightsSummary build(Mode mode, List<Entry> entries, {List<Budget> budgets = const []}) => buildInsightsSummary(
    settings: Setting(updatedAt: 1, id: 1, mode: mode, runwayWindowDays: 14, incomeWindowDays: 30, onboardingDone: true),
    entries: entries,
    categories: cats,
    budgets: budgets,
    today: today);

List<Type> types(InsightsSummary s) => [for (final b in s.blocks) b.runtimeType];

/// Datos completos: 2 meses cerrados, 14 días de serie, gasto en varias categorías.
List<Entry> full() => [
      e(EntryKind.income, 900, day(2026, 8, 1)),
      e(EntryKind.income, 600, day(2026, 9, 3)),
      e(EntryKind.income, 1000, ago(13)),
      for (var i = 0; i < 14; i++) e(EntryKind.expense, 10, ago(i)),
      e(EntryKind.expense, 30, ago(2), cat: 'ocio'),
      e(EntryKind.expense, 20, ago(3), cat: 'transporte'),
    ];

void main() {
  setUpAll(() => initializeDateFormatting('es_PE'));

  group('frase principal', () {
    test('Estable E1: techos activos vs todo el gasto del mes', () {
      final s = build(Mode.stable, [e(EntryKind.income, 1000, day(2026, 10, 1)), e(EntryKind.expense, 160, ago(1))],
          budgets: const [
            Budget(updatedAt: 1, categoryId: 'comida', capCents: 50000),
            Budget(updatedAt: 1, categoryId: 'ocio', capCents: 30000),
            Budget(updatedAt: 1, categoryId: 'ropa', capCents: 99900), // archivada: no suma (D2)
          ]);
      expect(s.phrase, 'Llevas S/ 160.00 de S/ 800.00 de tus techos este mes.');
    });

    test('Estable E2 (sin techos): la categoría mayor y su %', () {
      final s = build(Mode.stable, [e(EntryKind.expense, 120, ago(1)), e(EntryKind.expense, 30, ago(2), cat: 'ocio')]);
      expect(s.phrase, 'Comida se llevó el 80 % de lo que gastaste en 30 días.');
    });

    test('Estable E3 (sin techos ni gasto): la racha', () {
      final s = build(Mode.stable, [e(EntryKind.income, 300, ago(5))]);
      expect(s.phrase, 'Vas 6 días sin pasarte de tu límite diario.');
    });

    test('Variable V1: te sobran / te faltan, con avgIncome30 y avgExpense30 (I2)', () {
      expect(build(Mode.variable, [e(EntryKind.income, 3000, ago(29)), e(EntryKind.expense, 2000, ago(29))]).phrase,
          'En un mes típico te sobran ~S/ 1,000.00.');
      expect(build(Mode.variable, [e(EntryKind.income, 1000, ago(29)), e(EntryKind.expense, 1500, ago(29))]).phrase,
          'En un mes típico te faltan ~S/ 500.00.');
    });

    test('Variable V2 (sin ingreso en 30 días): lo que entró y salió', () {
      expect(build(Mode.variable, [e(EntryKind.expense, 80, ago(3))]).phrase,
          'En 30 días entró S/ 0.00 y salió S/ 80.00.');
    });

    test('Variable V3 (nada en 30 días): el mejor mes', () {
      final s = build(Mode.variable, [e(EntryKind.income, 800, day(2026, 8, 1)), e(EntryKind.income, 300, day(2026, 9, 5))]);
      expect(s.phrase, 'Tu mejor mes fue agosto, con S/ 800.00.');
    });

    test('Supervivencia S1: días de runway', () {
      final s = build(Mode.survival, [
        e(EntryKind.income, 1000, ago(13)),
        for (var i = 0; i < 14; i++) e(EntryKind.expense, 10, ago(i)),
      ]);
      expect(s.phrase, 'A este ritmo te alcanza para 86 días.');
    });

    test('Supervivencia S3 (sin gastos en la ventana): la racha con el límite', () {
      final s = build(Mode.survival, [e(EntryKind.income, 500, ago(20)), e(EntryKind.expense, 20, ago(20))]);
      expect(s.phrase, 'Vas 21 días gastando menos de S/ 23.81 al día.');
    });

    test('con datos pero sin reserva ni racha → "Sin reserva por ahora.", nunca la de espera', () {
      final s = build(Mode.survival, [e(EntryKind.income, 50, ago(20)), e(EntryKind.expense, 300, today)]);
      expect(s.phrase, noCushionPhrase);
    });

    test('con datos viejos y nada en 30 días → "Sin movimientos en los últimos 30 días."', () {
      expect(build(Mode.variable, [e(EntryKind.income, 50, ago(45))]).phrase, quietPhrase);
    });

    test('sin datos, en los 3 modos → frase de espera', () {
      for (final m in Mode.values) {
        expect(build(m, const []).phrase, emptyPhrase, reason: m.name);
      }
    });
  });

  group('orden de bloques', () {
    test('Estable', () {
      expect(types(build(Mode.stable, full())),
          [BudgetBlock, SpendBlock, StreakBlock, MonthsBlock, RunwayBlock, ReadingBlock]);
    });

    test('Variable', () {
      expect(types(build(Mode.variable, full())),
          [FlowBlock, MonthsBlock, SpendBlock, RunwayBlock, StreakBlock, ReadingBlock]);
    });

    test('Supervivencia: reserva alto primero, meses al fondo', () {
      final s = build(Mode.survival, full());
      expect(types(s), [RunwayBlock, StreakBlock, SuggestedBlock, SpendBlock, MonthsBlock, ReadingBlock]);
      expect((s.blocks.first as RunwayBlock).tall, isTrue);
    });

    test('sin datos: solo los bloques con texto de espera (y Presupuesto en Estable)', () {
      expect(types(build(Mode.stable, const [])), [BudgetBlock, MonthsBlock, RunwayBlock]);
      expect(types(build(Mode.variable, const [])), [MonthsBlock, RunwayBlock]);
      expect(types(build(Mode.survival, const [])), [RunwayBlock, MonthsBlock]);
    });
  });

  test('mejor y peor mes entre los cerrados completos', () {
    final s = build(Mode.stable, full());
    final m = s.blocks.whereType<MonthsBlock>().single;
    // Septiembre: 600 + 1,000 de hace 13 días (25 de septiembre).
    expect((m.best!.month, m.best!.cents), (DateTime.utc(2026, 9), 160000));
    expect((m.worst!.month, m.worst!.cents), (DateTime.utc(2026, 8), 90000));
    expect(Formatters.month(m.best!.month), 'Septiembre');
  });

  test('gasto: top 5 sin "Otros"; "Otros" real + el resto en una fila final piedra; archivada incluida', () {
    final s = build(Mode.stable, [
      e(EntryKind.expense, 300, ago(1), cat: 'ropa'), // archivada, cuenta (V3)
      e(EntryKind.expense, 250, ago(1), cat: 'otros'), // nunca entre las 5
      e(EntryKind.expense, 200, ago(1)),
      e(EntryKind.expense, 150, ago(1), cat: 'transporte'),
      e(EntryKind.expense, 100, ago(1), cat: 'vivienda'),
      e(EntryKind.expense, 50, ago(1), cat: 'ocio'),
      e(EntryKind.expense, 40, ago(1), cat: 'salud'),
    ]);
    final rows = s.blocks.whereType<SpendBlock>().single.rows;
    expect(rows.map((r) => r.name), ['Ropa', 'Comida', 'Transporte', 'Vivienda', 'Ocio', 'Otros']);
    expect(rows.where((r) => r.name == 'Otros'), hasLength(1));
    expect((rows.last.cents, rows.last.colorHex), (29000, 'cat:6'), reason: '250 de Otros + 40 de Salud');
    expect(rows.first.colorHex, 'cat:7');
    expect(rows.last.fraction, closeTo(290 / 300, 1e-9), reason: 'relativo a la fila mayor');
    expect(rows.map((r) => r.percent).reduce((a, b) => a + b), inInclusiveRange(99, 101));
  });

  test('techos sugeridos: activas sin techo, como mucho 3, de mayor a menor', () {
    final s = build(Mode.survival, [
      e(EntryKind.income, 2000, ago(20)),
      e(EntryKind.expense, 300, ago(5)),
      e(EntryKind.expense, 200, ago(5), cat: 'transporte'),
      e(EntryKind.expense, 100, ago(5), cat: 'ocio'),
      e(EntryKind.expense, 50, ago(5), cat: 'salud'),
      e(EntryKind.expense, 20, ago(5), cat: 'vivienda'), // cuarta candidata: queda fuera
      e(EntryKind.expense, 400, ago(5), cat: 'ropa'), // archivada: no se sugiere
    ], budgets: const [Budget(updatedAt: 1, categoryId: 'comida', capCents: 10000)]);
    final rows = s.blocks.whereType<SuggestedBlock>().single.rows;
    expect(rows.map((r) => r.categoryId), ['transporte', 'ocio', 'salud']);
  });

  test('RunwayLine.segments: cada null corta el trazo', () {
    expect(RunwayLine.segments([5, 4, null, null, 3, null, 2, 1]), [
      [(0, 5), (1, 4)],
      [(4, 3)],
      [(6, 2), (7, 1)],
    ]);
    expect(RunwayLine.segments(const [null, null]), isEmpty);
  });

  group('hallazgos del code-review', () {
    test('3: con umbral 0 no hay racha ni frase S3 ("menos de S/ 0.00")', () {
      // Sin ingreso y sin gastos en la ventana de 14 días: el umbral redondea a 0.
      final s = build(Mode.survival, [e(EntryKind.expense, 20, ago(20))]);
      expect(s.blocks.whereType<StreakBlock>(), isEmpty);
      expect(s.phrase, isNot(contains('S/ 0.00')));
      expect(build(Mode.stable, [e(EntryKind.expense, 20, ago(20))]).phrase, isNot(contains('sin pasarte')));
    });

    test('4: meses cerrados sin ningún ingreso → sin mejor/peor y sin "mejor mes … S/ 0.00"', () {
      final s = build(Mode.variable, [e(EntryKind.expense, 5, day(2026, 6, 1))]);
      expect(s.blocks.whereType<MonthsBlock>(), isEmpty);
      expect(s.phrase, isNot(contains('mejor mes')));
    });

    test('4: si todos los meses empatan, se muestra solo el mejor', () {
      final s = build(Mode.variable, [e(EntryKind.income, 500, day(2026, 8, 1)), e(EntryKind.income, 500, day(2026, 9, 1))]);
      final m = s.blocks.whereType<MonthsBlock>().single;
      expect(m.best!.cents, 50000);
      expect(m.worst, isNull);
    });
  });
}
