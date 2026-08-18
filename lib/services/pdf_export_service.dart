import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../utils/formatters.dart';

/// خروجی PDF از گزارش‌های حسابداری، با فونت فارسی وزیرمتن و چیدمان راست‌به‌چپ
class PdfExportService {
  pw.Font? _regularFont;
  pw.Font? _boldFont;

  Future<void> _loadFonts() async {
    if (_regularFont != null) return;
    final regularData = await rootBundle.load('assets/fonts/Vazirmatn-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Vazirmatn-Bold.ttf');
    _regularFont = pw.Font.ttf(regularData);
    _boldFont = pw.Font.ttf(boldData);
  }

  pw.Widget _header(String title, String subtitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text('دفتریار', style: pw.TextStyle(font: _regularFont, fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text(title, style: pw.TextStyle(font: _boldFont, fontSize: 18)),
        pw.SizedBox(height: 2),
        pw.Text(subtitle, style: pw.TextStyle(font: _regularFont, fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 14),
        pw.Divider(color: PdfColors.grey400),
      ],
    );
  }

  pw.Widget _row(String label, String value, {bool bold = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.6)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: bold ? _boldFont : _regularFont, fontSize: bold ? 12 : 11)),
          pw.Text(value, style: pw.TextStyle(font: bold ? _boldFont : _regularFont, fontSize: bold ? 12 : 11)),
        ],
      ),
    );
  }

  pw.Widget _sectionTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(text, style: pw.TextStyle(font: _boldFont, fontSize: 12, color: PdfColors.amber800)),
    );
  }

  Future<void> exportProfitLoss({
    required String fromDate,
    required String toDate,
    required Map<String, double> incomeLines,
    required Map<String, double> expenseLines,
  }) async {
    await _loadFonts();
    final totalIncome = incomeLines.values.fold<double>(0, (s, v) => s + v);
    final totalExpense = expenseLines.values.fold<double>(0, (s, v) => s + v);
    final net = totalIncome - totalExpense;

    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => pw.Directionality(
          textDirection: pw.TextDirection.rtl,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              _header('صورت سود و زیان', 'از ${formatJalaliLong(fromDate)} تا ${formatJalaliLong(toDate)}'),
              _sectionTitle('درآمدها'),
              ...incomeLines.entries.map((e) => _row(e.key, formatMoney(e.value))),
              _row('جمع درآمدها', formatMoney(totalIncome), bold: true),
              _sectionTitle('هزینه‌ها'),
              ...expenseLines.entries.map((e) => _row(e.key, formatMoney(e.value))),
              _row('جمع هزینه‌ها', formatMoney(totalExpense), bold: true),
              pw.SizedBox(height: 16),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(vertical: 10),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    top: pw.BorderSide(color: PdfColors.amber800, width: 1.4),
                    bottom: pw.BorderSide(color: PdfColors.amber800, width: 1.4),
                  ),
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(net >= 0 ? 'سود خالص' : 'زیان خالص', style: pw.TextStyle(font: _boldFont, fontSize: 13)),
                    pw.Text(formatMoney(net.abs()), style: pw.TextStyle(font: _boldFont, fontSize: 14)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: 'صورت_سود_و_زیان.pdf');
  }

  Future<void> exportTrialBalance({
    required List<Map<String, dynamic>> rows, // {name, type, debit, credit}
  }) async {
    await _loadFonts();
    final totalDebit = rows.fold<double>(0, (s, r) => s + (r['debit'] as double));
    final totalCredit = rows.fold<double>(0, (s, r) => s + (r['credit'] as double));

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => [
          pw.Directionality(
            textDirection: pw.TextDirection.rtl,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                _header('تراز آزمایشی', 'مانده تجمعی همه حساب‌ها تا امروز'),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(2.4),
                    1: pw.FlexColumnWidth(1),
                    2: pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('حساب', style: pw.TextStyle(font: _boldFont, fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('بدهکار', style: pw.TextStyle(font: _boldFont, fontSize: 10), textAlign: pw.TextAlign.center),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text('بستانکار', style: pw.TextStyle(font: _boldFont, fontSize: 10), textAlign: pw.TextAlign.center),
                        ),
                      ],
                    ),
                    for (final r in rows)
                      pw.TableRow(children: [
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(r['name'] as String, style: pw.TextStyle(font: _regularFont, fontSize: 10)),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            (r['debit'] as double) != 0 ? formatMoney(r['debit'] as double, withSuffix: false) : '—',
                            style: pw.TextStyle(font: _regularFont, fontSize: 10),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                        pw.Padding(
                          padding: const pw.EdgeInsets.all(6),
                          child: pw.Text(
                            (r['credit'] as double) != 0 ? formatMoney(r['credit'] as double, withSuffix: false) : '—',
                            style: pw.TextStyle(font: _regularFont, fontSize: 10),
                            textAlign: pw.TextAlign.center,
                          ),
                        ),
                      ]),
                  ],
                ),
                pw.SizedBox(height: 14),
                _row('جمع کل بدهکار', formatMoney(totalDebit), bold: true),
                _row('جمع کل بستانکار', formatMoney(totalCredit), bold: true),
              ],
            ),
          ),
        ],
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: 'تراز_آزمایشی.pdf');
  }
}
