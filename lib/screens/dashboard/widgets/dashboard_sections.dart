import 'package:flutter/material.dart';

import '../../../models/management_dashboard_data.dart';
import '../../../theme/app_theme.dart';

Widget _sectionTitle(String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
  );
}

/// بخش هشدارهای مدیریتی. [onOutstandingReceivablesTap] فقط برای هشدار
/// «مطالبات باز» استفاده می‌شود (مستقیماً به صفحه «طلب‌ها» می‌رود)؛
/// بقیه هشدارها فعلاً مقصد ناوبری مشخصی ندارند، پس قابل لمس نیستند.
class AlertsSection extends StatelessWidget {
  final ManagementDashboardData data;
  final VoidCallback? onOutstandingReceivablesTap;
  const AlertsSection({super.key, required this.data, this.onOutstandingReceivablesTap});

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
          final onTap = a.title == 'مطالبات باز' ? onOutstandingReceivablesTap : null;
          return Card(
            child: ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: color),
              title: Text(a.title, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              subtitle: Text(a.message),
              trailing: onTap != null ? const Icon(Icons.chevron_left) : null,
              onTap: onTap,
            ),
          );
        }),
      ],
    );
  }
}
