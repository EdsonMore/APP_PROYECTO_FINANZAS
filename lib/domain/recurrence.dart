import 'metrics.dart' show day;

/// Recordatorios de pagos que se repiten (Fase 4D). Funciones puras, días del
/// dominio ([day]: UTC medianoche).

enum Frequency { weekly, monthly, yearly }

/// Días que trae cada mes de ese año.
int _daysIn(int year, int month) => DateTime.utc(year, month + 1, 0).day;

/// Vencimiento siguiente a [from]. [anchorDay] es el día original (N3): con
/// ancla 31, en un mes de 30 cae el 30 y en el siguiente vuelve al 31; el 29
/// de febrero, en años no bisiestos, cae el 28.
DateTime nextDue(DateTime from, Frequency f, {required int anchorDay}) {
  DateTime clamp(int y, int m) => day(y, m, anchorDay.clamp(1, _daysIn(y, m)));
  return switch (f) {
    Frequency.weekly => from.add(const Duration(days: 7)),
    Frequency.monthly => clamp(from.month == 12 ? from.year + 1 : from.year, from.month == 12 ? 1 : from.month + 1),
    Frequency.yearly => clamp(from.year + 1, from.month),
  };
}

/// Vencimiento anterior a [due]: dónde empieza la ventana para buscar un pago
/// ya registrado a mano (E1).
DateTime previousDue(DateTime due, Frequency f, {required int anchorDay}) {
  DateTime clamp(int y, int m) => day(y, m, anchorDay.clamp(1, _daysIn(y, m)));
  return switch (f) {
    Frequency.weekly => due.subtract(const Duration(days: 7)),
    Frequency.monthly => clamp(due.month == 1 ? due.year - 1 : due.year, due.month == 1 ? 12 : due.month - 1),
    Frequency.yearly => clamp(due.year - 1, due.month),
  };
}

/// fix5: días hasta el vencimiento; negativo si ya venció. (No confundir con
/// `daysUntil` de metrics, que cuenta el último día.)
int daysToDue(DateTime due, DateTime today) => due.difference(today).inDays;

/// Rojo: vencido o vence hoy. Ámbar: 1 a 3 días. Neutro: más.
enum DueTone { overdue, soon, later }

DueTone dueTone(int days) => days <= 0 ? DueTone.overdue : (days <= 3 ? DueTone.soon : DueTone.later);

/// E3: cuántos vencimientos ya llegaron sin pagarse (el de hoy cuenta). La
/// fecha NO avanza sola: solo con Pagado o Saltar, de a un período.
int pendingPeriods(DateTime due, Frequency f, {required int anchorDay, required DateTime today}) {
  var n = 0;
  for (var d = due; !d.isAfter(today); d = nextDue(d, f, anchorDay: anchorDay)) {
    n++;
  }
  return n;
}

/// fix5: los avisos de un vencimiento, a las 9:00 hora local: 3 días antes,
/// el día y cada día del +1 al +7 (9 en total). DateTime corrige el desborde de mes.
const reminderOffsets = [-3, 0, 1, 2, 3, 4, 5, 6, 7];

List<DateTime> reminderMoments(DateTime due) =>
    [for (final o in reminderOffsets) DateTime(due.year, due.month, due.day + o, 9)];
