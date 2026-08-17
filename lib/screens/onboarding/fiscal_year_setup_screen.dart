import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// تعریف بازه سال مالی — هم در اولین اجرای برنامه (به‌صورت اجباری) و هم
/// بعداً از تنظیمات (برای ویرایش) استفاده می‌شود.
class FiscalYearSetupScreen extends StatefulWidget {
  final bool isOnboarding;
  final int initialMonth;
  final int initialDay;
  final VoidCallback? onDone;

  const FiscalYearSetupScreen({
    super.key,
    this.isOnboarding = false,
    this.initialMonth = 1,
    this.initialDay = 1,
    this.onDone,
  });

  @override
  State<FiscalYearSetupScreen> createState() => _FiscalYearSetupScreenState();
}

class _FiscalYearSetupScreenState extends State<FiscalYearSetupScreen> {
  final _db = DatabaseHelper.instance;
  late int _month = widget.initialMonth;
  late int _day = widget.initialDay;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    await _db.setFiscalYearStart(_month, _day);
    if (!mounted) return;
    if (widget.isOnboarding) {
      widget.onDone?.call();
    } else {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = _month <= 6 ? 31 : (_month <= 11 ? 30 : 29);
    if (_day > daysInMonth) _day = daysInMonth;

    final body = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.isOnboarding) ...[
              const Text(
                'دفتریار',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              const Text(
                'تعریف سال مالی',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              ),
              const SizedBox(height: 10),
              const Text(
                'روز و ماه شروع سال مالی دفتر را مشخص کنید. این بازه برای گزارش‌های '
                'سود و زیان و تراز سالانه استفاده می‌شود. اگر مطمئن نیستید، ۱ فروردین '
                '(پیش‌فرض تقویم شمسی) را نگه دارید.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.7),
              ),
              const SizedBox(height: 32),
            ],
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _day,
                    decoration: const InputDecoration(labelText: 'روز'),
                    items: List.generate(daysInMonth, (i) => i + 1)
                        .map((d) => DropdownMenuItem(value: d, child: Text(pn(d))))
                        .toList(),
                    onChanged: (v) => setState(() => _day = v!),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: DropdownButtonFormField<int>(
                    value: _month,
                    decoration: const InputDecoration(labelText: 'ماه'),
                    items: List.generate(12, (i) => i + 1)
                        .map((m) => DropdownMenuItem(value: m, child: Text(jalaliMonthName(m))))
                        .toList(),
                    onChanged: (v) => setState(() => _month = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('تأیید و ادامه'),
            ),
          ],
        ),
      ),
    );

    if (widget.isOnboarding) {
      return Scaffold(body: body);
    }
    return Scaffold(appBar: AppBar(title: const Text('تعریف سال مالی')), body: body);
  }
}
