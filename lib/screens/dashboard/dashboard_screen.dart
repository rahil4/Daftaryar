import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/stat_card.dart';
import '../settings/settings_screen.dart';
import '../journal/journal_list_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = DatabaseHelper.instance;
  bool _loading = true;

  double _assetBalance = 0;
  double _income = 0;
  double _expense = 0;
  double _netProfit = 0;
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
      _assetBalance = summary['assetBalance']!;
      _income = summary['income']!;
      _expense = summary['expense']!;
      _netProfit = summary['netProfit']!;
      _activeProjectsCount = projects.where((p) => p.status == 'در حال انجام').length;
      _clientsCount = clients.length;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('دفتریار'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: BlueprintGridBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text('خلاصه وضعیت مالی', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.5,
                      children: [
                        StatCard(
                          title: 'مانده حساب‌های دارایی',
                          value: formatMoney(_assetBalance),
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                        StatCard(
                          title: 'جمع درآمد',
                          value: formatMoney(_income),
                          icon: Icons.south_west_rounded,
                          valueColor: AppColors.positive,
                        ),
                        StatCard(
                          title: 'جمع هزینه',
                          value: formatMoney(_expense),
                          icon: Icons.north_east_rounded,
                          valueColor: AppColors.negative,
                        ),
                        StatCard(
                          title: 'سود / زیان خالص',
                          value: formatMoney(_netProfit),
                          icon: Icons.trending_up_rounded,
                          valueColor: _netProfit >= 0 ? AppColors.positive : AppColors.negative,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('نمای کلی', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            title: 'پروژه‌های در حال انجام',
                            value: '$_activeProjectsCount',
                            icon: Icons.work_history_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: StatCard(
                            title: 'تعداد کارفرمایان',
                            value: '$_clientsCount',
                            icon: Icons.people_alt_outlined,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.push(context,
                          MaterialPageRoute(builder: (_) => const JournalListScreen())),
                      icon: const Icon(Icons.add),
                      label: const Text('ثبت سند حسابداری جدید'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
