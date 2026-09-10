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

  /// فونت وزیرمتن embed‌شده در PDF برای نیم‌فاصله (ZWNJ) گلیف تعریف‌شده‌ای
  /// ندارد؛ به‌جای پهن‌ندادن نامرئی (رفتار مورد انتظار)، یک نماد غیرمنتظره
  /// رسم می‌کند. چون این کاراکتر در متن فارسی رایج است («پروژه‌ها»،
  /// «باقی‌مانده»، ...)، هر متنی که وارد PDF می‌شود از این تابع رد می‌شود؛
  /// جایگزین کردن با یک فاصله معمولی، جدایی بصری کلمه را حفظ می‌کند بدون
  /// نمایش گلیف نادرست.
  String _clean(String s) => s.replaceAll('‌', ' ').replaceAll('‍', '');

  pw.Widget _header(String title, String subtitle) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Text('دفتریار', style: pw.TextStyle(font: _regularFont, fontSize: 10, color: PdfColors.grey600)),
        pw.SizedBox(height: 4),
        pw.Text(_clean(title), style: pw.TextStyle(font: _boldFont, fontSize: 18)),
        pw.SizedBox(height: 2),
        pw.Text(_clean(subtitle),
            style: pw.TextStyle(font: _regularFont, fontSize: 10, color: PdfColors.grey600)),
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
          pw.Text(_clean(label),
              style: pw.TextStyle(font: bold ? _boldFont : _regularFont, fontSize: bold ? 12 : 11)),
          pw.Text(_clean(value),
              style: pw.TextStyle(font: bold ? _boldFont : _regularFont, fontSize: bold ? 12 : 11)),
        ],
      ),
    );
  }

  pw.Widget _sectionTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child:
          pw.Text(_clean(text), style: pw.TextStyle(font: _boldFont, fontSize: 12, color: PdfColors.amber800)),
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
  ///
  /// عمداً از همان اعداد summary (projectFinancialSummary) استفاده می‌کند
  /// که تب «خلاصه و مالی» خودِ برنامه نشان می‌دهد - نه agreedAmount خام که
  /// قبلاً استفاده می‌شد و با تغییر مبلغ برآوردی/نهایی‌سازی/تخفیف همگام
  /// نبود. فهرست تراکنش‌ها هم عمداً receipts (فقط دریافت‌های نقدی واقعی)
  /// است، نه سطرهای خام دفترکل - کارفرما نباید سند سیستمیِ «شناسایی
  /// درآمد»/«انتقال پیش‌دریافت» را ببیند.
  Future<void> exportProjectStatement({
    required String projectTitle,
    required String counterpartyName,
    String? counterpartyPhone,
    required Map<String, dynamic> summary,
    required List<Map<String, dynamic>> receipts, // {date, description, amount} - فقط دریافت نقدی
    required List<Map<String, dynamic>> expenses, // {date, description, amount} - فقط هزینه مستقیم پروژه
  }) async {
    await _loadFonts();
    final isFinalized = summary['isFinalized'] as bool;
    final initialEstimate = summary['initialEstimate'] as double;
    final currentExpected = summary['currentExpectedAmount'] as double?;
    final grossFinalAmount = summary['grossFinalAmount'] as double?;
    final discount = summary['discount'] as double? ?? 0;
    final netRevenue = summary['netRevenue'] as double?;
    final totalReceived = summary['totalReceived'] as double? ?? 0;
    final receivable = summary['receivable'] as double? ?? 0;
    final customerCredit = summary['customerCredit'] as double? ?? 0;
    final directProjectCost = summary['directProjectCost'] as double? ?? 0;

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
                if (!isFinalized)
                  _row('مبلغ برآوردی فعلی', formatMoney(currentExpected ?? initialEstimate))
                else ...[
                  _row('مبلغ نهایی قرارداد', formatMoney(grossFinalAmount ?? 0)),
                  if (discount > 0) _row('تخفیف', '- ${formatMoney(discount)}'),
                  _row('مبلغ نهایی پس از تخفیف', formatMoney(netRevenue ?? 0), bold: true),
                ],
                _row('دریافتی تاکنون', formatMoney(totalReceived)),
                _row('هزینه مستقیم پروژه', formatMoney(directProjectCost)),
                if (customerCredit > 0)
                  _row('بستانکاری (مازاد دریافتی)', formatMoney(customerCredit), bold: true)
                else
                  _row(
                    isFinalized ? 'مانده طلب' : 'مانده تخمینی',
                    formatMoney(isFinalized
                        ? receivable
                        : (currentExpected ?? initialEstimate) - totalReceived),
                    bold: true,
                  ),
                if (receipts.isNotEmpty) ...[
                  _sectionTitle('گردش دریافت‌ها'),
                  _amountTable(receipts),
                ],
                if (expenses.isNotEmpty) ...[
                  _sectionTitle('هزینه‌های پروژه'),
                  _amountTable(expenses),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    await Printing.sharePdf(bytes: await doc.save(), filename: 'صورتحساب_$projectTitle.pdf');
  }

  pw.Widget _amountTable(List<Map<String, dynamic>> rows) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(1.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey200),
          children: [
            _cell('تاریخ', bold: true),
            _cell('شرح', bold: true),
            _cell('مبلغ', bold: true),
          ],
        ),
        for (final r in rows)
          pw.TableRow(children: [
            _cell(formatJalaliLong(r['date'] as String)),
            _cell((r['description'] as String?) ?? '—'),
            _cell(formatMoney((r['amount'] as num).toDouble(), withSuffix: false)),
          ]),
      ],
    );
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
      child: pw.Text(_clean(text),
          style: pw.TextStyle(font: bold ? _boldFont : _regularFont, fontSize: 9.5),
          textAlign: pw.TextAlign.center),
    );
  }
}
