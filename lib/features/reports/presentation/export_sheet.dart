import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import 'package:saldo_claro/core/config/app_config.dart';
import 'package:saldo_claro/core/models/transaction.dart';
import 'package:saldo_claro/core/utils/formatters.dart';
import 'package:saldo_claro/features/dashboard/providers/dashboard_providers.dart';
import 'package:saldo_claro/features/reports/data/export_service.dart';

/// Diálogo para generar un reporte mensual (CSV o PDF) y compartirlo.
class ExportSheet extends ConsumerStatefulWidget {
  const ExportSheet({super.key});

  @override
  ConsumerState<ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends ConsumerState<ExportSheet> {
  ExportFormat _format = ExportFormat.pdf;
  DateTime _month = DateTime.now();
  bool _working = false;

  DateRangeReport get _range {
    final start = DateTime(_month.year, _month.month, 1);
    final end = DateTime(_month.year, _month.month + 1, 0, 23, 59, 59);
    return DateRangeReport(start: start, end: end);
  }

  Future<void> _generate() async {
    final transactions =
        ref.read(allTransactionsProvider).value ?? const <Transaction>[];
    final range = _range;
    setState(() => _working = true);

    try {
      File file;
      String text;
      if (_format == ExportFormat.csv) {
        final csv = ExportService.buildCsv(
          transactions: transactions,
          from: range.start,
          to: range.end,
        );
        file = await ExportService.writeTempText(
          content: csv,
          filename:
              'saldo_claro_${_month.year}_${_month.month.toString().padLeft(2, '0')}.csv',
        );
        text = 'Reporte SaldoClaro CSV';
      } else {
        final bytes = await ExportService.buildPdf(
          transactions: transactions,
          from: range.start,
          to: range.end,
        );
        file = await ExportService.writeTempBytes(
          bytes: bytes,
          filename:
              'saldo_claro_${_month.year}_${_month.month.toString().padLeft(2, '0')}.pdf',
        );
        text = 'Reporte SaldoClaro PDF';
      }

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: text),
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error al exportar: $e')));
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = Formatters.date(_range.start);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(ColorConfig.surfaceAlt),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Exportar reporte 📄',
            style: GoogleFonts.inter(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: const Color(ColorConfig.textPrimary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Se genera un resumen con tus movimientos y compartirlo por cualquier app.',
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(ColorConfig.textSecondary),
            ),
          ),
          const SizedBox(height: 20),

          // Mes
          const Text('Período',
              style: TextStyle(color: Color(ColorConfig.textSecondary))),
          const SizedBox(height: 8),
          SegmentedButton<DateTime>(
            segments: [
              ButtonSegment(
                value: DateTime(DateTime.now().year, DateTime.now().month),
                label: const Text('Mes actual'),
                icon: const Icon(Icons.today),
              ),
              ButtonSegment(
                value: DateTime.now()
                    .subtract(const Duration(days: 32)),
                label: const Text('Mes anterior'),
                icon: const Icon(Icons.date_range),
              ),
            ],
            selected: {_month},
            onSelectionChanged: (s) => setState(() => _month = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            monthLabel,
            style: const TextStyle(
              fontSize: 13,
              color: Color(ColorConfig.textSecondary),
            ),
          ),
          const SizedBox(height: 20),

          // Formato
          const Text('Formato',
              style: TextStyle(color: Color(ColorConfig.textSecondary))),
          const SizedBox(height: 8),
          SegmentedButton<ExportFormat>(
            segments: const [
              ButtonSegment(
                value: ExportFormat.pdf,
                label: Text('PDF'),
                icon: Icon(Icons.picture_as_pdf_outlined),
              ),
              ButtonSegment(
                value: ExportFormat.csv,
                label: Text('CSV / Excel'),
                icon: Icon(Icons.table_chart_outlined),
              ),
            ],
            selected: {_format},
            onSelectionChanged: (s) => setState(() => _format = s.first),
          ),
          const SizedBox(height: 24),

          ElevatedButton.icon(
            onPressed: _working ? null : _generate,
            icon: _working
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.share),
            label: Text(_working ? 'Generando…' : 'Generar y compartir'),
          ),
        ],
      ),
    );
  }
}

class DateRangeReport {
  const DateRangeReport({required this.start, required this.end});

  final DateTime start;
  final DateTime end;
}