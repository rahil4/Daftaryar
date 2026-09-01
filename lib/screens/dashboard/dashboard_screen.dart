import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../journal/quick_receipt_screen.dart';
import '../journal/quick_expense_screen.dart';
import '../../widgets/section_title.dart';
import '../sms_drafts/sms_drafts_screen.dart';

/// داشبورد اصلی دفتریار — سبک سنتی حسابداری: فقط متن و ردیف، بدون آیکون و کارت
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = DatabaseHelper.instance;
  bool _loading = true;

  List<Map<String, dynamic>> _bankLines = [];
  double _cashBalance = 0;
  double _todayIncome = 0;
  double _todayExpense = 0;
  int _pendingSmsDrafts = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final bankLines = await _db.bankBalances();
    final cash = await _db.assetBalanceByKeyword('صندوق');
    final today = todayJalaliString();
    final income = await _db.totalAccountTypeBalance(kAccountIncome, fromDate: today, toDate: today);
    final expense = await _db.totalAccountTypeBalance(kAccountExpense, fromDate: today, toDate: today);
    final pendingDrafts = await _db.countPendingSmsDrafts();

    setState(() {
      _bankLines = bankLines;
      _cashBalance = cash;
      _todayIncome = income;
      _todayExpense = expense;
      _pendingSmsDrafts = pendingDrafts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bankTotal = _bankLines.fold<double>(0, (s, b) => s + (b['balance'] as double));
    final liquidAssets = bankTotal + _cashBalance;
    final todayProfit = _todayIncome - _todayExpense;

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    const _PageHeader(),
                    if (_pendingSmsDrafts > 0) ...[
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => const SmsDraftsScreen()));
                          _load();
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: AppColors.brass.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.brass),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${pn(_pendingSmsDrafts)} پیش‌نویس پیامکی در انتظار تأیید',
                                style: const TextStyle(
                                    fontSize: 13, color: AppColors.brass, fontWeight: FontWeight.w700),
                              ),
                              const Text('‹', style: TextStyle(color: AppColors.brass, fontSize: 16)),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),

                    const SectionTitle('نقدینگی'),
                    const Divider(color: AppColors.gridLine, height: 1),
                    for (final b in _bankLines)
                      _LedgerRow(
                        label: b['name'] as String,
                        value: formatMoney(b['balance'] as double),
                      ),
                    _LedgerRow(label: 'موجودی صندوق', value: formatMoney(_cashBalance)),
                    _LedgerRow(
                      label: 'جمع دارایی‌های نقدی',
                      value: formatMoney(liquidAssets),
                      isTotal: true,
                    ),

                    const SizedBox(height: 22),
                    const SectionTitle('عملکرد روز جاری'),
                    const Divider(color: AppColors.gridLine, height: 1),
                    _LedgerRow(label: 'میزان درآمد روز جاری', value: formatMoney(_todayIncome)),
                    _LedgerRow(label: 'میزان هزینه روز جاری', value: formatMoney(_todayExpense)),
                    _LedgerRow(
                      label: 'سود روز جاری',
                      value: formatMoney(todayProfit),
                      isTotal: true,
                      valueColor: todayProfit >= 0 ? AppColors.positive : AppColors.negative,
                    ),

                    const SizedBox(height: 26),
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(
                          top: BorderSide(color: AppColors.gridLine),
                          bottom: BorderSide(color: AppColors.gridLine),
                        ),
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          children: [
                            Expanded(
                              child: _ActionCell(
                                label: 'ثبت دریافت',
                                color: AppColors.positive,
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const QuickReceiptScreen()),
                                  );
                                  if (result == true) _load();
                                },
                              ),
                            ),
                            const VerticalDivider(color: AppColors.gridLine, width: 1),
                            Expanded(
                              child: _ActionCell(
                                label: 'ثبت پرداخت',
                                color: AppColors.negative,
                                onTap: () async {
                                  final result = await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => const QuickExpenseScreen()),
                                  );
                                  if (result == true) _load();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// عنوان برنامه + عنوان صفحه + تاریخ گزارش، با خط جداکننده زیر
class _PageHeader extends StatelessWidget {
  const _PageHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(bottom: 16),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.gridLine)),
      ),
      child: Column(
        children: [
          const Text(
            'دفتریار',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          const Text(
            'صورت وضعیت مالی',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            'تاریخ گزارش: ${formatJalaliLong(todayJalaliString())}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// ردیف متنی ساده «عنوان — مبلغ»، مشابه سطر در دفتر حسابداری کاغذی
class _LedgerRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isTotal;
  final Color? valueColor;

  const _LedgerRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: isTotal ? 14 : 11, bottom: 11),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isTotal ? AppColors.brass : AppColors.gridLine,
            width: isTotal ? 2 : 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14.5,
              color: isTotal ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isTotal ? 17 : 14.5,
              fontWeight: isTotal ? FontWeight.w800 : FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// ردیف اقدام متنی قابل‌کلیک، برای قرارگیری کنار هم در یک ردیف (دریافت | پرداخت)
class _ActionCell extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionCell({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
        ),
      ),
    );
  }
}
