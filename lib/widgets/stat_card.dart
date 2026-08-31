import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// کارت آماری استاندارد برنامه: آیکون در جعبه کم‌رنگِ هم‌رنگ خودش،
/// عنوان خاکستری، مقدار درشت روشن. برای هر شاخص فقط یک رنگ لهجه کافی است؛
/// در داشبورد، جزئیات پروژه و گزارش‌ها به‌صورت یکسان استفاده می‌شود.
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color? color; // رنگ لهجه آیکون و مقدار (پیش‌فرض: برنز برند)
  final Color? valueColor;
  final String? unit;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.color,
    this.valueColor,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final accent = color ?? AppColors.brass;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gridLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 19),
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
