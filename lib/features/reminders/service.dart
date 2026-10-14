import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/utils/formatters.dart';
import '../../data/database.dart';
import '../../data/providers.dart';
import '../../domain/metrics.dart' show EntryKind;
import '../../domain/recurrence.dart';
import 'notifier.dart';

/// Recordatorios (4D): la tabla manda; las alarmas se derivan de ella.
/// fix5: la fecha solo avanza con Pagado o Saltar; hasta 9 avisos por pago.
class ReminderService {
  ReminderService(this._db, this._notifier, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;
  final AppDatabase _db;
  final ReminderNotifier _notifier;
  final DateTime Function() _clock;

  /// Id de cada aviso: 9 por recordatorio. ponytail: Android admite ~500
  /// alarmas por app, o sea ~50 recordatorios (E6); más, agrupar avisos.
  static int _alarmId(Recurrence r, int k) => r.notificationId * 10 + k;

  Future<Recurrence?> _byId(String id) =>
      (_db.select(_db.recurrences)..where((x) => x.id.equals(id))).getSingleOrNull();

  /// Al abrir la app y al volver (N8): cancela todo y reprograma. Ya no corre
  /// las fechas: un pago sin pagar sigue pendiente (fix5).
  Future<void> refreshAll() async {
    await _notifier.cancelAll();
    for (final r in await _db.select(_db.recurrences).get()) {
      await schedule(r);
    }
  }

  /// Los avisos de [r] que todavía están por delante: 3 días antes, el día y
  /// del +1 al +7, a las 9:00.
  Future<void> schedule(Recurrence r) async {
    await _cancel(r);
    final due = parseIsoDay(r.nextDue);
    final now = _clock();
    final category = await (_db.select(_db.categories)..where((c) => c.id.equals(r.categoryId))).getSingleOrNull();
    final label = reminderLabel(r, category?.name);
    final amount = Formatters.soles(r.amountCents);
    final date = DateFormat('EEEE d MMM', 'es_PE').format(DateTime(due.year, due.month, due.day));
    final moments = reminderMoments(due);
    for (var k = 0; k < moments.length; k++) {
      if (!moments[k].isAfter(now)) continue;
      final offset = reminderOffsets[k];
      await _notifier.schedule(
        id: _alarmId(r, k),
        at: moments[k],
        title: offset < 0
            ? 'Se viene un pago: $amount'
            : (offset == 0 ? 'Hoy vence: $amount' : 'Pago vencido: $amount'),
        body: offset < 0
            ? '$label vence el $date. Toca para registrarlo.'
            : (offset == 0 ? '$label vence hoy. Toca para registrarlo.' : '$label venció el $date. Toca para registrarlo.'),
        payload: r.id,
      );
    }
  }

  Future<void> _cancel(Recurrence r) async {
    for (var k = 0; k < reminderOffsets.length; k++) {
      await _notifier.cancel(_alarmId(r, k));
    }
  }

  /// Pagado (R1: siempre el usuario): el vencimiento pasa al período
  /// siguiente y se reprograma.
  Future<void> confirmed(String id) async {
    final r = await _byId(id);
    if (r == null) return;
    await setDue(id, nextDue(parseIsoDay(r.nextDue), r.frequency, anchorDay: r.anchorDay));
  }

  /// Saltar este período: avanza sin crear gasto (E2). Devuelve el
  /// vencimiento anterior, para "Deshacer".
  Future<DateTime?> skip(String id) async {
    final r = await _byId(id);
    if (r == null) return null;
    final previous = parseIsoDay(r.nextDue);
    await setDue(id, nextDue(previous, r.frequency, anchorDay: r.anchorDay));
    return previous;
  }

  /// Fija el próximo pago y reprograma sus avisos (también deshace un salto).
  Future<void> setDue(String id, DateTime due) async {
    await _db.setRecurrenceDue(id, due);
    if (await _byId(id) case final r?) await schedule(r);
  }

  /// E1: un gasto ya anotado de la misma categoría y el mismo monto, después
  /// del vencimiento anterior y hasta hoy. El más reciente; null si no hay.
  Future<Entry?> findPayment(Recurrence r, {required DateTime today}) async {
    final from = previousDue(parseIsoDay(r.nextDue), r.frequency, anchorDay: r.anchorDay);
    return (_db.select(_db.entries)
          ..where((e) =>
              e.kind.equalsValue(EntryKind.expense) &
              e.categoryId.equals(r.categoryId) &
              e.amountCents.equals(r.amountCents) &
              e.occurredOn.isBiggerThanValue(isoDay(from)) &
              e.occurredOn.isSmallerOrEqualValue(isoDay(today)))
          ..orderBy([(e) => OrderingTerm.desc(e.occurredOn), (e) => OrderingTerm.desc(e.createdAt)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> remove(Recurrence r) async {
    await _cancel(r);
    await _db.deleteRecurrence(r.id);
  }
}

/// "vence hoy", "en 3 días", "vencido hace 2 días"…
String dueStatus(int days) => switch (days) {
      0 => 'vence hoy',
      1 => 'vence mañana',
      -1 => 'venció ayer',
      > 1 => 'en $days días',
      _ => 'vencido hace ${-days} días',
    };

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
