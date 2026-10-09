import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/metrics.dart';
import 'database.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// null hasta que termina el onboarding.
final settingsProvider = StreamProvider<Setting?>((ref) => ref.watch(databaseProvider).watchSettings());

/// Día local de hoy. Inyectable para tests (nunca DateTime.now() en la UI).
final todayProvider = Provider<DateTime>((_) => dayOf(DateTime.now()));
