import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import 'home_screen_test.dart' as h;

/// Empezó hoy con S/ 300 (saldo fijado ayer) y hoy gastó [spentSoles].
Future<void> Function(h.Seed) day300({int spentSoles = 20}) => (s) async {
      await s.db.setOpeningBalance(cents: 30000, at: DateTime(2026, 10, 7, 9));
      if (spentSoles > 0) await s.expense(spentSoles, h.today);
    };

Finder key(String k) => find.byKey(Key(k));

Future<void> open(WidgetTester tester) async {
  await tester.tap(key('home.allowance'));
  await tester.pumpAndSettle();
}

Future<void> tap(WidgetTester tester, String k) async {
  await tester.tap(key(k));
  await tester.pumpAndSettle();
}

String text(WidgetTester tester, String k) => tester.widget<Text>(key(k)).data!.replaceAll('\u00A0', ' ');

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  for (final mode in Mode.values) {
    testWidgets('el link está bajo el número en modo ${mode.name}', (tester) async {
      await h.pumpHome(tester, await h.seeded(mode, day300()));
      expect(key('home.allowance'), findsOneWidget);
      expect(find.text('¿Cuánto puedo gastar hoy?'), findsOneWidget);
      await h.unmount(tester);
    });
  }

  testWidgets('sin datos (bienvenida): no hay link', (tester) async {
    await h.pumpHome(tester, await h.seeded(Mode.variable));
    expect(key('home.allowance'), findsNothing);
    await h.unmount(tester);
  });

  testWidgets('abre con 14 días: lo que queda hoy, el límite y lo gastado', (tester) async {
    final handle = tester.ensureSemantics();
    await h.pumpHome(tester, await h.seeded(Mode.variable, day300()));
    await open(tester);
    expect(find.text('S/ 1.42'), findsOneWidget, reason: 'floor(300 / 14) = 21.42 − 20.00');
    expect(text(tester, 'allowance.explain'),
        'Para que te alcance 14 días, puedes gastar S/ 21.42 al día. Hoy ya gastaste S/ 20.00.');
    expect(key('allowance.over'), findsNothing);
    expect(key('allowance.noOpening'), findsNothing);
    expect(tester.widget<Text>(key('allowance.explain')).data, contains('S/\u00A021.42'),
        reason: 'un monto nunca se parte entre "S/" y la cifra');
    expect(find.bySemanticsLabel('Puedes gastar hoy S/ 1.42'), findsOneWidget);
    handle.dispose();
    await h.unmount(tester);
  });

  testWidgets('7 y 30 días recalculan; con 30 hoy ya se pasó el límite', (tester) async {
    await h.pumpHome(tester, await h.seeded(Mode.variable, day300()));
    await open(tester);
    expect(tester.getSize(key('allowance.days.7')).width, lessThan(150), reason: 'el chip mide su texto, no la fila');
    expect(tester.getTopLeft(key('allowance.days.14')).dy, tester.getTopLeft(key('allowance.days.7')).dy,
        reason: 'los chips van en la misma fila');
    await tap(tester, 'allowance.days.7');
    expect(find.text('S/ 22.85'), findsOneWidget, reason: '42.85 − 20');
    await tap(tester, 'allowance.days.30');
    expect(find.text('S/ 0.00'), findsOneWidget);
    expect(text(tester, 'allowance.over'), 'Hoy pasaste el límite por S/ 10.00.');
    await h.unmount(tester);
  });

  testWidgets('sin gasto hoy: no menciona lo gastado', (tester) async {
    await h.pumpHome(tester, await h.seeded(Mode.variable, (s) async {
      await day300(spentSoles: 0)(s);
      await s.expense(5, h.ago(1));
    }));
    await open(tester);
    expect(text(tester, 'allowance.explain'), 'Para que te alcance 14 días, puedes gastar S/ 21.07 al día.');
    await h.unmount(tester);
  });

  testWidgets('"Otra fecha" abre el calendario', (tester) async {
    await h.pumpHome(tester, await h.seeded(Mode.variable, day300()));
    await open(tester);
    await tap(tester, 'allowance.until');
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await h.unmount(tester);
  });

  testWidgets('saldo ≤ 0: "Sin reserva"', (tester) async {
    await h.pumpHome(tester, await h.seeded(Mode.survival, day300(spentSoles: 400)));
    await open(tester);
    expect(find.descendant(of: key('allowance.sheet'), matching: find.text('Sin reserva')), findsOneWidget);
    expect(text(tester, 'allowance.noReserve'),
        'Tu saldo de hoy es S/ 0.00 o menos. Registra un ingreso o actualiza tu saldo inicial.');
    await h.unmount(tester);
  });

  testWidgets('sin saldo inicial: avisa que se calcula solo con los movimientos', (tester) async {
    await h.pumpHome(tester, await h.seeded(Mode.variable, (s) => s.income(1000, h.ago(2))));
    await open(tester);
    expect(text(tester, 'allowance.noOpening'),
        'Calculado solo con tus movimientos. Para más precisión, agrega tu saldo inicial.');
    await h.unmount(tester);
  });

  testWidgets('modo oscuro: sin errores', (tester) async {
    await h.pumpHome(tester, await h.seeded(Mode.variable, day300()), theme: AppTheme.dark);
    await open(tester);
    expect(find.text('S/ 1.42'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await h.unmount(tester);
  });
}
