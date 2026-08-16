import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// عنوان بخش به سبک سنتی حسابداری (برنزی، کوچک، بدون آیکون) —
/// در داشبورد و چارت حساب‌ها برای جدا کردن دسته‌های اصلی استفاده می‌شود.
class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brass),
      ),
    );
  }
}
