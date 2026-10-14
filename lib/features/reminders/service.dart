import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart' show dayOf;
import '../../domain/recurrence.dart';
import 'notifier.dart';

/// Recordatorios (4D): la tabla manda; las alarmas se derivan de ella.
class ReminderService {
  ReminderService(this._db, this._notifier, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final AppDatabase _db;
  final ReminderNotifier _notifier;
  final DateTime Function() _clock;

  /// N2 + N8 (al abrir la app y al volver): corre las fechas vencidas sin
  /// crear nada, cancela todas las alarmas y vuelve a programarlas.
  Future<void> refreshAll() async {
    final today = dayOf(_clock());
    for (final r in await _db.select(_db.recurrences).get()) {
      final rolled = rollForward(parseIsoDay(r.nextDue), r.frequency, anchorDay: r.anchorDay, today: today);
      if (isoDay(rolled) != r.nextDue) await _db.setRecurrenceDue(r.id, rolled);
    }
    await _notifier.cancelAll();
    for (final r in await _db.select(_db.recurrences).get()) {
      await schedule(r);
    }
  }

  /// Programa el aviso de [r] (3 días antes, 9:00). Si ese momento ya pasó, no
  /// avisa: espera al período siguiente.
  Future<void> schedule(Recurrence r) async {
    await _notifier.cancel(r.notificationId);
    final due = parseIsoDay(r.nextDue);
    final at = reminderAt(due);
    if (!at.isAfter(_clock())) return;
    final category = await (_db.select(_db.categories)..where((c) => c.id.equals(r.categoryId))).getSingleOrNull();
    await _notifier.schedule(
      id: r.notificationId,
      at: at,
      title: 'Se viene un pago: ${Formatters.soles(r.amountCents)}',
      body: '${reminderLabel(r, category?.name)} vence el '
          '${DateFormat('EEEE d MMM', 'es_PE').format(DateTime(due.year, due.month, due.day))}. Toca para registrarlo.',
      payload: r.id,
    );
  }

  /// El usuario registró el pago (R1: siempre él): el vencimiento pasa al
  /// período siguiente y se programa de nuevo.
  Future<void> confirmed(String id) async {
    final r = await (_db.select(_db.recurrences)..where((x) => x.id.equals(id))).getSingleOrNull();
    if (r == null) return;
    final next = nextDue(parseIsoDay(r.nextDue), r.frequency, anchorDay: r.anchorDay);
    await _db.setRecurrenceDue(id, next);
    await schedule((await (_db.select(_db.recurrences)..where((x) => x.id.equals(id))).getSingle()));
  }

  Future<void> remove(Recurrence r) async {
    await _notifier.cancel(r.notificationId);
    await _db.deleteRecurrence(r.id);
  }
}

/// "Internet (Vivienda)"; sin nota, solo la categoría (o "Gasto" si ya no existe).
String reminderLabel(Recurrence r, String? categoryName) {
  final note = r.note?.trim();
  final cat = categoryName ?? 'Gasto';
  return note == null || note.isEmpty ? cat : '$note ($cat)';
}

const frequencyLabels = {
  Frequency.weekly: 'Cada semana',
  Frequency.monthly: 'Cada mes',
  Frequency.yearly: 'Cada año',
};

/// main.dart lo reemplaza por [PluginReminderNotifier].
final reminderNotifierProvider = Provider<ReminderNotifier>((_) => FakeReminderNotifier());

final reminderServiceProvider = Provider<ReminderService>(
    (ref) => ReminderService(ref.watch(databaseProvider), ref.watch(reminderNotifierProvider)));

final recurrencesStreamProvider = StreamProvider<List<Recurrence>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.recurrences)..orderBy([(r) => OrderingTerm(expression: r.nextDue)])).watch();
});

/// Recordatorio tocado en una notificación, a abrir en el Home (N7).
final pendingReminderProvider = StateProvider<String?>((_) => null);

/// ¿Hay permiso de notificaciones? Se vuelve a preguntar al invalidarlo.
final notificationsGrantedProvider =
    FutureProvider.autoDispose<bool>((ref) => ref.watch(reminderNotifierProvider).permissionGranted());
