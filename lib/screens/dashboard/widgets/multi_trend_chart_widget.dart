import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/management_dashboard_data.dart';
import '../../../theme/app_theme.dart';

/// یک سری داده برای نمودار چندخطی
class ChartSeries {
  final String label;
  final List<TrendPoint> points;
  final Color color;
  const ChartSeries({required this.label, required this.points, required this.color});
}

/// نمودار مقایسه‌ای چندخطی - برای نمایش دو سری هم‌واحد (مثلاً درآمد
/// شناسایی‌شده در برابر دریافت نقدی) روی یک محور مشترک، تا شکاف بین آن‌ها
/// مستقیماً دیده شود نه با مقایسه ذهنی دو نمودار جدا.
///
/// فقط خط رسم می‌شود (بدون پرکردن ناحیه زیر خط) چون با دو ناحیه نیمه‌شفاف
/// روی هم، دقیقاً محل تقاطع - که مهم‌ترین نقطه نمودار است - گل‌آلود می‌شود.
///
/// نقاط null (غیرقابل‌محاسبه) به‌جای صفر، از نمودار حذف می‌شوند تا خط را
/// به‌اشتباه به سمت صفر نکشند.
class MultiTrendChartWidget extends StatelessWidget {
  final String title;
  final List<ChartSeries> series;

  const MultiTrendChartWidget({super.key, required this.title, required this.series});

  @override
  Widget build(BuildContext context) {
    // برچسب‌های محور افقی از اولین سری‌ای که داده دارد گرفته می‌شود؛ همه
    // سری‌ها از یک مجموعه Bucket ماهانه می‌آیند پس هم‌ترازند.
    final labels = series.isEmpty ? <String>[] : series.first.points.map((p) => p.label).toList();

    final barsData = <LineChartBarData>[];
    var hasAnyData = false;
    for (final s in series) {
      final valid = <int, double>{};
      for (var i = 0; i < s.points.length; i++) {
        if (s.points[i].value != null) valid[i] = s.points[i].value!;
      }
      if (valid.isNotEmpty) hasAnyData = true;
      barsData.add(LineChartBarData(
        spots: valid.entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
        isCurved: true,
        color: s.color,
        barWidth: 2.5,
        dotData: const FlDotData(show: true),
        belowBarData: BarAreaData(show: false),
      ));
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
                            height: 3,
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
                height: 150,
                child: Padding(
                  // لیبل ماه اول و آخر دقیقاً روی لبه نمودار قرار می‌گیرند
                  // و بدون این حاشیه، از کارت بیرون زده و بریده می‌شوند.
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: LineChart(
                    LineChartData(
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
                      lineBarsData: barsData,
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
