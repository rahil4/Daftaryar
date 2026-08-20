import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../services/backup_service.dart';
import '../../services/security_service.dart';
import '../../services/sms_listener_service.dart';
import '../sms_drafts/sms_drafts_screen.dart';
import '../sms_drafts/manual_sms_entry_screen.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../accounts/accounts_screen.dart';
import '../clients/clients_screen.dart';
import '../onboarding/fiscal_year_setup_screen.dart';
import '../lock/pin_setup_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _backup = BackupService();
  final _security = SecurityService();
  bool _busy = false;
  int _fyMonth = 1;
  int _fyDay = 1;
  bool _lockEnabled = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  bool _smsReadingEnabled = false;
  final _allowedSenderController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFiscalYear();
    _loadSecurity();
    _loadSmsSetting();
  }

  Future<void> _loadSmsSetting() async {
    final value = await DatabaseHelper.instance.getSetting('sms_reading_enabled');
    final sender = await DatabaseHelper.instance.getSetting('sms_allowed_sender');
    if (mounted) {
      setState(() {
        _smsReadingEnabled = value == '1';
        _allowedSenderController.text = sender ?? '';
      });
    }
  }

  Future<void> _saveAllowedSender(String value) async {
    await DatabaseHelper.instance.setSetting('sms_allowed_sender', value.trim());
  }

  Future<void> _toggleSmsReading(bool value) async {
    if (value) {
      final granted = await SmsListenerService.hasPermission();
      if (!granted) {
        _snack('برای این قابلیت باید دسترسی پیامک را تأیید کنید.');
        return;
      }
      await DatabaseHelper.instance.setSetting('sms_reading_enabled', '1');
      SmsListenerService.startListening();
      _snack('خواندن خودکار پیامک بانکی فعال شد.');
    } else {
      await DatabaseHelper.instance.setSetting('sms_reading_enabled', '0');
      _snack('خواندن خودکار پیامک بانکی غیرفعال شد.');
    }
    _loadSmsSetting();
  }

  Future<void> _loadSecurity() async {
    final lockEnabled = await _security.isLockEnabled();
    final bioEnabled = await _security.isBiometricEnabled();
    final bioAvailable = await _security.deviceSupportsBiometrics();
    if (mounted) {
      setState(() {
        _lockEnabled = lockEnabled;
        _biometricEnabled = bioEnabled;
        _biometricAvailable = bioAvailable;
      });
    }
  }

  Future<void> _toggleLock(bool value) async {
    if (value) {
      final result = await Navigator.push(
          context, MaterialPageRoute(builder: (_) => const PinSetupScreen()));
      if (result == true) {
        _snack('قفل پین فعال شد.');
      }
    } else {
      await _security.disableLock();
      _snack('قفل امنیتی غیرفعال شد.');
    }
    _loadSecurity();
  }

  Future<void> _toggleBiometric(bool value) async {
    await _security.setBiometricEnabled(value);
    _loadSecurity();
  }

  Future<void> _loadFiscalYear() async {
    final fy = await DatabaseHelper.instance.getFiscalYearStart();
    if (mounted) {
      setState(() {
        _fyMonth = fy['month']!;
        _fyDay = fy['day']!;
      });
    }
  }

  Future<void> _editFiscalYear() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FiscalYearSetupScreen(initialMonth: _fyMonth, initialDay: _fyDay),
      ),
    );
    if (result == true) _loadFiscalYear();
  }

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
            'تمام اشخاص، پروژه‌ها، تراکنش‌ها و هزینه‌ها برای همیشه حذف می‌شود. این عمل غیرقابل بازگشت است. مطمئن هستید؟'),
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
                    leading: const Icon(Icons.account_tree_outlined, color: AppColors.brass),
                    title: const Text('چارت حساب‌ها'),
                    subtitle: const Text('تعریف، ویرایش و دسته‌بندی حساب‌های حسابداری'),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const AccountsScreen())),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.people_alt_outlined, color: AppColors.brass),
                    title: const Text('اشخاص'),
                    subtitle: const Text('مدیریت لیست اشخاص'),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const ClientsScreen())),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.event_repeat_outlined, color: AppColors.brass),
                    title: const Text('سال مالی'),
                    subtitle: Text('شروع از ${pn(_fyDay)} ${jalaliMonthName(_fyMonth)}'),
                    onTap: _editFiscalYear,
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.lock_outline, color: AppColors.brass),
                    title: const Text('قفل امنیتی با پین'),
                    subtitle: Text(_lockEnabled ? 'فعال' : 'غیرفعال'),
                    value: _lockEnabled,
                    onChanged: _toggleLock,
                  ),
                ),
                if (_lockEnabled) ...[
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.password_outlined, color: AppColors.brass),
                      title: const Text('تغییر پین'),
                      onTap: () async {
                        final result = await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const PinSetupScreen()));
                        if (result == true) _snack('پین به‌روزرسانی شد.');
                      },
                    ),
                  ),
                  if (_biometricAvailable)
                    Card(
                      child: SwitchListTile(
                        secondary: const Icon(Icons.fingerprint, color: AppColors.brass),
                        title: const Text('ورود با اثر انگشت'),
                        subtitle: const Text('علاوه بر پین، امکان ورود سریع با اثر انگشت'),
                        value: _biometricEnabled,
                        onChanged: _toggleBiometric,
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                Card(
                  child: SwitchListTile(
                    secondary: const Icon(Icons.sms_outlined, color: AppColors.brass),
                    title: const Text('خواندن خودکار پیامک بانکی'),
                    subtitle: const Text(
                        'با ورود پیامک واریز/برداشت، پیش‌نویس سند آماده تأیید ساخته می‌شود'),
                    value: _smsReadingEnabled,
                    onChanged: _toggleSmsReading,
                  ),
                ),
                if (_smsReadingEnabled) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                      child: TextFormField(
                        controller: _allowedSenderController,
                        decoration: const InputDecoration(
                          labelText: 'شماره/فرستنده مجاز پیامک بانک',
                          hintText: 'مثلاً bki.ir یا شماره فرستنده',
                        ),
                        onChanged: _saveAllowedSender,
                      ),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.drafts_outlined, color: AppColors.brass),
                      title: const Text('پیش‌نویس‌های پیامکی'),
                      subtitle: const Text('بررسی، تأیید یا رد پیش‌نویس‌های شناسایی‌شده'),
                      onTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const SmsDraftsScreen())),
                    ),
                  ),
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.edit_note_outlined, color: AppColors.brass),
                      title: const Text('افزودن دستی پیامک'),
                      subtitle: const Text('اگر شنود خودکار کار نکرد، متن پیامک را اینجا بچسبانید'),
                      onTap: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const ManualSmsEntryScreen())),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
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
