import '../../core/utils/formatters.dart';
import '../../domain/insights.dart';

/// "Lectura del mes" (5AB): una frase por hecho del motor (lib/domain/insights.dart).
const _weekdays = {
  DateTime.monday: 'Los lunes',
  DateTime.tuesday: 'Los martes',
  DateTime.wednesday: 'Los miércoles',
  DateTime.thursday: 'Los jueves',
  DateTime.friday: 'Los viernes',
  DateTime.saturday: 'Los sábados',
  DateTime.sunday: 'Los domingos',
};

String factText(Fact f, {required Map<String, String> categoryNames}) {
  final s = Formatters.soles;
  return switch (f) {
    BalanceFact(:final cents) when cents < 0 => 'Este mes salió ${s(-cents)} más de lo que entró.',
    BalanceFact(:final cents) => 'Este mes te quedan ${s(cents)} de lo que entró.',
    CategoryChange(:final categoryId, :final deltaCents, :final percent, :final previousMonth) => () {
        final name = categoryNames[categoryId] ?? 'esa categoría';
        final month = Formatters.month(previousMonth).toLowerCase();
        return deltaCents > 0
            ? 'Vas ${s(deltaCents)} más en $name que a esta altura de $month (+$percent%).'
            : 'Vas ${s(-deltaCents)} menos en $name que a esta altura de $month (−${-percent}%).';
      }(),
    DaysLeftFact(:final days, :final balanceCents, :final dailyCents) => () {
        final left = days == 1 ? 'Queda 1 día del mes' : 'Quedan $days días del mes';
        return dailyCents == null
            ? '$left y no tienes reserva.'
            : '$left: con ${s(balanceCents)} te alcanza ~${s(dailyCents)} al día.';
      }(),
    StreakFact(:final days, :final thresholdCents) => 'Llevas $days días sin pasarte de ${s(thresholdCents)} al día.',
    WeekdayFact(:final weekday, :final avgCents) =>
      '${_weekdays[weekday]} es cuando más gastas: ${s(avgCents)} en promedio.',
  };
}
