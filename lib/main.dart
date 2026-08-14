import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/network/supabase_client.dart';
import 'core/notification/local_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inicializa la conexión con Supabase (Auth + BD).
  await SupabaseService.instance.init();

  // Canal de confirmación de capturas (flutter_local_notifications).
  await LocalNotificationService.instance.init();

  // Locale por defecto y símbolos de fecha (es_PE).
  await initializeDateFormatting('es_PE');
  Intl.defaultLocale = 'es_PE';

  await GoogleFonts.pendingFonts();

  runApp(const ProviderScope(child: App()));
}
