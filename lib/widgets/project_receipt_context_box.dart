import 'package:flutter/material.dart';

import '../models/project.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// تعریف واحد «مانده» برای همه‌جای برنامه (فرم‌های دریافت وجه + تب خلاصه
/// پروژه) - پیش از Finalization یک برآورد است (چون مبلغ قطعی نیست)، پس از
/// آن دقیقاً مانده واقعی حساب دریافتنی (AR) پروژه. هیچ محاسبه مالی جدیدی
/// اینجا انجام نمی‌شود - فقط ترکیب دو عدد از‌قبل‌محاسبه‌شدهٔ
/// projectFinancialSummary.
({double? value, String label}) computeProjectRemaining(ProjectModel project, Map<String, dynamic> summary) {
  final totalReceived = (summary['totalReceived'] as double?) ?? 0;
  if (project.isFinalized) {
    return (value: summary['receivable'] as double?, label: 'مانده طلب');
  }
  final currentExpected = summary['currentExpectedAmount'] as double?;
  return (
    value: currentExpected != null ? currentExpected - totalReceived : null,
    label: 'مانده تخمینی',
  );
}

/// بلوک اطلاعاتی فشرده - «مجموع دریافتی تاکنون» و «مانده» - که در فرم‌های
/// دریافت وجه پروژه (چه از تب مالی پروژه، چه از دریافت سریع) بالای فیلد
/// مبلغ نمایش داده می‌شود تا لحظه ثبت پول، کاربر زمینهٔ کامل وضعیت پروژه
/// را ببیند. فقط از اعداد از‌قبل‌محاسبه‌شدهٔ projectFinancialSummary
/// استفاده می‌کند - هیچ محاسبه مالی جدیدی اینجا انجام نمی‌شود.
class ProjectReceiptContextBox extends StatelessWidget {
  final ProjectModel project;
  final Map<String, dynamic> summary;
  const ProjectReceiptContextBox({super.key, required this.project, required this.summary});

  @override
  Widget build(BuildContext context) {
    final totalReceived = (summary['totalReceived'] as double?) ?? 0;
    final remainingInfo = computeProjectRemaining(project, summary);
    final remaining = remainingInfo.value;
    final remainingColor =
        remaining == null ? AppColors.textSecondary : (remaining > 0 ? AppColors.brass : AppColors.positive);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.gridLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('مجموع دریافتی تاکنون',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 3),
                Text(formatMoney(totalReceived),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.positive)),
              ],
            ),
          ),
          Container(width: 1, height: 30, color: AppColors.gridLine),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(remainingInfo.label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 3),
                Text(
                  remaining == null ? '—' : formatMoney(remaining.abs()),
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: remainingColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
