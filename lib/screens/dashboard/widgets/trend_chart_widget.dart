import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/management_dashboard_data.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/formatters.dart';

/// نمودار روند ماهانه ستونی - نقاط null (غیرقابل‌محاسبه) به‌جای صفر، از
/// نمودار حذف می‌شوند تا یک ستون صفر به‌اشتباه به‌جای «داده‌ای نیست» خوانده نشود.
class TrendChartWidget extends StatelessWidget {
  final String title;
  final List<TrendPoint> points;
  final Color color;

  const TrendChartWidget({super.key, required this.title, required this.points, this.color = AppColors.brass});

  @override
  Widget build(BuildContext context) {
    final validPoints = <int, double>{};
    for (var i = 0; i < points.length; i++) {
      if (points[i].value != null) validPoints[i] = points[i].value!;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            const SizedBox(height: 10),
            if (points.isEmpty || validPoints.isEmpty)
              const SizedBox(
                height: 100,
                child: Center(
                  child: Text('داده کافی برای رسم نمودار در این بازه وجود ندارد.',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
              )
            else
              SizedBox(
                height: 140,
                child: Padding(
                  // لیبل ماه اول و آخر روی لبه نمودار قرار می‌گیرند و بدون
                  // این حاشیه از کارت بیرون زده و بریده می‌شوند.
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
                            // نام ماه‌های فارسی چند برابر معادل لاتین عرض
                            // می‌گیرند؛ بدون interval، برچسب‌ها روی عرض
                            // موبایل در هم می‌روند.
                            interval: points.length <= 4 ? 1 : (points.length / 4).ceilToDouble(),
                            reservedSize: 28,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= points.length) return const SizedBox.shrink();
                              return Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text(points[idx].label.split(' ').first,
                                    maxLines: 1,
                                    style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
                              );
                            },
                          ),
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: validPoints.entries
                          .map((e) => BarChartGroupData(
                                x: e.key,
                                barRods: [
                                  BarChartRodData(
                                    toY: e.value,
                                    color: color,
                                    width: 10,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ],
                              ))
                          .toList(),
                      // نمایش جزئیات با لمس: تاریخ + مقدار دقیق همان ستون.
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final idx = group.x;
                            final label = idx >= 0 && idx < points.length ? points[idx].label : '';
                            return BarTooltipItem(
                              '$label\n${formatMoney(rod.toY, withSuffix: false)}',
                              TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
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
