import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../accounts/accounts_screen.dart';
import '../journal/journal_list_screen.dart';
import '../settings/settings_screen.dart';

enum _AccountingView { ledger, chart }

/// تب یکپارچه «حسابداری» - دفترکل (اسناد) و چارت حساب‌ها (با نمایش درختی
/// زیرحساب‌ها) که پیش‌تر دو مسیر ناوبری کاملاً جدا بودند و چارت حساب‌ها
/// داخل تنظیمات قایم شده بود. هر دو زیرصفحه در حالت embedded (بدون
/// Scaffold/AppBar مستقل خودشان) در یک IndexedStack مشترک نگه داشته
/// می‌شوند تا وضعیت اسکرول/فیلتر هرکدام هنگام سوییچ حفظ شود.
class AccountingScreen extends StatefulWidget {
  const AccountingScreen({super.key});

  @override
  State<AccountingScreen> createState() => _AccountingScreenState();
}

class _AccountingScreenState extends State<AccountingScreen> {
  _AccountingView _view = _AccountingView.ledger;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('حسابداری'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'تنظیمات',
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _ViewSwitcher(
              selected: _view,
              onChanged: (v) => setState(() => _view = v),
            ),
          ),
        ),
      ),
      body: BlueprintGridBackground(
        child: IndexedStack(
          index: _view.index,
          children: const [
            JournalListScreen(embedded: true),
            AccountsScreen(embedded: true),
          ],
        ),
      ),
    );
  }
}

/// سوییچ دوحالته دفترکل/چارت حساب‌ها به‌شکل Pill، مطابق ماکت تأییدشده
class _ViewSwitcher extends StatelessWidget {
  final _AccountingView selected;
  final ValueChanged<_AccountingView> onChanged;
  const _ViewSwitcher({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gridLine),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(child: _segment('دفترکل', _AccountingView.ledger)),
          Expanded(child: _segment('چارت حساب‌ها', _AccountingView.chart)),
        ],
      ),
    );
  }

  Widget _segment(String label, _AccountingView value) {
    final active = selected == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.brass : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: active ? const Color(0xFF15100A) : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
