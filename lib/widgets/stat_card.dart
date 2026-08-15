import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// کارت آماری استاندارد برنامه: آیکون در جعبه پاستلی، عنوان خاکستری،
/// مقدار درشت و تیره، و واحد اختیاری زیر آن. در داشبورد، جزئیات پروژه
/// و گزارش‌ها به‌صورت یکسان استفاده می‌شود.
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final Color? iconBg;
  final Color? iconColor;
  final String? unit;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.valueColor,
    this.iconBg,
    this.iconColor,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconBg ?? AppColors.pastelAmberBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor ?? AppColors.brass, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (unit != null)
            Text(unit!, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        ],
      ),
    );
  }
}
