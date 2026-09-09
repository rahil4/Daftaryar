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

  Future<void> exportCounterpartyStatement({
    required String counterpartyName,
    String? counterpartyPhone,
    required List<Map<String, dynamic>> projectRows, // {title, agreedAmount, received, spent, remaining}
    required List<Map<String, dynamic>> transactions, // {date, description, type, amount}
  }) async {
    await _loadFonts();
    final totalAgreed = projectRows.fold<double>(0, (s, r) => s + (r['agreedAmount'] as num).toDouble());
    final totalReceived = projectRows.fold<double>(0, (s, r) => s + (r['received'] as num).toDouble());
    final totalRemaining = projectRows.fold<double>(0, (s, r) => s + (r['remaining'] as num).toDouble());

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
                _header('صورتحساب $counterpartyName', counterpartyPhone != null ? 'شماره تماس: $counterpartyPhone' : ''),
                pw.Text('تاریخ صدور: ${formatJalaliLong(todayJalaliString())}',
                    style: pw.TextStyle(font: _regularFont, fontSize: 9, color: PdfColors.grey600)),
                pw.SizedBox(height: 14),

                _sectionTitle('خلاصه پروژه‌ها'),
                pw.Table(
                  border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
                  columnWidths: const {
                    0: pw.FlexColumnWidth(2.2),
                    1: pw.FlexColumnWidth(1),
                    2: pw.FlexColumnWidth(1),
                    3: pw.FlexColumnWidth(1),
                  },
                  children: [
                    pw.TableRow(
                      decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                      children: [
                        _cell('پروژه', bold: true),
                        _cell('مبلغ قرارداد', bold: true),
                        _cell('دریافتی', bold: true),
                        _cell('باقی‌مانده', bold: true),
                      ],
                    ),
                    for (final r in projectRows)
                      pw.TableRow(children: [
                        _cell(r['title'] as String),
                        _cell(formatMoney((r['agreedAmount'] as num).toDouble(), withSuffix: false)),
                        _cell(formatMoney((r['received'] as num).toDouble(), withSuffix: false)),
                        _cell(formatMoney((r['remaining'] as num).toDouble(), withSuffix: false)),
                      ]),
                  ],
                ),
                pw.SizedBox(height: 10),
                _row('جمع مبلغ قرارداد', formatMoney(totalAgreed)),
                _row('جمع دریافتی', formatMoney(totalReceived)),
                _row('جمع باقی‌مانده', formatMoney(totalRemaining), bold: true),

                if (transactions.isNotEmpty) ...[
                  _sectionTitle('گردش تراکنش‌ها'),
                  _transactionsTable(transactions),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: 'صورتحساب_$counterpartyName.pdf');
  }

  /// صورتحساب مختص یک پروژه خاص - برخلاف exportCounterpartyStatement که
  /// همه پروژه‌های یک طرف‌حساب را با هم می‌آورد، این خروجی وقتی کاربر
  /// می‌خواهد فقط وضعیت مالی یک کار مشخص را برای همان کارفرما بفرستد
  /// (بدون افشای بقیه پروژه‌های او) استفاده می‌شود.
  Future<void> exportProjectStatement({
    required String projectTitle,
    required String counterpartyName,
    String? counterpartyPhone,
    required double agreedAmount,
    required double received,
    required List<Map<String, dynamic>> transactions, // {date, description, type, amount}
  }) async {
    await _loadFonts();
    final remaining = agreedAmount - received;

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
                _header('صورتحساب پروژه', projectTitle),
                pw.Text(
                    'کارفرما: $counterpartyName${counterpartyPhone != null ? ' — $counterpartyPhone' : ''}',
                    style: pw.TextStyle(font: _regularFont, fontSize: 10, color: PdfColors.grey700)),
                pw.Text('تاریخ صدور: ${formatJalaliLong(todayJalaliString())}',
                    style: pw.TextStyle(font: _regularFont, fontSize: 9, color: PdfColors.grey600)),
                pw.SizedBox(height: 14),
                _row('مبلغ قرارداد', formatMoney(agreedAmount)),
                _row('دریافتی', formatMoney(received)),
                _row('باقی‌مانده', formatMoney(remaining), bold: true),
                if (transactions.isNotEmpty) ...[
                  _sectionTitle('گردش تراکنش‌ها'),
                  _transactionsTable(transactions),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: 'صورتحساب_$projectTitle.pdf');
  }

  pw.Widget _transactionsTable(List<Map<String, dynamic>> transactions) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(1),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('تاریخ', bold: true),
            _cell('نوع', bold: true),
            _cell('شرح', bold: true),
            _cell('مبلغ', bold: true),
          ],
        ),
        for (final t in transactions)
          pw.TableRow(children: [
            _cell(formatJalaliLong(t['date'] as String)),
            _cell(t['type'] as String),
            _cell((t['description'] as String?) ?? '—'),
            _cell(formatMoney((t['amount'] as num).toDouble(), withSuffix: false)),
          ]),
      ],
    );
  }

  pw.Widget _cell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(text,
          style: pw.TextStyle(font: bold ? _boldFont : _regularFont, fontSize: 9.5),
          textAlign: pw.TextAlign.center),
    );
  }
}
