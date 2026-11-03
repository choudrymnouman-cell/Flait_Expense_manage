import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../offline/secure_book.dart';
import 'monthly_state.dart';

Future<Uint8List> monthlyPdf(MonthlyState state, String month) async {
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
  );
  final arabic = pw.Font.ttf(
    await rootBundle.load('assets/fonts/NotoNaskhArabic-Regular.ttf'),
  );
  final report = pw.Document(
    theme: pw.ThemeData.withFont(base: font, fontFallback: [arabic]),
  );
  final salary = state.salary(month);
  final total = state.spent(month);
  report.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      maxPages: 300,
      build: (_) => [
        pw.Text('Expense Manage', style: const pw.TextStyle(fontSize: 20)),
        pw.Text('${state.profile.identity!.name}  |  $month'),
        pw.SizedBox(height: 16),
        pw.Text('Salary: ${rupees(salary)}'),
        pw.Text('Monthly expenses: ${rupees(total)}'),
        pw.Text('Remaining: ${rupees(salary - total)}'),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          data: [
            ['Section', 'Entry', 'Salary impact'],
            for (final row in state.lines(month))
              [row.section, row.title, rupees(row.cents)],
          ],
        ),
        for (final flat in state.ofKind('flat')) ...[
          pw.SizedBox(height: 14),
          pw.Text(flat.flatName),
          pw.TableHelper.fromTextArray(
            data: [
              ['Flat item', 'Amount', 'Status'],
              for (final row in flat.view!.monthly.values.where(
                (r) => r['type'] == 'item' && r['month'] == month,
              ))
                [
                  row['title'],
                  rupees(row['cents'] as int),
                  row['approved'] == true ? 'Approved' : 'Pending',
                ],
            ],
          ),
        ],
      ],
    ),
  );
  return report.save();
}

Future<void> exportMonth(MonthlyState state, String month) async {
  await FilePicker.platform.saveFile(
    dialogTitle: 'Export monthly report',
    fileName: 'Expense-Manage-$month.pdf',
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    bytes: await monthlyPdf(state, month),
  );
}

Future<void> saveClosedReports(MonthlyState state) async {
  if (!Platform.isAndroid || state.profile.identity == null) return;
  final directory = await getApplicationSupportDirectory();
  for (final month in state.reportMonths.where(
    (m) => m.compareTo(state.currentMonth) < 0,
  )) {
    final version = await digest([
      state.salary(month),
      for (final row in state.lines(month)) [row.section, row.title, row.cents],
      for (final group in state.ofKind('flat'))
        for (final row in group.view!.monthly.values.where(
          (r) => r['month'] == month,
        ))
          row,
    ]);
    final file = File('${directory.path}/Expense-Manage-$month.pdf');
    final marker = File('${file.path}.revision');
    if (await file.exists() &&
        await marker.exists() &&
        await marker.readAsString() == version) {
      continue;
    }
    final pending = File('${file.path}.pending');
    await pending.writeAsBytes(await monthlyPdf(state, month), flush: true);
    await pending.rename(file.path);
    await marker.writeAsString(version, flush: true);
    await MonthlyState.notifications.invokeMethod<void>('show', {
      'id': 'report-$month',
      'title': 'Monthly report ready',
      'body': month,
    });
  }
}
