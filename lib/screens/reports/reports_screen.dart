import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../db/database_helper.dart';
import '../../models/project_transaction.dart';
import '../../models/office_expense.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/stat_card.dart';

const _chartColors = [
  AppColors.brass,
  AppColors.positive,
  AppColors.negative,
  Color(0xFF5E9BD6),
  Color(0xFF9C7FD4),
  Color(0xFFD98E4A),
  Color(0xFF6FBF9A),
];

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  final _db = DatabaseHelper.instance;

  String _fromDate = '';
  String _toDate = '';

  double _received = 0;
  double _paid = 0;
  double _officeExpenses = 0;
  Map<String, double> _categoryBreakdown = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = todayJalaliString();
    _toDate = now;
    _fromDate = now; // پیش‌فرض: کل بازه (بدون فیلتر مؤثر در محاسبه کلی زیر)
    _load();
  }

  bool _inRange(String date) {
    if (_fromDate.isEmpty || _toDate.isEmpty) return true;
    final d = parseJalaliString(date);
    final from = parseJalaliString(_fromDate);
    final to = parseJalaliString(_toDate);
    if (d == null || from == null || to == null) return true;
    return !d.compareTo(from).isNegative && !to.compareTo(d).isNegative;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final txs = await _db.getTransactions();
    final expenses = await _db.getExpenses();

    final filteredTxs = txs.where((t) => _inRange(t.date)).toList();
    final filteredExpenses = expenses.where((e) => _inRange(e.date)).toList();

    final received = filteredTxs
        .where((t) => t.type == kTxReceipt)
        .fold<double>(0, (s, t) => s + t.amount);
    final paid = filteredTxs
        .where((t) => t.type == kTxPayment)
        .fold<double>(0, (s, t) => s + t.amount);
    final officeTotal = filteredExpenses.fold<double>(0, (s, e) => s + e.amount);

    final Map<String, double> breakdown = {};
    for (final e in filteredExpenses) {
      breakdown[e.category] = (breakdown[e.category] ?? 0) + e.amount;
    }

    setState(() {
      _received = received;
      _paid = paid;
      _officeExpenses = officeTotal;
      _categoryBreakdown = breakdown;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final net = _received - _paid - _officeExpenses;
    return Scaffold(
      appBar: AppBar(title: const Text('گزارش سود و زیان')),
      body: BlueprintGridBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: JalaliDateField(
                          label: 'از تاریخ',
                          value: _fromDate,
                          onChanged: (v) {
                            _fromDate = v;
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: JalaliDateField(
                          label: 'تا تاریخ',
                          value: _toDate,
                          onChanged: (v) {
                            _toDate = v;
                            _load();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 1.5,
                    children: [
                      StatCard(
                        title: 'دریافتی پروژه‌ها',
                        value: formatMoney(_received),
                        icon: Icons.south_west_rounded,
                        valueColor: AppColors.positive,
                      ),
                      StatCard(
                        title: 'پرداختی پروژه‌ها',
                        value: formatMoney(_paid),
                        icon: Icons.north_east_rounded,
                        valueColor: AppColors.negative,
                      ),
                      StatCard(
                        title: 'هزینه عمومی دفتر',
                        value: formatMoney(_officeExpenses),
                        icon: Icons.store_outlined,
                        valueColor: AppColors.negative,
                      ),
                      StatCard(
                        title: 'سود / زیان خالص',
                        value: formatMoney(net),
                        icon: Icons.trending_up_rounded,
                        valueColor: net >= 0 ? AppColors.positive : AppColors.negative,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text('توزیع هزینه‌های عمومی به تفکیک دسته',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  if (_categoryBreakdown.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Text('هزینه‌ای در این بازه ثبت نشده',
                          style: TextStyle(color: AppColors.textSecondary)),
                    )
                  else ...[
                    SizedBox(
                      height: 200,
                      child: PieChart(
                        PieChartData(
                          sections: _buildSections(),
                          sectionsSpace: 2,
                          centerSpaceRadius: 40,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._categoryBreakdown.entries.toList().asMap().entries.map((entry) {
                      final idx = entry.key;
                      final e = entry.value;
                      final color = _chartColors[idx % _chartColors.length];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            Container(
                                width: 12, height: 12,
                                decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Expanded(child: Text(e.key)),
                            Text(formatMoney(e.value)),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
      ),
    );
  }

  List<PieChartSectionData> _buildSections() {
    final total = _categoryBreakdown.values.fold<double>(0, (s, v) => s + v);
    final entries = _categoryBreakdown.entries.toList();
    return List.generate(entries.length, (i) {
      final e = entries[i];
      final pct = total == 0 ? 0 : (e.value / total * 100);
      return PieChartSectionData(
        value: e.value,
        color: _chartColors[i % _chartColors.length],
        title: '${pct.toStringAsFixed(0)}٪',
        radius: 60,
        titleStyle: const TextStyle(
            fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15100A)),
      );
    });
  }
}
