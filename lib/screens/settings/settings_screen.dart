import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../services/backup_service.dart';
import '../../theme/app_theme.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _backup = BackupService();
  bool _busy = false;

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      await _backup.exportToFile();
      _snack('فایل پشتیبان ساخته و برای اشتراک‌گذاری آماده شد.');
    } catch (e) {
      _snack('خطا در تهیه پشتیبان: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _import({required bool replace}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بازیابی اطلاعات'),
        content: Text(replace
            ? 'با ادامه، تمام داده‌های فعلی حذف و با محتوای فایل پشتیبان جایگزین می‌شود. ادامه می‌دهید؟'
            : 'اطلاعات فایل پشتیبان به داده‌های فعلی افزوده می‌شود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأیید')),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busy = true);
    try {
      await _backup.importFromPickedFile(replaceExisting: replace);
      _snack('بازیابی با موفقیت انجام شد.');
    } catch (e) {
      _snack('خطا در بازیابی: $e');
    } finally {
      setState(() => _busy = false);
    }
  }

  Future<void> _wipeAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('پاک‌سازی کامل'),
        content: const Text(
            'تمام کارفرمایان، پروژه‌ها، تراکنش‌ها و هزینه‌ها برای همیشه حذف می‌شود. این عمل غیرقابل بازگشت است. مطمئن هستید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف همه', style: TextStyle(color: AppColors.negative))),
        ],
      ),
    );
    if (confirm == true) {
      await DatabaseHelper.instance.wipeAll();
      _snack('تمام داده‌ها حذف شد.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیمات و پشتیبان‌گیری')),
      body: BlueprintGridBackground(
        child: AbsorbPointer(
          absorbing: _busy,
          child: Opacity(
            opacity: _busy ? 0.6 : 1,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.upload_file_outlined, color: AppColors.brass),
                    title: const Text('تهیه فایل پشتیبان'),
                    subtitle: const Text('خروجی JSON از تمام اطلاعات، برای ذخیره یا اشتراک‌گذاری'),
                    onTap: _export,
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.download_outlined, color: AppColors.brass),
                    title: const Text('افزودن از فایل پشتیبان'),
                    subtitle: const Text('اطلاعات فایل به داده‌های فعلی اضافه می‌شود'),
                    onTap: () => _import(replace: false),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.restore_page_outlined, color: AppColors.brass),
                    title: const Text('جایگزینی کامل با فایل پشتیبان'),
                    subtitle: const Text('داده‌های فعلی حذف و با فایل پشتیبان جایگزین می‌شود'),
                    onTap: () => _import(replace: true),
                  ),
                ),
                const SizedBox(height: 20),
                Card(
                  color: AppColors.surfaceAlt,
                  child: ListTile(
                    leading: const Icon(Icons.delete_forever_outlined, color: AppColors.negative),
                    title: const Text('پاک‌سازی کامل اطلاعات'),
                    subtitle: const Text('حذف همیشگی همه داده‌ها از روی دستگاه'),
                    onTap: _wipeAll,
                  ),
                ),
                const SizedBox(height: 24),
                const Center(
                  child: Text('دفتریار — نسخه ۱.۰.۰',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
