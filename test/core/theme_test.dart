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
}
