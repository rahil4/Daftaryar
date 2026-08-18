import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/formatters.dart';

/// خروجی اکسل (xlsx) از گزارش‌های حسابداری برای استفاده حسابدار یا اظهارنامه مالیاتی
class ExcelExportService {
  Future<void> _shareWorkbook(Excel excel, String filename) async {
    final bytes = excel.encode();
    if (bytes == null) return;
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], text: filename);
  }

  Future<void> exportProfitLoss({
    required String fromDate,
    required String toDate,
    required Map<String, double> incomeLines,
    required Map<String, double> expenseLines,
  }) async {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];

    void addRow(List<dynamic> cells, {bool bold = false}) {
      final rowIndex = sheet.maxRows;
      for (int i = 0; i < cells.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIndex));
        cell.value = cells[i] is num ? DoubleCellValue((cells[i] as num).toDouble()) : TextCellValue(cells[i].toString());
        if (bold) cell.cellStyle = CellStyle(bold: true);
      }
    }

    addRow(['صورت سود و زیان'], bold: true);
    addRow(['از ${formatJalaliLong(fromDate)} تا ${formatJalaliLong(toDate)}']);
    addRow([]);
    addRow(['درآمدها'], bold: true);
    final totalIncome = incomeLines.values.fold<double>(0, (s, v) => s + v);
    for (final e in incomeLines.entries) {
      addRow([e.key, e.value]);
    }
    addRow(['جمع درآمدها', totalIncome], bold: true);
    addRow([]);
    addRow(['هزینه‌ها'], bold: true);
    final totalExpense = expenseLines.values.fold<double>(0, (s, v) => s + v);
    for (final e in expenseLines.entries) {
      addRow([e.key, e.value]);
    }
    addRow(['جمع هزینه‌ها', totalExpense], bold: true);
    addRow([]);
    addRow([totalIncome - totalExpense >= 0 ? 'سود خالص' : 'زیان خالص', (totalIncome - totalExpense).abs()], bold: true);

    await _shareWorkbook(excel, 'صورت_سود_و_زیان.xlsx');
  }

  Future<void> exportTrialBalance(List<Map<String, dynamic>> rows) async {
    final excel = Excel.createExcel();
    final sheet = excel[excel.getDefaultSheet()!];

    void addRow(List<dynamic> cells, {bool bold = false}) {
      final rowIndex = sheet.maxRows;
      for (int i = 0; i < cells.length; i++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: rowIndex));
        cell.value = cells[i] is num ? DoubleCellValue((cells[i] as num).toDouble()) : TextCellValue(cells[i].toString());
        if (bold) cell.cellStyle = CellStyle(bold: true);
      }
    }

    addRow(['تراز آزمایشی'], bold: true);
    addRow([]);
    addRow(['حساب', 'بدهکار', 'بستانکار'], bold: true);
    double totalDebit = 0, totalCredit = 0;
    for (final r in rows) {
      final debit = r['debit'] as double;
      final credit = r['credit'] as double;
      totalDebit += debit;
      totalCredit += credit;
      addRow([r['name'], debit, credit]);
    }
    addRow([]);
    addRow(['جمع کل', totalDebit, totalCredit], bold: true);

    await _shareWorkbook(excel, 'تراز_آزمایشی.xlsx');
  }
}
