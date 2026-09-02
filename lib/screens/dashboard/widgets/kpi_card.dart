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
  final bool emphasized;
  final VoidCallback? onTap;

  const KpiCard(
      {super.key,
      required this.title,
      required this.kpi,
      this.isPercentage = false,
      this.emphasized = false,
      this.onTap});

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

    final body = Padding(
      padding: EdgeInsets.all(emphasized ? 16 : 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: emphasized ? 12.5 : 12,
                  color: emphasized ? AppColors.brass : AppColors.textSecondary,
                  fontWeight: emphasized ? FontWeight.w700 : FontWeight.normal)),
          SizedBox(height: emphasized ? 8 : 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(_formatValue(kpi.value),
                style: TextStyle(fontSize: emphasized ? 24 : 18, fontWeight: FontWeight.w800)),
          ),
          if (growth != null) ...[
            const SizedBox(height: 4),
            Text('$growthIcon ${growth.abs().toStringAsFixed(1)}٪',
                style: TextStyle(fontSize: 12, color: growthColor, fontWeight: FontWeight.w700)),
          ],
        ],
      ),
    );

    return Card(
      shape: emphasized
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12), side: const BorderSide(color: AppColors.brass, width: 1))
          : null,
      child: onTap == null
          ? body
          : InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: body),
    );
  }
}
