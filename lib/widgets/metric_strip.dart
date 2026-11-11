import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/formatters.dart';

/// یک شاخص در MetricStrip: برچسب کوچک، مقدار، و یک زیرنویس اختیاری.
class MetricItem {
  final String label;
  final String value;
  final Widget? footer;
  final double valueSize;
  final Color? valueColor;

  const MetricItem({
    required this.label,
    required this.value,
    this.footer,
    this.valueSize = 15,
    this.valueColor,
  });
}

/// چند شاخص هم‌ردیف در یک کارت، با خط جداکننده عمودی بین‌شان - به‌جای چند
/// کارت جدا برای اعدادی که با هم خوانده می‌شوند (درآمد/هزینه/سود).
class MetricStrip extends StatelessWidget {
  final List<MetricItem> items;
  final bool framed;

  const MetricStrip({super.key, required this.items, this.framed = true});

  @override
  Widget build(BuildContext context) {
    final row = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) ...[
              const VerticalDivider(width: 1, thickness: 1, color: AppColors.gridLine),
              const SizedBox(width: 12),
            ],
            Expanded(child: _cell(items[i])),
          ],
        ],
      ),
    );
    if (!framed) return row;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gridLine),
      ),
      child: row,
    );
  }

  Widget _cell(MetricItem item) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(item.label, style: AppTextStyles.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            item.value,
            style: TextStyle(
              fontSize: item.valueSize,
              fontWeight: FontWeight.w700,
              color: item.valueColor ?? AppColors.textPrimary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        if (item.footer != null) ...[const SizedBox(height: 4), item.footer!],
      ],
    );
  }
}

/// تغییر نسبت به دوره قبل: مثلث جهت + درصد. عمداً خنثی (نه سبز/قرمز)، چون
/// «بالا رفتن» برای هزینه خبر خوب نیست و رنگ نباید قضاوت کند.
class DeltaLabel extends StatelessWidget {
  final double? percent;
  final String? suffix;

  const DeltaLabel({super.key, required this.percent, this.suffix});

  @override
  Widget build(BuildContext context) {
    final p = percent;
    if (p == null) return const SizedBox(height: 16);
    final text = '${pn(p.abs().toStringAsFixed(p.abs() >= 10 ? 0 : 1))}٪${suffix == null ? '' : ' $suffix'}';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(p >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down, size: 16, color: AppColors.textSecondary),
        Flexible(
          child: Text(text,
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// کادر استاندارد بخش‌های صفحه (سطح کارت با حاشیه ملایم).
class SurfaceBox extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const SurfaceBox({super.key, required this.child, this.padding = const EdgeInsets.all(16)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gridLine),
      ),
      child: child,
    );
  }
}

/// عدد اصلی صفحه: برچسب کوچک بالای یک عدد درشت با واحد.
class HeroAmount extends StatelessWidget {
  final String label;
  final double amount;
  final double fontSize;

  const HeroAmount({super.key, required this.label, required this.amount, this.fontSize = 34});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(formatMoney(amount, withSuffix: false),
                  style: AppTextStyles.heroNumber.copyWith(fontSize: fontSize)),
              const SizedBox(width: 8),
              const Text('تومان', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
