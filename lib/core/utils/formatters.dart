import 'package:intl/intl.dart';

/// Utilidades de formato para montos y fechas.
abstract final class Formatters {
  static final NumberFormat _currency = NumberFormat.currency(
    locale: 'es_PE',
    symbol: 'S/',
    decimalDigits: 2,
  );

  static final NumberFormat _compact = NumberFormat.compact(locale: 'es_PE');

  static final DateFormat _date = DateFormat('dd MMM yyyy', 'es_PE');
  static final DateFormat _time = DateFormat('HH:mm', 'es_PE');

  static String currency(double value) => _currency.format(value);

  static String currencySigned(double value) =>
      value < 0 ? '-${_currency.format(value.abs())}' : _currency.format(value);

  static String compact(double value) => _compact.format(value);

  static String date(DateTime date) => _date.format(date);

  static String time(DateTime date) => _time.format(date);

  static String dateTime(DateTime date) => '${_date.format(date)} · ${_time.format(date)}';
}
