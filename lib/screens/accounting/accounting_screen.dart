import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/reloadable.dart';
import '../../widgets/page_header.dart';
import '../../widgets/segmented_switch.dart';
import '../accounts/account_form_screen.dart';
import '../accounts/accounts_screen.dart';
import '../journal/journal_list_screen.dart';

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

class _AccountingScreenState extends State<AccountingScreen> with Reloadable<AccountingScreen> {
  _AccountingView _view = _AccountingView.ledger;
  final _journalKey = GlobalKey<State<JournalListScreen>>();
  final _accountsKey = GlobalKey<State<AccountsScreen>>();

  @override
  Future<void> reload() {
    triggerReload(_view == _AccountingView.ledger ? _journalKey : _accountsKey);
    return Future.value();
  }

  void _switchView(_AccountingView v) {
    setState(() => _view = v);
    triggerReload(v == _AccountingView.ledger ? _journalKey : _accountsKey);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageHeader(
        context,
        title: 'حسابداری',
        actions: [
          // ساخت حساب فقط در نمای چارت حساب‌ها معنا دارد.
          if (_view == _AccountingView.chart)
            TextButton.icon(
              onPressed: () async {
                final result =
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountFormScreen()));
                if (result == true && mounted) triggerReload(_accountsKey);
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('حساب جدید', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.brassLight,
                minimumSize: const Size(44, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.gridLine),
                ),
                backgroundColor: AppColors.surface,
              ),
            ),
        ],
      ),
      body: BlueprintGridBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: SegmentedSwitch<_AccountingView>(
                options: const {
                  _AccountingView.ledger: 'دفترکل',
                  _AccountingView.chart: 'چارت حساب‌ها',
                },
                selected: _view,
                onChanged: _switchView,
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: _view.index,
                children: [
                  JournalListScreen(key: _journalKey, embedded: true),
                  AccountsScreen(key: _accountsKey, embedded: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
