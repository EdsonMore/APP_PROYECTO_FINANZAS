import 'package:intl/intl.dart';

/// Utilidades de formato para montos y fechas.
abstract final class Formatters {
  /// "S/ 1,250.50": símbolo adelante, coma de miles, punto decimal. Es el uso
  /// común en Perú y lo que muestra la hoja de registro. (El locale es_PE de
  /// intl da "1.250,50 S/", que no coincide.)
  static final NumberFormat _amount = NumberFormat('#,##0.00', 'en_US');

  static final NumberFormat _compact = NumberFormat.compact(locale: 'es_PE');

  static final DateFormat _date = DateFormat('dd MMM yyyy', 'es_PE');
  static final DateFormat _time = DateFormat('HH:mm', 'es_PE');

  /// Monto en centavos → "S/ 25.00" / "-S/ 3.50". Preferir esto: el dinero es int.
  static String soles(int cents) => '${cents < 0 ? '-' : ''}S/ ${_amount.format(cents.abs() / 100)}';

  static String currency(double value) => soles((value * 100).round());

  static String currencySigned(double value) => currency(value);

  static String compact(double value) => _compact.format(value);

  static String date(DateTime date) => _date.format(date);

  static String time(DateTime date) => _time.format(date);

  static String dateTime(DateTime date) => '${_date.format(date)} · ${_time.format(date)}';
}
