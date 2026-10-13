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
  // 4A (O2): la cuenta de cada fila; en una transferencia, account_* es el
  // origen y to_account_* el destino.
  'account_id',
  'account_name',
  'to_account_id',
  'to_account_name',
];

String csvFileName(DateTime today) => 'saldoclaro-movimientos-${isoDay(today)}.csv';

/// Todos los movimientos (y las transferencias, como filas `transferencia`),
/// del más nuevo al más viejo. Incluye nombres de categorías/fuentes/cuentas
/// archivadas. Fin de línea CRLF (RFC 4180, Excel). Sin cuentas, las columnas
/// de cuenta van vacías; con cuentas, "Sin asignar" es id vacío y ese nombre.
String entriesToCsv(
  List<Entry> entries, {
  required List<Category> categories,
  required List<Source> sources,
  List<Account> accounts = const [],
  List<TransferRow> transfers = const [],
}) {
  final catName = {for (final c in categories) c.id: c.name};
  final srcName = {for (final s in sources) s.id: s.name};
  final accName = {for (final a in accounts) a.id: a.name};
  final stamp = DateFormat("yyyy-MM-dd'T'HH:mm:ss");
  String time(int ms) => stamp.format(DateTime.fromMillisecondsSinceEpoch(ms));
  String amount(int c) => '${c ~/ 100}.${(c % 100).toString().padLeft(2, '0')}';
  String accountName(String? id) => id == null ? (accounts.isEmpty ? '' : 'Sin asignar') : accName[id] ?? '';

  final sorted = <Object>[...entries, ...transfers]..sort((a, b) {
      String day(Object x) => x is Entry ? x.occurredOn : (x as TransferRow).occurredOn;
      int created(Object x) => x is Entry ? x.createdAt : (x as TransferRow).createdAt;
      final byDay = day(b).compareTo(day(a));
      return byDay != 0 ? byDay : created(b).compareTo(created(a));
    });

  List<String> transferRow(TransferRow t) => [
        t.id,
        'transferencia',
        '${t.amountCents}',
        amount(t.amountCents),
        t.occurredOn,
        '',
        '',
        t.note ?? '',
        'manual',
        time(t.createdAt),
        time(t.updatedAt),
        '',
        t.fromAccountId ?? '',
        t.fromAccountId == null ? 'Sin asignar' : accName[t.fromAccountId] ?? '',
        t.toAccountId ?? '',
        t.toAccountId == null ? 'Sin asignar' : accName[t.toAccountId] ?? '',
      ];

  final lines = [
    csvColumns.join(csvSeparator),
    for (final x in sorted)
      if (x is TransferRow)
        transferRow(x).map(_escape).join(csvSeparator)
      else if (x case final Entry e)
      [
        e.id,
        e.kind == EntryKind.expense ? 'gasto' : 'ingreso',
        '${e.amountCents}',
        amount(e.amountCents),
        e.occurredOn,
        (e.kind == EntryKind.expense ? catName[e.categoryId] : srcName[e.sourceId]) ?? '',
        (e.kind == EntryKind.expense ? e.categoryId : e.sourceId) ?? '',
        e.note ?? '',
        e.origin.name,
        time(e.createdAt),
        time(e.updatedAt),
        e.accountLabel ?? '',
        e.accountId ?? '',
        accountName(e.accountId),
        '',
        '',
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
