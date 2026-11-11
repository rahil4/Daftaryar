import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// نشان «مُهر» برای وضعیت‌های قطعی و برگشت‌ناپذیر (مثل «نهایی‌شده»): دو کادر
/// تودرتو با کمی چرخش، شبیه مُهر روی سند کاغذی.
class StampChip extends StatelessWidget {
  final String label;
  final Color color;
  final double fontSize;

  const StampChip(this.label, {super.key, this.color = AppColors.brass, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.06,
      child: Container(
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withValues(alpha: 0.55)),
          ),
          child: Text(label,
              style: TextStyle(color: AppColors.brassLight, fontSize: fontSize, fontWeight: FontWeight.w800)),
        ),
      ),
    );
  }
}

/// برچسب وضعیت معمولی (غیرقطعی): کادر خنثی و کم‌رنگ.
class StatusChip extends StatelessWidget {
  final String label;
  const StatusChip(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.lineStrong),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary)),
    );
  }
}
