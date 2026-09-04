import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../models/management_dashboard_data.dart';
import '../../../theme/app_theme.dart';

/// نمودار روند ماهانه ساده - نقاط null (غیرقابل‌محاسبه) به‌جای صفر، از
/// نمودار حذف می‌شوند تا خط را به‌اشتباه به سمت صفر نکشند.
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
                    lineBarsData: [
                      LineChartBarData(
                        spots: validPoints.entries.map((e) => FlSpot(e.key.toDouble(), e.value)).toList(),
                        isCurved: true,
                        color: color,
                        barWidth: 2.5,
                        dotData: const FlDotData(show: true),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
