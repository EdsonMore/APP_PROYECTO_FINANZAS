import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:saldo_claro/core/theme/app_theme.dart';
import 'package:saldo_claro/core/theme/tokens.dart';

void main() {
  for (final (name, theme, palette) in [
    ('claro', AppTheme.light, Palette.light),
    ('oscuro', AppTheme.dark, Palette.dark),
  ]) {
    testWidgets('tema $name renderiza y usa los tokens', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: theme,
        home: Builder(builder: (c) {
          ctx = c;
          return Scaffold(
            body: Column(children: [
              Text('Te alcanza para ~23 días', style: Theme.of(c).textTheme.displayLarge),
              FilledButton(onPressed: () {}, child: const Text('+ Gasto')),
              const Card(child: Text('En qué se va')),
            ]),
          );
        }),
      ));

      expect(tester.takeException(), isNull);
      final t = Theme.of(ctx);
      expect(t.scaffoldBackgroundColor, palette.canvas);
      expect(t.colorScheme.surface, palette.surface);
      expect(t.colorScheme.primary, palette.ink);
      expect(t.colorScheme.error, palette.expenseFg);
      expect(ctx.palette, same(palette));
      expect(t.textTheme.displayLarge!.fontFamily, AppType.serif);
      expect(t.textTheme.bodyLarge!.fontFamily, AppType.sans);
      expect(t.textTheme.displayLarge!.color, palette.ink);
    });
  }

  test('categoryColor: slot → paleta del tema; valor desconocido → piedra', () {
    expect(categoryColor('cat:1', Brightness.light), const Color(0xFFCA653C));
    expect(categoryColor('cat:1', Brightness.dark), const Color(0xFFD87248));
    expect(categoryColor('cat:9', Brightness.light), const Color(0xFF09919D));
    expect(categoryColor('cat:5', Brightness.dark), const Color(0xFF909A40));
    for (final bad in ['#525252', 'cat:0', 'cat:10', 'cat:', 'cat:x', '']) {
      expect(categoryColor(bad, Brightness.light), categoryLight[5], reason: bad);
      expect(categoryColor(bad, Brightness.dark), categoryDark[5], reason: bad);
    }
  });

  test('ningún estilo pide un peso no empaquetado', () {
    final packaged = [FontWeight.w400, FontWeight.w500, FontWeight.w600];
    for (final s in [AppType.display, AppType.title, AppType.heading, AppType.body, AppType.label, AppType.link,
        AppType.caption, AppType.amount, AppType.amountInput, AppType.button]) {
      expect(packaged, contains(s.fontWeight), reason: '$s');
      if (s.fontFamily == AppType.serif) expect(s.fontWeight, FontWeight.w500);
    }
  });

  test('montos con cifras tabulares', () {
    expect(AppType.amount.fontFeatures, contains(const FontFeature.tabularFigures()));
    expect(AppType.amountInput.fontFeatures, contains(const FontFeature.tabularFigures()));
  });

  // C1: el spinner de "Guardar" usa Palette.canvas sobre Palette.ink.
  for (final (name, p) in [('claro', Palette.light), ('oscuro', Palette.dark)]) {
    test('spinner de Guardar contrasta con el botón en tema $name', () {
      expect(p.canvas, isNot(p.ink));
      final hi = [p.canvas, p.ink].map((c) => c.computeLuminance()).reduce((a, b) => a > b ? a : b);
      final lo = [p.canvas, p.ink].map((c) => c.computeLuminance()).reduce((a, b) => a < b ? a : b);
      // ≥ 3:1, mínimo WCAG para componentes no textuales.
      expect((hi + 0.05) / (lo + 0.05), greaterThanOrEqualTo(3));
    });
  }

  // C2: el carril de la barra de presupuesto se distingue del fondo (WCAG 1.4.11).
  for (final (name, p) in [('claro', Palette.light), ('oscuro', Palette.dark)]) {
    double ratio(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
    }

    test('carril de presupuesto ≥ 3:1 sobre surface y canvas en tema $name', () {
      expect(ratio(p.track, p.surface), greaterThanOrEqualTo(3));
      expect(ratio(p.track, p.canvas), greaterThanOrEqualTo(3), reason: 'la barra va sobre el fondo de la pantalla');
      expect(ratio(p.ink, p.track), greaterThanOrEqualTo(3), reason: 'el relleno se distingue del carril');
    });
  }
}

