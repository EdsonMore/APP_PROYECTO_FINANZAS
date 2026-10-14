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

/// N2: si el vencimiento ya pasó sin confirmarse, la primera fecha que no es
/// anterior a [today]. Nunca crea gastos: solo corre la fecha.
DateTime rollForward(DateTime due, Frequency f, {required int anchorDay, required DateTime today}) {
  var d = due;
  while (d.isBefore(today)) {
    d = nextDue(d, f, anchorDay: anchorDay);
  }
  return d;
}

/// Momento del aviso: 3 días antes del vencimiento, a las 9:00 hora local.
DateTime reminderAt(DateTime due) {
  final d = due.subtract(const Duration(days: 3));
  return DateTime(d.year, d.month, d.day, 9);
}
