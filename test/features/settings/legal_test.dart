import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:saldo_claro/domain/metrics.dart';
import 'package:saldo_claro/features/settings/legal_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/real_fonts.dart';
import '../home/home_screen_test.dart' as h;
import 'settings_screen_test.dart' as st;

void main() {
  setUpAll(() async {
    await initializeDateFormatting('es_PE');
    await loadRealFonts();
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    SharedPreferences.resetStatic();
  });

  group('textos legales', () {
    for (final (asset, web) in [
      (privacyAsset, 'docs/play-store/politica-privacidad.md'),
      (termsAsset, 'docs/play-store/terminos.md'),
    ]) {
      test('$asset es idéntico a $web (la app y la web nunca se desincronizan)', () {
        String norm(String s) => s.replaceAll('\r\n', '\n');
        expect(norm(File(asset).readAsStringSync()), norm(File(web).readAsStringSync()));
      });

      test('$asset: sin guion largo, sin "sueldo", con fecha y contacto', () {
        final s = File(asset).readAsStringSync();
        expect(s, isNot(contains('—')));
        expect(s.toLowerCase(), isNot(contains('sueldo')));
        expect(parseLegal(s).updated, startsWith('Última actualización: '));
        expect(s, contains('## Contacto'));
      });
    }

    test('parseLegal: título fuera, fecha aparte, subtítulos, párrafos y viñetas', () {
      final d = parseLegal('# Título\n\nÚltima actualización: hoy\n\n## Uno\n\nTexto.\n\n- a\n- b\r\n\n## Dos\nMás.');
      expect(d.updated, 'Última actualización: hoy');
      expect(d.blocks, [
        (kind: LegalKind.heading, text: 'Uno'),
        (kind: LegalKind.paragraph, text: 'Texto.'),
        (kind: LegalKind.bullet, text: 'a'),
        (kind: LegalKind.bullet, text: 'b'),
        (kind: LegalKind.heading, text: 'Dos'),
        (kind: LegalKind.paragraph, text: 'Más.'),
      ]);
    });
  });

  test('ficha de Play: descripción corta ≤ 80 y larga ≤ 4000 caracteres', () {
    final s = File('docs/play-store/descripcion.md').readAsStringSync().replaceAll('\r\n', '\n');
    final short = s.split('## Descripción corta (máx. 80)')[1].split('##').first.trim();
    final long = s.split('## Descripción larga (máx. 4000)')[1].trim();
    expect(short.length, lessThanOrEqualTo(80));
    expect(long.length, lessThanOrEqualTo(4000));
    expect(s, isNot(contains('—')));
  });

  for (final (asset, page) in [(privacyAsset, 'docs/landing/privacidad.html'), (termsAsset, 'docs/landing/terminos.html')]) {
    test('landing: $page dice lo mismo que $asset (correr generar_legal.py si cambia)', () {
      final html = File(page).readAsStringSync();
      String esc(String s) => const HtmlEscape(HtmlEscapeMode.element).convert(s);
      final doc = parseLegal(File(asset).readAsStringSync());
      expect(html, contains(esc(doc.updated)));
      for (final b in doc.blocks) {
        expect(html, contains(esc(b.text)), reason: b.text);
      }
      expect(html, isNot(contains('<script')));
    });
  }

  test('página web de borrado de cuenta (Play): existe, sin JavaScript, con mailto y enlazada desde la landing', () {
    final page = File('docs/landing/borrar-cuenta.html').readAsStringSync();
    expect(page, isNot(contains('<script')));
    expect(page, contains('href="mailto:saldoclaro.oficial@gmail.com?subject=Borrar%20mi%20cuenta'));
    expect(page, contains('30 días'));
    expect(File('docs/landing/index.html').readAsStringSync(), contains('href="borrar-cuenta.html"'));
  });

  test('release firma con debug si no hay android/key.properties (el build no se rompe)', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    expect(gradle, contains('if (keystoreProperties.isNotEmpty())'));
    expect(gradle, contains('signingConfigs.getByName("debug")'));
  });

  for (final (row, title, heading) in [
    ('privacy', 'Política de privacidad', 'Qué datos recolectamos'),
    ('terms', 'Términos y condiciones', 'SaldoClaro no es un asesor financiero'),
  ]) {
    testWidgets('Acerca de → $title: header, fecha y subtítulos', (tester) async {
      await st.pumpApp(tester, await h.seeded(Mode.variable));
      await st.openSettings(tester);
      await st.tapRow(tester, 'about');
      await tester.tap(find.byKey(Key('about.$row')));
      await tester.pumpAndSettle();
      expect(find.byType(LegalScreen), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      expect(find.text('Última actualización: 12 de octubre de 2026'), findsOneWidget);
      await tester.scrollUntilVisible(find.text(heading), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text(heading), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Contacto'), 300, scrollable: find.byType(Scrollable).last);
      expect(find.text('saldoclaro.oficial@gmail.com'), findsWidgets);
      await h.unmount(tester);
    });
  }
}
