import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../journal/quick_receipt_screen.dart';
import '../journal/quick_expense_screen.dart';
import '../../widgets/section_title.dart';

/// داشبورد اصلی دفتریار — سبک سنتی حسابداری: فقط متن و ردیف، بدون آیکون و کارت
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = DatabaseHelper.instance;
  bool _loading = true;

  double _assets = 0;
  double _liabilities = 0;
  double _netWorth = 0;
  double _equity = 0;
  int _activeProjectsCount = 0;
  int _clientsCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final summary = await _db.dashboardSummary();
    final projects = await _db.getProjects();
    final clients = await _db.getClients();
    setState(() {
      _assets = summary['assetBalance']!;
      _liabilities = summary['liabilityBalance']!;
      _netWorth = summary['netWorth']!;
      _equity = summary['equityBalance']!;
      _activeProjectsCount = projects.where((p) => p.status == 'در حال انجام').length;
      _clientsCount = clients.length;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                    const SizedBox(height: 22),

                    const SectionTitle('ترازنامه خلاصه'),
                    _LedgerDivider.top(),
                    _LedgerRow(label: 'جمع دارایی‌ها', value: formatMoney(_assets)),
                    _LedgerRow(label: 'جمع بدهی‌ها', value: formatMoney(_liabilities)),
                    _LedgerRow(
                      label: 'خالص ارزش',
                      value: formatMoney(_netWorth),
                      isTotal: true,
                      valueColor: _netWorth >= 0 ? AppColors.positive : AppColors.negative,
                    ),
                    _LedgerRow(label: 'حقوق صاحبان سهام', value: formatMoney(_equity)),

                    const SizedBox(height: 22),
                    const SectionTitle('وضعیت کلی'),
                    _StatLine(label: 'پروژه‌های در حال انجام', value: '${pn(_activeProjectsCount)} مورد'),
                    _StatLine(label: 'تعداد اشخاص ثبت‌شده', value: '${pn(_clientsCount)} نفر'),

                    const SizedBox(height: 26),
                    Container(
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: AppColors.gridLine)),
                      ),
                      child: Column(
                        children: [
                          _ActionRow(
                            label: 'ثبت دریافت وجه',
                            color: AppColors.positive,
                            onTap: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const QuickReceiptScreen()),
                              );
                              if (result == true) _load();
                            },
                          ),
                          _ActionRow(
                            label: 'ثبت پرداخت / هزینه',
                            color: AppColors.negative,
                            onTap: () async {
                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const QuickExpenseScreen()),
                              );
                              if (result == true) _load();
                            },
                          ),
                        ],
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

/// خط باریک بالای بخش دفترداری (مثل خط بالای جدول در دفتر کل)
class _LedgerDivider extends StatelessWidget {
  const _LedgerDivider();
  factory _LedgerDivider.top() => const _LedgerDivider();

  @override
  Widget build(BuildContext context) {
    return const Divider(color: AppColors.gridLine, height: 1);
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

/// ردیف آمار کلی بدون خط جداکننده - برای اطلاعات فرعی
class _StatLine extends StatelessWidget {
  final String label;
  final String value;
  const _StatLine({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12.5, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// ردیف اقدام متنی قابل‌کلیک (ثبت دریافت / پرداخت) بدون آیکون یا پس‌زمینه رنگی
class _ActionRow extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionRow({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.gridLine)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
            const Text('‹', style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
