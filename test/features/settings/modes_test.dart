import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/settings/modes_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import '../home/home_screen_test.dart' as h;
import 'settings_screen_test.dart' as st;

const names = {Mode.stable: 'Estable', Mode.variable: 'Variable', Mode.survival: 'Supervivencia'};

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  test('ningún texto de modo dice "sueldo" (SPEC §Reglas duras)', () {
    for (final t in [...modeExplanations.values, mixedNote]) {
      expect(t.toLowerCase(), isNot(contains('sueldo')));
    }
  });

  group('Ajustes', () {
    for (final mode in Mode.values) {
      testWidgets('${mode.name}: "Modo actual" y debajo "Modos de uso", antes de "Nombre del espacio"', (tester) async {
        await st.pumpApp(tester, await h.seeded(mode));
        await st.openSettings(tester);
        expect(find.descendant(of: find.byKey(const Key('settings.mode')), matching: find.text('Modo actual')),
            findsOneWidget);
        expect(find.text('Modo de uso'), findsNothing, reason: 'la fila se renombró');
        double y(String k) => tester.getTopLeft(find.byKey(Key('settings.$k'))).dy;
        expect(y('mode'), lessThan(y('modes')));
        expect(y('modes'), lessThan(y('name')));
        await h.unmount(tester);
      });
    }

    testWidgets('"Modos de uso" abre la pantalla con los 3 modos, "Ejemplo" y el actual marcado', (tester) async {
      await st.pumpApp(tester, await h.seeded(Mode.survival));
      await st.openSettings(tester);
      await st.tapRow(tester, 'modes');
      expect(find.byType(ModesScreen), findsOneWidget);
      for (final m in Mode.values) {
        await tester.scrollUntilVisible(find.byKey(Key('modes.${m.name}')), 200,
            scrollable: find.byType(Scrollable).last);
        expect(find.text(names[m]!), findsOneWidget);
        expect(find.text(modeExplanations[m]!), findsOneWidget);
        expect(find.byKey(Key('modes.current.${m.name}')), m == Mode.survival ? findsOneWidget : findsNothing,
            reason: m.name);
      }
      expect(find.text('Ejemplo', skipOffstage: false), findsNWidgets(3));
      expect(find.byKey(const Key('modes.example.bar'), skipOffstage: false), findsOneWidget);
      expect(find.text(mixedNote, skipOffstage: false), findsOneWidget);
      await h.unmount(tester);
    });
  });

  group('ícono ⓘ del Home', () {
    for (final mode in Mode.values) {
      testWidgets('${mode.name}: abre la hoja con el modo actual y su explicación', (tester) async {
        await h.pumpHome(tester, await h.seeded(mode));
        await tester.tap(find.byKey(const Key('home.modeInfo')));
        await tester.pumpAndSettle();
        final sheet = find.byKey(const Key('modeInfo.sheet'));
        expect(find.descendant(of: sheet, matching: find.text('Modo ${names[mode]}')), findsOneWidget);
        expect(find.descendant(of: sheet, matching: find.text(modeExplanations[mode]!)), findsOneWidget);
        expect(tester.widget<BottomSheet>(find.byType(BottomSheet)).showDragHandle, isFalse,
            reason: 'una sola asa: SheetGrabber');
        await h.unmount(tester);
      });
    }

    testWidgets('"Ver todos los modos" cierra la hoja y abre "Modos de uso" con el actual marcado', (tester) async {
      await h.pumpHome(tester, await h.seeded(Mode.stable));
      await tester.tap(find.byKey(const Key('home.modeInfo')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('modeInfo.seeAll')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modeInfo.sheet')), findsNothing);
      expect(find.byType(ModesScreen), findsOneWidget);
      expect(find.byKey(const Key('modes.current.stable')), findsOneWidget);
      // Al volver, la hoja no reaparece: se cerró antes de abrir la pantalla.
      await tester.tap(find.byTooltip('Volver'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('modeInfo.sheet'), skipOffstage: false), findsNothing);
      expect(find.byKey(const Key('home.modeInfo')), findsOneWidget);
      await h.unmount(tester);
    });
  });

  testWidgets('Home sin saldo: "Sin reserva" (antes "Sin colchón")', (tester) async {
    await h.pumpHome(tester, await h.seeded(Mode.survival, (s) => s.expense(50, h.ago(1))));
    expect(find.text('Sin reserva'), findsOneWidget);
    expect(find.textContaining('colchón'), findsNothing);
    await h.unmount(tester);
  });
}
