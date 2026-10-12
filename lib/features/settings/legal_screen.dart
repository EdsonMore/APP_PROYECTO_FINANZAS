import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/tokens.dart';
import 'settings_screen.dart';

const privacyAsset = 'assets/legal/privacidad.md';
const termsAsset = 'assets/legal/terminos.md';

enum LegalKind { heading, paragraph, bullet }

typedef LegalBlock = ({LegalKind kind, String text});

/// Markdown mínimo de los textos legales: `#` título (lo pone el header),
/// `##` subtítulo, `- ` viñeta y párrafos separados por línea en blanco.
/// La primera línea de texto ("Última actualización: …") se devuelve aparte.
({String updated, List<LegalBlock> blocks}) parseLegal(String md) {
  var updated = '';
  final blocks = <LegalBlock>[];
  for (final raw in md.split(RegExp(r'\r?\n'))) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('# ')) continue;
    if (line.startsWith('## ')) {
      blocks.add((kind: LegalKind.heading, text: line.substring(3)));
    } else if (line.startsWith('- ')) {
      blocks.add((kind: LegalKind.bullet, text: line.substring(2)));
    } else if (updated.isEmpty && blocks.isEmpty) {
      updated = line;
    } else {
      blocks.add((kind: LegalKind.paragraph, text: line));
    }
  }
  return (updated: updated, blocks: blocks);
}

/// Política de privacidad o Términos: texto con scroll, subtítulos en heading.
class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key, required this.title, required this.asset});
  final String title;
  final String asset;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<String>(
          future: rootBundle.loadString(asset),
          builder: (context, snap) {
            final doc = snap.hasData ? parseLegal(snap.data!) : null;
            return ListView(
              key: const Key('legal.scroll'),
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.xl),
              children: [
                SubpageHeader(title: title),
                if (doc != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 48 + Space.xs, top: Space.xs),
                    child: Text(doc.updated, style: AppType.caption.copyWith(color: p.inkMuted)),
                  ),
                  for (final b in doc.blocks)
                    switch (b.kind) {
                      LegalKind.heading => Padding(
                          padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
                          child: Semantics(
                            header: true,
                            child: Text(b.text, style: AppType.heading.copyWith(color: p.ink)),
                          ),
                        ),
                      LegalKind.paragraph => Padding(
                          padding: const EdgeInsets.only(bottom: Space.sm),
                          child: Text(b.text, style: AppType.body.copyWith(color: p.ink)),
                        ),
                      LegalKind.bullet => Padding(
                          padding: const EdgeInsets.only(left: Space.sm, bottom: Space.xs),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('•  ', style: AppType.body.copyWith(color: p.inkMuted)),
                            Expanded(child: Text(b.text, style: AppType.body.copyWith(color: p.ink))),
                          ]),
                        ),
                    },
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
