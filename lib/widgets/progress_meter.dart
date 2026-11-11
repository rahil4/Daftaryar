import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// نوار پیشرفت افقی ساده (مثلاً «دریافتی از مبلغ پروژه»). مقدار بیرون از
/// بازه ۰ تا ۱ به همان بازه محدود می‌شود.
class ProgressMeter extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  final String? semanticLabel;

  const ProgressMeter({
    super.key,
    required this.value,
    this.color = AppColors.brass,
    this.height = 6,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Semantics(
      label: semanticLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height / 2),
        child: Container(
          height: height,
          color: AppColors.gridLine,
          alignment: AlignmentDirectional.centerStart,
          child: FractionallySizedBox(
            widthFactor: clamped,
            child: Container(
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height / 2)),
            ),
          ),
        ),
      ),
    );
  }
}
