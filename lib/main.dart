import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es_PE');
  Intl.defaultLocale = 'es_PE';
  LicenseRegistry.addLicense(_fontLicenses);
  runApp(const ProviderScope(child: App()));
}

/// La OFL exige distribuir la licencia junto con las fuentes.
Stream<LicenseEntry> _fontLicenses() async* {
  for (final font in ['Newsreader', 'Geist']) {
    yield LicenseEntryWithLineBreaks([font], await rootBundle.loadString('assets/fonts/licenses/OFL-$font.txt'));
  }
}
