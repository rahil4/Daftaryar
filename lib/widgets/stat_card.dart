import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// کارت آماری استاندارد برنامه: برچسب خاکستری کوچک + مقدار درشت، در یک
/// کادر یکدست - در داشبورد، جزئیات پروژه، طرف‌حساب و گزارش‌ها به یک شکل
/// استفاده می‌شود (پیش‌تر هرکدام از این صفحات کامپوننت کارت آماری جداگانه‌ی
/// خودش را داشت؛ اکنون همه از همین یک الگو می‌آیند).
class StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color? color; // رنگ تأکید مقدار (پیش‌فرض: متن اصلی)
  final String? unit;
  final VoidCallback? onTap;
  /// حاشیه برنزی برای برجسته‌کردن یک شاخص کلیدی (مثل پیش‌دریافت در داشبورد)
  final bool emphasize;

  const StatCard({
    super.key,
    required this.title,
    required this.value,
    this.color,
    this.unit,
    this.onTap,
    this.emphasize = false,
  });

  /// فقط محتوای داخلی (برچسب+مقدار)، بدون کادر بیرونی - برای ترکیب چند
  /// شاخص در یک کارت واحد (مثل کارت «طلب و پیش‌دریافت» داشبورد) بدون
  /// تکرار کد چیدمان برچسب/مقدار.
  static Widget content({required String title, required String value, Color? color, String? unit}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            value,
            style: TextStyle(color: color ?? AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
        if (unit != null) Text(unit, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: emphasize ? AppColors.brass : AppColors.gridLine, width: emphasize ? 0.8 : 1),
      ),
      child: content(title: title, value: value, color: color, unit: unit),
    );
    if (onTap == null) return card;
    return InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: card);
  }
}
