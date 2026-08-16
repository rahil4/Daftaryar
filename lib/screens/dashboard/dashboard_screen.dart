import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
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

  double _bankBalance = 0;
  double _cashBalance = 0;
  double _todayIncome = 0;
  double _todayExpense = 0;
  int _activeProjectsCount = 0;
  int _clientsCount = 0;

  // عملکرد ۴ هفته اخیر: هفته جاری + ۳ هفته قبل
  List<double> _weeklyProfits = [0, 0, 0, 0];
  static const _weekLabels = ['۳ هفته قبل', '۲ هفته قبل', '۱ هفته قبل', 'هفته جاری'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final bank = await _db.assetBalanceByKeyword('بانک');
    final cash = await _db.assetBalanceByKeyword('صندوق');
    final today = todayJalaliString();
    final income = await _db.totalAccountTypeBalance(kAccountIncome, fromDate: today, toDate: today);
    final expense = await _db.totalAccountTypeBalance(kAccountExpense, fromDate: today, toDate: today);
    final projects = await _db.getProjects();
    final clients = await _db.getClients();

    // محاسبه سود/زیان ۴ هفته اخیر (شنبه تا جمعه شمسی)
    final now = Jalali.now();
    final thisWeek = jalaliWeekRange(now);
    final weeklyProfits = <double>[];
    for (int i = 3; i >= 0; i--) {
      final weekStart = thisWeek[0].addDays(-7 * i);
      final weekEnd = weekStart.addDays(6);
      final profit = await _db.netProfitForRange(
        fromDate: jalaliToString(weekStart),
        toDate: jalaliToString(weekEnd),
      );
      weeklyProfits.add(profit);
    }

    setState(() {
      _bankBalance = bank;
      _cashBalance = cash;
      _todayIncome = income;
      _todayExpense = expense;
      _activeProjectsCount = projects.where((p) => p.status == 'در حال انجام').length;
      _clientsCount = clients.length;
      _weeklyProfits = weeklyProfits;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final liquidAssets = _bankBalance + _cashBalance;
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
                    const SizedBox(height: 22),

                    const SectionTitle('نقدینگی'),
                    const Divider(color: AppColors.gridLine, height: 1),
                    _LedgerRow(label: 'موجودی بانک‌ها', value: formatMoney(_bankBalance)),
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

                    const SizedBox(height: 22),
                    const SectionTitle('عملکرد هفتگی (سود/زیان)'),
                    const SizedBox(height: 8),
                    _WeeklyProfitChart(values: _weeklyProfits, labels: _weekLabels),
                    const SizedBox(height: 10),
                    ...List.generate(_weeklyProfits.length, (i) {
                      final v = _weeklyProfits[i];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_weekLabels[i],
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                            Text(
                              formatMoney(v),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: v >= 0 ? AppColors.positive : AppColors.negative,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),

                    const SizedBox(height: 22),
                    const SectionTitle('وضعیت کلی'),
                    const Divider(color: AppColors.gridLine, height: 1),
                    _StatLine(label: 'پروژه‌های در حال انجام', value: '${pn(_activeProjectsCount)} مورد'),
                    _StatLine(label: 'تعداد اشخاص ثبت‌شده', value: '${pn(_clientsCount)} نفر'),

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

/// نمودار میله‌ای سود/زیان ۴ هفته اخیر
class _WeeklyProfitChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  const _WeeklyProfitChart({required this.values, required this.labels});

  @override
  Widget build(BuildContext context) {
    final maxAbs = values.fold<double>(1, (m, v) => v.abs() > m ? v.abs() : m);
    final ceiling = maxAbs * 1.25;

    return SizedBox(
      height: 150,
      child: BarChart(
        BarChartData(
          maxY: ceiling,
          minY: -ceiling,
          barTouchData: BarTouchData(enabled: false),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: ceiling,
            getDrawingHorizontalLine: (_) => const FlLine(color: AppColors.gridLine, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(labels[i],
                        style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary)),
                  );
                },
              ),
            ),
          ),
          barGroups: List.generate(values.length, (i) {
            final v = values[i];
            return BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: v,
                  color: v >= 0 ? AppColors.positive : AppColors.negative,
                  width: 22,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
