import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/management_dashboard_data.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/formatters.dart';

/// یک سری داده برای نمودار چندستونی
class ChartSeries {
  final String label;
  final List<TrendPoint> points;
  final Color color;
  const ChartSeries({required this.label, required this.points, required this.color});
}

/// نمودار مقایسه‌ای چندستونی (گروهی) - برای نمایش دو سری هم‌واحد (مثلاً
/// درآمد شناسایی‌شده در برابر دریافت نقدی) کنار هم در هر بازه، تا شکاف بین
/// آن‌ها مستقیماً دیده شود نه با مقایسه ذهنی دو نمودار جدا.
///
/// نقاط null (غیرقابل‌محاسبه) به‌جای صفر، از نمودار حذف می‌شوند تا یک ستون
/// صفر به‌اشتباه به‌جای «داده‌ای نیست» خوانده نشود.
class MultiTrendChartWidget extends StatelessWidget {
  final String title;
  final List<ChartSeries> series;

  const MultiTrendChartWidget({super.key, required this.title, required this.series});

  @override
  Widget build(BuildContext context) {
    // برچسب‌های محور افقی از اولین سری‌ای که داده دارد گرفته می‌شود؛ همه
    // سری‌ها از یک مجموعه Bucket ماهانه می‌آیند پس هم‌ترازند.
    final labels = series.isEmpty ? <String>[] : series.first.points.map((p) => p.label).toList();

    final maxIndex = labels.length;
    final groups = <BarChartGroupData>[];
    // نگاشت هر ستون داخل یک گروه به شناسه سری اصلی‌اش - چون وقتی یکی از
    // سری‌ها در یک نقطه null باشد، آن ستون اصلاً ساخته نمی‌شود و rodIndex
    // دیگر مستقیماً با ایندکس series یکی نیست.
    final groupSeriesIndices = <int, List<int>>{};
    var hasAnyData = false;
    for (var i = 0; i < maxIndex; i++) {
      final rods = <BarChartRodData>[];
      final seriesIdx = <int>[];
      for (var sIdx = 0; sIdx < series.length; sIdx++) {
        final v = i < series[sIdx].points.length ? series[sIdx].points[i].value : null;
        if (v == null) continue;
        hasAnyData = true;
        rods.add(BarChartRodData(
            toY: v, color: series[sIdx].color, width: 7, borderRadius: BorderRadius.circular(2)));
        seriesIdx.add(sIdx);
      }
      // مهم: باید برای هر Bucket - حتی وقتی هیچ سری‌ای مقدار ندارد - یک
      // BarChartGroupData ساخته شود (هرچند با barRods خالی)، نه اینکه از
      // لیست groups حذف شود. fl_chart موقعیت افقی هر ستون را صرفاً از روی
      // ترتیب/تعداد عناصر همین لیست (calculateGroupsX) حساب می‌کند، نه از
      // روی مقدار x - در حالی‌که برچسب‌های محور افقی مستقل و بر مبنای کل
      // بازه (0..maxIndex-1) چیده می‌شوند. اگر Bucketهای خالی حذف شوند، دو
      // مقیاس متفاوت پدید می‌آید و ستون‌ها زیر برچسب درست خودشان نمی‌افتند
      // (مثلاً یک ستون تنها، وسط نمودار، زیر برچسب اشتباه).
      groups.add(BarChartGroupData(
        x: i,
        barRods: rods,
        barsSpace: 4,
        showingTooltipIndicators: List.generate(rods.length, (i) => i),
      ));
      groupSeriesIndices[i] = seriesIdx;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 8),
            // راهنمای رنگ‌ها
            Wrap(
              spacing: 14,
              runSpacing: 4,
              children: series
                  .map((s) => Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration:
                                BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(2)),
                          ),
                          const SizedBox(width: 5),
                          Text(s.label,
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                        ],
                      ))
                  .toList(),
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
                // کمی بلندتر از قبل چون حالا مقدار هر ستون همیشه بالای
                // خودش نوشته می‌شود (نه فقط با لمس) و به فضا نیاز دارد.
                height: 170,
                child: Padding(
                  // لیبل ماه اول و آخر دقیقاً روی لبه نمودار قرار می‌گیرند
                  // و بدون این حاشیه، از کارت بیرون زده و بریده می‌شوند.
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: BarChart(
                    BarChartData(
                      gridData: const FlGridData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            // نام ماه‌های فارسی («اردیبهشت») چند برابر معادل
                            // لاتین عرض می‌گیرند. بدون تعیین interval،
                            // fl_chart برای هر نقطه یک برچسب می‌گذارد و روی
                            // عرض موبایل همه در هم می‌روند.
                            interval: labels.length <= 4 ? 1 : (labels.length / 4).ceilToDouble(),
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= labels.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(
                                  labels[idx].split(' ').first,
                                  maxLines: 1,
                                  style: const TextStyle(fontSize: 9, color: AppColors.textSecondary),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: groups,
                      // مقدار هر ستون همیشه بالای خودش نمایش داده می‌شود
                      // (showingTooltipIndicators در ساخت groups) - نه فقط
                      // با لمس؛ برای همین برچسب کوتاه و فشرده (فقط مبلغ) با
                      // رنگ سری است، نه توضیح کامل تاریخ/نام سری که برای
                      // چند برچسب هم‌زمان روی نمودار شلوغ می‌شود.
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) => Colors.transparent,
                          tooltipPadding: EdgeInsets.zero,
                          tooltipMargin: 4,
                          fitInsideHorizontally: true,
                          fitInsideVertically: true,
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final idx = group.x;
                            final seriesIdxList = groupSeriesIndices[idx] ?? const [];
                            final s = rodIndex < seriesIdxList.length
                                ? series[seriesIdxList[rodIndex]]
                                : series.first;
                            return BarTooltipItem(
                              formatMoneyCompact(rod.toY),
                              TextStyle(color: s.color, fontWeight: FontWeight.w800, fontSize: 9),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
