import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../screens/journal/quick_receipt_screen.dart';
import '../screens/journal/quick_expense_screen.dart';
import '../screens/journal/journal_form_screen.dart';

/// شیت پایین مشترک برای «ثبت دریافت»، «ثبت هزینه/پرداخت» و «سند دستی»
/// در چند نقطه از برنامه (نوار پایین، صفحه اسناد، صفحه پروژه) استفاده می‌شود
/// تا کد تکراری نداشته باشیم.
Future<void> showQuickAddSheet(
  BuildContext context, {
  int? presetProjectId,
  VoidCallback? onDone,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => SafeArea(
      child: Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.south_west_rounded, color: AppColors.positive),
            title: const Text('ثبت دریافت وجه'),
            subtitle: const Text('دریافت از شخص یا سایر منابع'),
            onTap: () async {
              Navigator.pop(ctx);
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => QuickReceiptScreen(presetProjectId: presetProjectId)),
              );
              if (result == true) onDone?.call();
            },
          ),
          ListTile(
            leading: const Icon(Icons.north_east_rounded, color: AppColors.negative),
            title: const Text('ثبت هزینه / پرداخت'),
            subtitle: const Text('هزینه عمومی دفتر یا هزینه پروژه'),
            onTap: () async {
              Navigator.pop(ctx);
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => QuickExpenseScreen(presetProjectId: presetProjectId)),
              );
              if (result == true) onDone?.call();
            },
          ),
          ListTile(
            leading: const Icon(Icons.receipt_long_outlined, color: AppColors.brass),
            title: const Text('سند حسابداری دستی'),
            subtitle: const Text('برای ثبت‌های چندسطری یا خاص'),
            onTap: () async {
              Navigator.pop(ctx);
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => JournalFormScreen(presetProjectId: presetProjectId)),
              );
              if (result == true) onDone?.call();
            },
          ),
        ],
      ),
    ),
  );
}
