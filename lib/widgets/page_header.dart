import 'package:flutter/material.dart';

import '../screens/settings/settings_screen.dart';
import '../theme/app_theme.dart';

/// سربرگ مشترک چهار تب اصلی: نام برنامه با حروف ریز بالای عنوان درشت صفحه،
/// و دکمه‌های اقدام در سمت دیگر. روی همان پس‌زمینه صفحه می‌نشیند (نه یک نوار
/// جدا با رنگ کارت) تا عدد اصلی صفحه بلافاصله زیر عنوان دیده شود.
AppBar pageHeader(
  BuildContext context, {
  required String title,
  List<Widget> actions = const [],
  bool showSettings = true,
  PreferredSizeWidget? bottom,
}) {
  return AppBar(
    backgroundColor: AppColors.background,
    centerTitle: false,
    titleSpacing: 20,
    toolbarHeight: 64,
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('دفتریار',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.textSecondary)),
        Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ],
    ),
    actions: [
      ...actions,
      if (showSettings)
        HeaderIconButton(
          icon: Icons.settings_outlined,
          tooltip: 'تنظیمات',
          onPressed: () =>
              Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
        ),
      const SizedBox(width: 12),
    ],
    bottom: bottom,
  );
}

/// دکمه آیکونی چهارگوش سربرگ (۴۴×۴۴) با حاشیه ملایم.
class HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const HeaderIconButton({super.key, required this.icon, required this.tooltip, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: Tooltip(
        message: tooltip,
        child: Material(
          color: AppColors.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.gridLine),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 20, color: AppColors.textSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

/// عنوان بلوک‌های داخل صفحه («نیاز به پیگیری»، «آخرین تراکنش‌ها»).
class BlockHeading extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const BlockHeading(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(text, style: AppTextStyles.blockHeading)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
