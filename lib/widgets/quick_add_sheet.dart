import 'package:flutter/material.dart';

import '../screens/counterparties/counterparty_form_screen.dart';
import '../screens/journal/journal_form_screen.dart';
import '../screens/journal/quick_expense_screen.dart';
import '../screens/journal/quick_receipt_screen.dart';
import '../screens/projects/project_form_screen.dart';
import '../theme/app_theme.dart';

/// برگه «ثبت جدید» - تنها نقطه ورود همه ثبت‌ها: دو کار پرتکرار (دریافت وجه
/// و ثبت هزینه) به‌شکل دو کاشی بزرگ، و بقیه (پروژه/طرف حساب جدید، سند دستی)
/// به‌شکل ردیف زیر آن‌ها. از دکمه «+» نوار پایین و از داخل صفحه پروژه/طرف
/// حساب باز می‌شود.
///
/// وقتی از داخل یک پروژه یا طرف حساب باز شود (preset داده شده)، ردیف‌های
/// «پروژه جدید» و «طرف حساب جدید» نمایش داده نمی‌شوند، چون در آن زمینه
/// بی‌ربط‌اند.
Future<void> showQuickAddSheet(
  BuildContext context, {
  int? presetProjectId,
  int? presetCounterpartyId,
  VoidCallback? onDone,
}) {
  final hasPreset = presetProjectId != null || presetCounterpartyId != null;

  Future<void> open(BuildContext sheetContext, Widget screen) async {
    Navigator.pop(sheetContext);
    final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    // فرم‌های دریافت/هزینه/سند true برمی‌گردانند و فرم‌های پروژه/طرف حساب
    // خودِ رکورد ساخته‌شده را؛ هر مقدار غیر از null/false یعنی چیزی ثبت شده.
    if (result != null && result != false) onDone?.call();
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration:
                    BoxDecoration(color: AppColors.lineStrong, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('ثبت جدید', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  ),
                  IconButton(
                    tooltip: 'بستن',
                    icon: const Icon(Icons.close, color: AppColors.textSecondary),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _BigTile(
                      icon: Icons.arrow_downward_rounded,
                      title: 'دریافت وجه',
                      subtitle: 'پیش‌دریافت، طلب، درآمد نقدی',
                      primary: true,
                      onTap: () => open(
                        ctx,
                        QuickReceiptScreen(
                            presetProjectId: presetProjectId, presetCounterpartyId: presetCounterpartyId),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _BigTile(
                      icon: Icons.arrow_upward_rounded,
                      title: 'ثبت هزینه',
                      subtitle: 'هزینه پروژه یا دفتر، پرداخت بدهی',
                      onTap: () => open(
                        ctx,
                        QuickExpenseScreen(
                            presetProjectId: presetProjectId, presetCounterpartyId: presetCounterpartyId),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (!hasPreset) ...[
              _SheetRow(
                icon: Icons.work_outline,
                title: 'پروژه جدید',
                onTap: () => open(ctx, const ProjectFormScreen()),
              ),
              const Divider(height: 1),
              _SheetRow(
                icon: Icons.person_outline,
                title: 'طرف حساب جدید',
                onTap: () => open(ctx, const CounterpartyFormScreen()),
              ),
              const Divider(height: 1),
            ],
            _SheetRow(
              icon: Icons.menu_book_outlined,
              title: 'سند حسابداری دستی',
              subtitle: 'برای ثبت‌های چندسطری و اصلاحی',
              onTap: () => open(
                ctx,
                JournalFormScreen(presetProjectId: presetProjectId, presetCounterpartyId: presetCounterpartyId),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _BigTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool primary;
  final VoidCallback onTap;

  const _BigTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(16);
    return Material(
      color: primary ? AppColors.brass.withValues(alpha: 0.10) : AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: primary ? AppColors.brass : AppColors.gridLine),
      ),
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: AppColors.brassLight, size: 24),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SheetRow({required this.icon, required this.title, required this.onTap, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
            // در چیدمان راست‌به‌چپ، «جلو رفتن» به سمت چپ است.
            const Icon(Icons.chevron_left, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
