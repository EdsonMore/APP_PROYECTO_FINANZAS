import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../../domain/metrics.dart';

/// Punto y coma: Excel con configuración regional de Perú lo espera al abrir
/// con doble clic (con coma, todo cae en una columna).
const csvSeparator = ';';
const _bom = '﻿'; // UTF-8 con BOM: Excel muestra bien "Préstamo", "Menú".

const csvColumns = [
  'id',
  'kind',
  'amount_cents',
  'amount',
  'occurred_on',
  'category_or_source',
  'category_or_source_id',
  'note',
  'origin',
  'created_at',
  'updated_at',
  'account_label',
];

String csvFileName(DateTime today) => 'saldoclaro-movimientos-${isoDay(today)}.csv';

/// Todos los movimientos, del más nuevo al más viejo. Incluye nombres de
/// categorías/fuentes archivadas. Fin de línea CRLF (RFC 4180, Excel).
String entriesToCsv(List<Entry> entries, {required List<Category> categories, required List<Source> sources}) {
  final catName = {for (final c in categories) c.id: c.name};
  final srcName = {for (final s in sources) s.id: s.name};
  final stamp = DateFormat("yyyy-MM-dd'T'HH:mm:ss");
  String time(int ms) => stamp.format(DateTime.fromMillisecondsSinceEpoch(ms));

  final sorted = [...entries]..sort((a, b) {
      final byDay = b.occurredOn.compareTo(a.occurredOn);
      return byDay != 0 ? byDay : b.createdAt.compareTo(a.createdAt);
    });

  final lines = [
    csvColumns.join(csvSeparator),
    for (final e in sorted)
      [
        e.id,
        e.kind == EntryKind.expense ? 'gasto' : 'ingreso',
        '${e.amountCents}',
        '${e.amountCents ~/ 100}.${(e.amountCents % 100).toString().padLeft(2, '0')}',
        e.occurredOn,
        (e.kind == EntryKind.expense ? catName[e.categoryId] : srcName[e.sourceId]) ?? '',
        (e.kind == EntryKind.expense ? e.categoryId : e.sourceId) ?? '',
        e.note ?? '',
        e.origin.name,
        time(e.createdAt),
        time(e.updatedAt),
        e.accountLabel ?? '',
      ].map(_escape).join(csvSeparator),
  ];
  return '$_bom${lines.join('\r\n')}\r\n';
}

/// Entre comillas si el campo trae separador, comillas o saltos de línea.
String _escape(String v) =>
    v.contains(csvSeparator) || v.contains('"') || v.contains('\n') || v.contains('\r') ? '"${v.replaceAll('"', '""')}"' : v;

/// Escribe el CSV en un archivo temporal y abre el menú de compartir de Android.
/// Es un provider para poder simularlo en los tests (sin disco ni plataforma).
final csvExporterProvider = Provider<Future<void> Function(String csv, String fileName)>((_) => _shareCsv);

Future<void> _shareCsv(String csv, String fileName) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsBytes(utf8.encode(csv), flush: true);
  await SharePlus.instance.share(ShareParams(files: [XFile(file.path, mimeType: 'text/csv')], subject: fileName));
}
