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

/// Combina las fuentes de un resumen: el primer error gana; si alguna sigue
/// cargando, cargando; si no, [build]. Lo usan Home, Presupuesto e Insights.
AsyncValue<T> combineAsync<T>(List<AsyncValue<Object?>> parts, T Function() build) {
  for (final p in parts) {
    if (p.hasError) return AsyncError(p.error!, p.stackTrace ?? StackTrace.current);
  }
  if (parts.any((p) => !p.hasValue)) return const AsyncLoading();
  return AsyncData(build());
}

/// Día local de hoy. Inyectable para tests (nunca DateTime.now() en la UI).
final todayProvider = Provider<DateTime>((_) => dayOf(DateTime.now()));
