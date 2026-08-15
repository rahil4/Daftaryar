import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
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

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارش‌ها'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'سود و زیان'),
            Tab(text: 'تراز آزمایشی'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [_ProfitLossTab(), _TrialBalanceTab()],
      ),
    );
  }
}

class _ProfitLossTab extends StatefulWidget {
  const _ProfitLossTab();

  @override
  State<_ProfitLossTab> createState() => _ProfitLossTabState();
}

class _ProfitLossTabState extends State<_ProfitLossTab> {
  final _db = DatabaseHelper.instance;
  String _fromDate = '';
  String _toDate = '';
  double _income = 0;
  double _expense = 0;
  Map<String, double> _breakdown = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _toDate = todayJalaliString();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final incomeAccounts = await _db.getAccounts(type: kAccountIncome);
    double income = 0;
    for (final a in incomeAccounts) {
      final bal = await _db.accountBalance(a.id!,
          fromDate: _fromDate.isEmpty ? null : _fromDate,
          toDate: _toDate.isEmpty ? null : _toDate);
      income += bal['balance']!;
    }
    final breakdown = await _db.expenseBreakdown(
        fromDate: _fromDate.isEmpty ? null : _fromDate,
        toDate: _toDate.isEmpty ? null : _toDate);
    final expense = breakdown.values.fold<double>(0, (s, v) => s + v);
    setState(() {
      _income = income;
      _expense = expense;
      _breakdown = breakdown;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final net = _income - _expense;
    return BlueprintGridBackground(
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
                Row(
                  children: [
                    Expanded(
                      child: StatCard(
                        title: 'جمع درآمد',
                        value: formatMoney(_income),
                        icon: Icons.south_west_rounded,
                        valueColor: AppColors.positive,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: StatCard(
                        title: 'جمع هزینه',
                        value: formatMoney(_expense),
                        icon: Icons.north_east_rounded,
                        valueColor: AppColors.negative,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                StatCard(
                  title: 'سود / زیان خالص',
                  value: formatMoney(net),
                  icon: Icons.trending_up_rounded,
                  valueColor: net >= 0 ? AppColors.positive : AppColors.negative,
                ),
                const SizedBox(height: 24),
                Text('توزیع هزینه‌ها به تفکیک حساب', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                if (_breakdown.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('هزینه‌ای در این بازه ثبت نشده',
                        style: TextStyle(color: AppColors.textSecondary)),
                  )
                else ...[
                  SizedBox(
                    height: 200,
                    child: PieChart(
                      PieChartData(sections: _buildSections(), sectionsSpace: 2, centerSpaceRadius: 40),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._breakdown.entries.toList().asMap().entries.map((entry) {
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
    );
  }

  List<PieChartSectionData> _buildSections() {
    final total = _breakdown.values.fold<double>(0, (s, v) => s + v);
    final entries = _breakdown.entries.toList();
    return List.generate(entries.length, (i) {
      final e = entries[i];
      final pct = total == 0 ? 0 : (e.value / total * 100);
      return PieChartSectionData(
        value: e.value,
        color: _chartColors[i % _chartColors.length],
        title: '${pn(pct.toStringAsFixed(0))}٪',
        radius: 60,
        titleStyle:
            const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15100A)),
      );
    });
  }
}

class _TrialBalanceTab extends StatefulWidget {
  const _TrialBalanceTab();

  @override
  State<_TrialBalanceTab> createState() => _TrialBalanceTabState();
}

class _TrialBalanceTabState extends State<_TrialBalanceTab> {
  final _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _db.trialBalance();
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final totalDebit = _rows.fold<double>(0, (s, r) => s + (r['debit'] as double));
    final totalCredit = _rows.fold<double>(0, (s, r) => s + (r['credit'] as double));

    return BlueprintGridBackground(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final row in _rows)
                    if ((row['debit'] as double) != 0 || (row['credit'] as double) != 0)
                      Card(
                        child: ListTile(
                          dense: true,
                          title: Text((row['account'] as AccountModel).name),
                          subtitle: Text('بدهکار: ${formatMoney((row['debit'] as double), withSuffix: false)} '
                              '· بستانکار: ${formatMoney((row['credit'] as double), withSuffix: false)}'),
                          trailing: Text(
                            formatMoney((row['balance'] as double).abs(), withSuffix: false),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  const SizedBox(height: 12),
                  Card(
                    color: AppColors.surfaceAlt,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('جمع کل بدهکار'),
                              Text(formatMoney(totalDebit)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('جمع کل بستانکار'),
                              Text(formatMoney(totalCredit)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
