import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/management_dashboard_data.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/metric_strip.dart';

/// نمودار ترکیبی درآمد/هزینه/دریافتی داشبورد - دو سری تعهدی (درآمد، هزینه)
/// به‌صورت ستون کنار هم، و دریافتی نقدی به‌صورت خط روی همان نمودار؛ با محور
/// Y واقعی (خط‌های راهنما + مقیاس عددی) و مقدار همیشه‌نمایان روی هر ستون/نقطه.
///
/// عمداً با CustomPainter دستی رسم می‌شود، نه ترکیب BarChart+LineChart از
/// fl_chart روی هم (تکنیک رایج ولی شکننده - چون BarChart موقعیت افقی
/// ستون‌ها را از روی تعداد عناصر لیست حساب می‌کند، نه مقدار x واقعی، در
/// حالی‌که LineChart از مختصات پیوسته واقعی استفاده می‌کند؛ هم‌ترازکردن دقیق
/// این دو مقیاس متفاوت دقیقاً همان کلاس باگی است که قبلاً در همین نمودار
/// رفع شد). رسم دستی یعنی موقعیت ستون‌ها و نقاط خط از یک منبع واحد محاسبه
/// می‌شوند و هرگز از هم جدا نمی‌افتند.
///
/// جهت محور افقی: چپ‌به‌راست بر حسب زمان - قدیمی‌ترین Bucket سمت چپ،
/// جدیدترین سمت راست (رایج‌ترین جهت نمودارهای زمانی، طبق درخواست صریح
/// کاربر؛ نسخه قبلی این نمودار عمداً برعکس بود، اما آن تصمیم با این
/// درخواست جایگزین شد).
///
/// [caption] زیرنویس زیر کل محور افقی - سطح هفته: «هفته N | تاریخ تا
/// تاریخ»، سطح ماه: «نام‌ماه سال»، سطح فصل/سال: «سال سال» - از
/// DashboardPeriodResolver.buildAxisPlan می‌آید.
class ComboTrendChartWidget extends StatelessWidget {
  final String title;
  final List<TrendPoint> income;
  final List<TrendPoint> expense;
  final List<TrendPoint> receipts;
  final String? caption;

  /// جمع دریافتی نقدی بازه - کنار برچسب «دریافتی» در راهنمای نمودار نمایش
  /// داده می‌شود (درآمد و هزینه بازه در ردیف شاخص‌های بالای نمودار هستند).
  final double? receiptsTotal;

  const ComboTrendChartWidget({
    super.key,
    required this.title,
    required this.income,
    required this.expense,
    required this.receipts,
    this.caption,
    this.receiptsTotal,
  });

  /// رنگ خط دریافتی: خنثی و روشن، تا از دو سری ستونی (برنزی/آبی) جدا بماند
  /// و معنای «خوب/بد» القا نکند.
  static const Color receiptsColor = AppColors.textPrimary;

  @override
  Widget build(BuildContext context) {
    final count = [income.length, expense.length, receipts.length].fold(0, math.max);
    final hasAnyData = income.any((p) => p.value != null) ||
        expense.any((p) => p.value != null) ||
        receipts.any((p) => p.value != null);

    return SurfaceBox(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(caption == null ? title : '$title · $caption',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: [
                const _LegendDot(color: AppColors.chartIncome, label: 'درآمد'),
                const _LegendDot(color: AppColors.chartExpense, label: 'هزینه'),
                _LegendLine(
                  color: receiptsColor,
                  label: receiptsTotal == null
                      ? 'دریافتی نقدی'
                      : 'دریافتی نقدی ${formatMoney(receiptsTotal!, withSuffix: false)}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!hasAnyData)
              const SizedBox(
                height: 100,
                child: Center(
                  child: Text('داده کافی برای رسم نمودار در این بازه وجود ندارد.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
              )
            else
              SizedBox(
                height: 230,
                width: double.infinity,
                child: CustomPaint(
                  painter: _ComboChartPainter(
                    income: income,
                    expense: expense,
                    receipts: receipts,
                    count: count,
                  ),
                ),
              ),
          ],
        ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 5),
      // Flexible: در صفحه باریک یا فونت بزرگ، برچسب می‌شکند به‌جای بیرون‌زدن.
      Flexible(child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
    ]);
  }
}

class _LegendLine extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendLine({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 14, height: 2, color: color),
      const SizedBox(width: 4),
      Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      // Flexible: در صفحه باریک یا فونت بزرگ، برچسب می‌شکند به‌جای بیرون‌زدن.
      Flexible(child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
    ]);
  }
}

class _ComboChartPainter extends CustomPainter {
  final List<TrendPoint> income;
  final List<TrendPoint> expense;
  final List<TrendPoint> receipts;
  final int count;

  _ComboChartPainter({
    required this.income,
    required this.expense,
    required this.receipts,
    required this.count,
  });

  double? _valueAt(List<TrendPoint> series, int i) => i < series.length ? series[i].value : null;

  String _labelAt(int i) {
    if (i < income.length) return income[i].label;
    if (i < expense.length) return expense[i].label;
    if (i < receipts.length) return receipts[i].label;
    return '';
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (count == 0) return;

    double maxVal = 0;
    for (var i = 0; i < count; i++) {
      for (final v in [_valueAt(income, i), _valueAt(expense, i), _valueAt(receipts, i)]) {
        if (v != null && v > maxVal) maxVal = v;
      }
    }
    if (maxVal <= 0) maxVal = 1;
    final step = _niceStep(maxVal / 5);
    final axisMax = step * (maxVal / step).ceil();
    final tickCount = (axisMax / step).round().clamp(1, 10);

    const labelStyle = TextStyle(fontSize: 9, color: AppColors.textSecondary);
    const leftAxisWidth = 50.0;
    const bottomLabelHeight = 20.0;
    const topPad = 20.0;
    const plotLeft = leftAxisWidth;
    final plotRight = size.width;
    const plotTop = topPad;
    final plotBottom = size.height - bottomLabelHeight;
    final plotWidth = plotRight - plotLeft;
    final plotHeight = plotBottom - plotTop;
    if (plotWidth <= 0 || plotHeight <= 0) return;

    final gridPaint = Paint()
      ..color = AppColors.gridLine.withValues(alpha: 0.6)
      ..strokeWidth = 0.6;

    final basePaint = Paint()
      ..color = AppColors.lineStrong
      ..strokeWidth = 1;

    for (var t = 0; t <= tickCount; t++) {
      final value = step * t;
      final y = plotBottom - (value / axisMax) * plotHeight;
      canvas.drawLine(Offset(plotLeft, y), Offset(plotRight, y), t == 0 ? basePaint : gridPaint);
      _drawText(
        canvas,
        value == 0 ? '۰' : formatMoneyCompact(value),
        Offset(leftAxisWidth - 6, y),
        const TextStyle(fontSize: 9, color: AppColors.textSecondary),
        align: TextAlign.right,
        anchorY: 0.5,
        maxWidth: leftAxisWidth - 6,
      );
    }

    final slotWidth = plotWidth / count;
    final barWidth = math.min(16.0, slotWidth * 0.26);
    const barGap = 2.0;

    final linePoints = <Offset?>[];

    for (var i = 0; i < count; i++) {
      // i=۰ قدیمی‌ترین Bucket است و سمت چپ می‌افتد، i=count-1 (جدیدترین)
      // سمت راست - جهت زمانی چپ‌به‌راست.
      final slot = i;
      final centerX = plotLeft + (slot + 0.5) * slotWidth;

      final incomeV = _valueAt(income, i);
      if (incomeV != null) {
        final h = (incomeV / axisMax) * plotHeight;
        final barLeft = centerX - barGap / 2 - barWidth;
        final rect = Rect.fromLTWH(barLeft, plotBottom - h, barWidth, h);
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
          Paint()..color = AppColors.chartIncome,
        );
        _drawText(canvas, formatMoneyCompact(incomeV), Offset(barLeft + barWidth / 2, plotBottom - h - 4),
            const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            anchorY: 1);
      }

      final expenseV = _valueAt(expense, i);
      if (expenseV != null) {
        final h = (expenseV / axisMax) * plotHeight;
        final barLeft = centerX + barGap / 2;
        final rect = Rect.fromLTWH(barLeft, plotBottom - h, barWidth, h);
        canvas.drawRRect(
          RRect.fromRectAndCorners(rect, topLeft: const Radius.circular(4), topRight: const Radius.circular(4)),
          Paint()..color = AppColors.chartExpense,
        );
        _drawText(canvas, formatMoneyCompact(expenseV), Offset(barLeft + barWidth / 2, plotBottom - h - 4),
            const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            anchorY: 1);
      }

      final receiptV = _valueAt(receipts, i);
      linePoints.add(receiptV != null ? Offset(centerX, plotBottom - (receiptV / axisMax) * plotHeight) : null);

      _drawText(canvas, _labelAt(i), Offset(centerX, plotBottom + 6), labelStyle, anchorY: 0);
    }

    // خط دریافتی - پیوسته بین نقاط متوالی غیر-null، با شکست روی null
    // (بدون درون‌یابی ساختگی روی Bucketهای بدون داده).
    final linePaint = Paint()
      ..color = ComboTrendChartWidget.receiptsColor
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    Offset? prev;
    for (final p in linePoints) {
      if (p == null) {
        prev = null;
        continue;
      }
      if (prev != null) canvas.drawLine(prev, p, linePaint);
      prev = p;
    }
    for (var i = 0; i < linePoints.length; i++) {
      final p = linePoints[i];
      if (p == null) continue;
      canvas.drawCircle(p, 3.2, Paint()..color = ComboTrendChartWidget.receiptsColor);
      canvas.drawCircle(
          p, 3.2, Paint()..color = AppColors.surface..style = PaintingStyle.stroke..strokeWidth = 1.2);
      final v = _valueAt(receipts, i)!;
      _drawText(canvas, formatMoneyCompact(v), Offset(p.dx, p.dy - 8),
          const TextStyle(fontSize: 8.5, fontWeight: FontWeight.w700, color: ComboTrendChartWidget.receiptsColor),
          anchorY: 1);
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset pos,
    TextStyle style, {
    TextAlign align = TextAlign.center,
    double anchorY = 0.5,
    double? maxWidth,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: align,
      textDirection: TextDirection.rtl,
      maxLines: 1,
    )..layout(maxWidth: maxWidth ?? double.infinity);
    double dx;
    if (align == TextAlign.left) {
      dx = pos.dx;
    } else if (align == TextAlign.right) {
      dx = pos.dx - tp.width;
    } else {
      dx = pos.dx - tp.width / 2;
    }
    tp.paint(canvas, Offset(dx, pos.dy - tp.height * anchorY));
  }

  /// نزدیک‌ترین «عدد گرد» بزرگ‌تر یا مساوی roughStep (الگوی ۱/۲/۵ × ۱۰^k) -
  /// برای این‌که خط‌های راهنمای محور Y روی اعدادی مثل ۵۰,۰۰۰,۰۰۰ بیفتند،
  /// نه اعداد عجیب مثل ۴۳,۷۵۰,۰۰۰.
  double _niceStep(double roughStep) {
    if (roughStep <= 0) return 1;
    final magnitude = math.pow(10, (math.log(roughStep) / math.ln10).floor()).toDouble();
    final residual = roughStep / magnitude;
    double niceResidual;
    if (residual <= 1) {
      niceResidual = 1;
    } else if (residual <= 2) {
      niceResidual = 2;
    } else if (residual <= 5) {
      niceResidual = 5;
    } else {
      niceResidual = 10;
    }
    return niceResidual * magnitude;
  }

  @override
  bool shouldRepaint(covariant _ComboChartPainter oldDelegate) {
    return oldDelegate.income != income ||
        oldDelegate.expense != expense ||
        oldDelegate.receipts != receipts ||
        oldDelegate.count != count;
  }
}
