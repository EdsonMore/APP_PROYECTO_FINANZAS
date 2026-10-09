import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/entry/draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simula cerrar y reabrir la app: descarta la instancia en memoria y vuelve a
/// leer del almacenamiento (el mock de plataforma conserva lo escrito).
Future<DraftStore> reopenApp() async {
  SharedPreferences.resetStatic();
  return DraftStore(await SharedPreferences.getInstance());
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('sobrevive a cerrar y reabrir la app', () async {
    final before = DraftStore(await SharedPreferences.getInstance());
    await before.save(EntryKind.expense,
        Draft(amountText: '12.5', pickId: 'transporte', day: day(2026, 10, 6), note: 'combi'));

    final after = await reopenApp();
    final d = after.load(EntryKind.expense)!;
    expect(d.amountText, '12.5');
    expect(d.pickId, 'transporte');
    expect(d.day, day(2026, 10, 6));
    expect(d.note, 'combi');
  });

  test('un borrador por tipo', () async {
    final s = DraftStore(await SharedPreferences.getInstance());
    await s.save(EntryKind.expense, const Draft(amountText: '5'));
    await s.save(EntryKind.income, const Draft(amountText: '900'));
    final after = await reopenApp();
    expect(after.load(EntryKind.expense)!.amountText, '5');
    expect(after.load(EntryKind.income)!.amountText, '900');
  });

  test('"hoy" se guarda como null', () async {
    final s = DraftStore(await SharedPreferences.getInstance());
    await s.save(EntryKind.expense, const Draft(amountText: '5'));
    expect((await reopenApp()).load(EntryKind.expense)!.day, isNull);
  });

  test('borrador vacío borra el guardado', () async {
    final s = DraftStore(await SharedPreferences.getInstance());
    await s.save(EntryKind.expense, const Draft(amountText: '5'));
    await s.save(EntryKind.expense, const Draft(pickId: 'ocio'));
    expect((await reopenApp()).has(EntryKind.expense), isFalse);
  });

  test('clear lo elimina', () async {
    final s = DraftStore(await SharedPreferences.getInstance());
    await s.save(EntryKind.income, const Draft(amountText: '1'));
    await s.clear(EntryKind.income);
    expect((await reopenApp()).load(EntryKind.income), isNull);
  });

  test('JSON corrupto → null, no crash', () async {
    SharedPreferences.setMockInitialValues({'draft.expense': '{no es json'});
    final s = await reopenApp();
    expect(s.load(EntryKind.expense), isNull);
  });

  test('JSON con tipos inesperados → null, no crash', () async {
    SharedPreferences.setMockInitialValues({'draft.expense': '{"amount": 12}'});
    final s = await reopenApp();
    expect(s.load(EntryKind.expense), isNull);
  });
}
