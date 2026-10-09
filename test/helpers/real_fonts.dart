import 'dart:io';

import 'package:flutter/services.dart';

/// Fuentes reales: con Ahem (la fuente de test) los anchos no se parecen a
/// Geist y el test de 640 dp mediría otra cosa.
Future<void> loadRealFonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f').readAsBytesSync())));
    }
    await l.load();
  }

  await load('Newsreader', ['Newsreader16pt-Medium.ttf']);
  await load('Geist', ['Geist-Regular.ttf', 'Geist-Medium.ttf', 'Geist-SemiBold.ttf']);
}
