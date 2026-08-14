import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/utils/formatters.dart';

/// Formato de exportación soportado.
enum ExportFormat { csv, pdf }

/// Genera reportes mensuales en CSV o PDF y los deja listos para compartir.
class ExportService {
  /// Construye el CSV (UTF-8) con el detalle de movimientos del período.
  static String buildCsv({
    required List<Transaction> transactions,
    required DateTime from,
    required DateTime to,
  }) {
    final buffer = StringBuffer()
      ..writeln('Tipo,Fecha,Comercio,Categoría,Aplicación,Monto S/');
    for (final t in transactions) {
      if (t.createdAt.isBefore(from) || t.createdAt.isAfter(to)) continue;
      final type = t.isIncome ? 'Ingreso' : 'Gasto';
      buffer.writeln(
        '$type,'
        '${Formatters.date(t.createdAt)},'
        '${_escapeCsv(t.merchantOrPerson ?? 'Movimiento')},'
        '${_escapeCsv(t.categoryName ?? 'Sin categoría')},'
        '${t.sourceApp},'
        '${t.amount.toStringAsFixed(2)}',
      );
    }
    return buffer.toString();
  }

  static String _escapeCsv(String value) =>
      '"${value.replaceAll('"', '""')}"';

  /// Genera un PDF con el resumen mensual y la tabla de movimientos.
  static Future<Uint8List> buildPdf({
    required List<Transaction> transactions,
    required DateTime from,
    required DateTime to,
  }) async {
    final list = transactions
        .where((t) =>
            !t.createdAt.isBefore(from) && !t.createdAt.isAfter(to))
        .toList();

    var totalExpense = 0.0;
    var totalIncome = 0.0;
    for (final t in list) {
      if (t.isIncome) {
        totalIncome += t.amount;
      } else {
        totalExpense += t.amount;
      }
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) => [
          pw.Header(
            level: 0,
            child: pw.Text('SaldoClaro — Reporte financiero'),
          ),
          pw.Text(
            'Período: ${Formatters.date(from)} — ${Formatters.date(to)}',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Ingresos: S/ ${totalIncome.toStringAsFixed(2)}',
                style: const pw.TextStyle(color: PdfColors.green700),
              ),
              pw.Text(
                'Gastos: S/ ${totalExpense.toStringAsFixed(2)}',
                style: const pw.TextStyle(color: PdfColors.red700),
              ),
            ],
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: ['Fecha', 'Tipo', 'Comercio', 'Categoría', 'App', 'Monto'],
            data: [
              for (final t in list)
                [
                  Formatters.date(t.createdAt),
                  t.isIncome ? 'Ingreso' : 'Gasto',
                  t.merchantOrPerson ?? 'Movimiento',
                  t.categoryName ?? 'Sin categoría',
                  t.sourceApp,
                  (t.isIncome ? '+ ' : '- ') + t.amount.toStringAsFixed(2),
                ],
            ],
            headerStyle: const pw.TextStyle(
              color: PdfColors.white,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: const pw.BoxDecoration(
              color: PdfColors.blueGrey700,
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(4),
          ),
        ],
      ),
    );

    return doc.save();
  }

  /// Escribe un archivo temporal con bytes y devuelve la ruta.
  static Future<File> writeTempBytes({
    required Uint8List bytes,
    required String filename,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// Escribe un archivo temporal con texto y devuelve la ruta.
  static Future<File> writeTempText({
    required String content,
    required String filename,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content, flush: true);
    return file;
  }
}