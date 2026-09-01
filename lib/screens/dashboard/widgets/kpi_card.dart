import 'package:flutter/material.dart';

import '../../../models/management_dashboard_data.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/formatters.dart';

/// کارت یک KPI با نمایش صحیح null (—) در برابر صفر واقعی، به‌همراه درصد
/// تغییر نسبت به دوره قبل (اگر قابل‌محاسبه باشد).
class KpiCard extends StatelessWidget {
  final String title;
  final KpiValue kpi;
  final bool isPercentage;

  const KpiCard({super.key, required this.title, required this.kpi, this.isPercentage = false});

  String _formatValue(double? v) {
    if (v == null) return '—';
    return isPercentage ? '${v.toStringAsFixed(1)}٪' : formatMoney(v);
  }

  @override
  Widget build(BuildContext context) {
    final growth = kpi.growthRate;
    final growthColor = growth == null
        ? AppColors.textSecondary
        : (growth >= 0 ? AppColors.positive : AppColors.negative);
    final growthIcon = growth == null ? null : (growth >= 0 ? '▲' : '▼');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text(_formatValue(kpi.value),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            if (growth != null) ...[
              const SizedBox(height: 4),
              Text('$growthIcon ${growth.abs().toStringAsFixed(1)}٪',
                  style: TextStyle(fontSize: 12, color: growthColor, fontWeight: FontWeight.w700)),
            ],
          ],
        ),
      ),
    );
  }
}
