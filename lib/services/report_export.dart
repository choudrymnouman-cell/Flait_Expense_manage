import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/flat_models.dart';
import '../state/app_state.dart';

String csvCell(String input) {
  final safe = RegExp(r'^\s*[=+\-@\t\r]').hasMatch(input) ? "'$input" : input;
  return '"${safe.replaceAll('"', '""')}"';
}

Future<void> exportReport(FlaitState state, List<ExpenseRequest> expenses,
    {bool pdf = false}) async {
  final rows = [
    [
      'Date',
      'Title',
      'Member',
      'Category',
      'Amount (${state.currency})',
      'Status'
    ],
    for (final e in expenses)
      [
        e.createdAt.toLocal().toIso8601String(),
        e.title,
        state.memberName(e.requesterId),
        e.category,
        e.amount.toStringAsFixed(2),
        e.cancelled ? 'cancelled' : e.status.name
      ]
  ];
  Uint8List bytes;
  if (pdf) {
    final font =
        pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
    final arabic = pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'));
    final doc = pw.Document(
        theme: pw.ThemeData.withFont(base: font, fontFallback: [arabic]));
    doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        maxPages: 300,
        build: (_) => [
              pw.Text('Flait expense report',
                  style: const pw.TextStyle(fontSize: 22)),
              pw.Text(state.flatName),
              pw.Text(
                  'Exported ${DateTime.now().toLocal().toIso8601String()} | ${expenses.length} filtered records'),
              pw.Text('Confirmed approved/paid total: ${state.currency} ${(expenses.where((e) => !e.cancelled && [
                    ExpenseStatus.approved,
                    ExpenseStatus.paid
                  ].contains(e.status)).fold(0.0, (a, e) => a + e.amount)).toStringAsFixed(2)}'),
              pw.SizedBox(height: 12),
              pw.TableHelper.fromTextArray(
                  data: rows,
                  cellStyle: const pw.TextStyle(fontSize: 8),
                  headerStyle: const pw.TextStyle(fontSize: 9)),
              pw.Text(
                  'Pending requests are not confirmed spending. No bank transfer is performed by this app.'),
            ]));
    bytes = await doc.save();
  } else {
    bytes = Uint8List.fromList(utf8.encode(
        '\uFEFF${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}'));
  }
  await FilePicker.platform.saveFile(
      dialogTitle: 'Export filtered report',
      fileName: 'Flait-report.${pdf ? 'pdf' : 'csv'}',
      type: FileType.custom,
      allowedExtensions: [pdf ? 'pdf' : 'csv'],
      bytes: bytes);
}
