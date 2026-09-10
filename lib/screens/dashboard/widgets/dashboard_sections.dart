import 'package:flutter/material.dart';

import '../../../models/management_dashboard_data.dart';
import '../../../theme/app_theme.dart';

Widget _sectionTitle(String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
  );
}

/// بخش هشدارهای مدیریتی
class AlertsSection extends StatelessWidget {
  final ManagementDashboardData data;
  const AlertsSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.alerts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('هشدارهای مدیریتی'),
        ...data.alerts.map((a) {
          final color = a.severity == ManagementAlertSeverity.error
              ? AppColors.negative
              : (a.severity == ManagementAlertSeverity.warning ? AppColors.brass : AppColors.textSecondary);
          return Card(
            child: ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: color),
              title: Text(a.title, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              subtitle: Text(a.message),
            ),
          );
        }),
      ],
    );
  }
}
