import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/management_dashboard_data.dart';
import '../../services/management_dashboard_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/dashboard_period.dart';
import '../../utils/formatters.dart';
import '../journal/quick_receipt_screen.dart';
import '../journal/quick_expense_screen.dart';
import '../settings/settings_screen.dart';
import '../sms_drafts/sms_drafts_screen.dart';
import 'widgets/dashboard_sections.dart';
import 'widgets/period_selector_widget.dart';
import 'widgets/trend_chart_widget.dart';
import '../operational/operational_performance_screen.dart';

/// تب یکپارچه «داشبورد» - ادغام داشبورد سریع پیشین (اقدامات سریع + پیش‌نویس
/// پیامکی) با داشبورد مدیریتی (ManagementDashboardService). این صفحه فقط
/// مصرف‌کننده ManagementDashboardService است و هیچ محاسبه مالی مستقلی انجام
/// نمی‌دهد.
class ManagementDashboardScreen extends StatefulWidget {
  const ManagementDashboardScreen({super.key});

  @override
  State<ManagementDashboardScreen> createState() => _ManagementDashboardScreenState();
}

class _ManagementDashboardScreenState extends State<ManagementDashboardScreen> {
  final _service = ManagementDashboardService();
  final _db = DatabaseHelper.instance;
  DashboardPeriodPreset _preset = DashboardPeriodPreset.thisMonth;
  ManagementDashboardData? _data;
  bool _loading = true;
  String? _error;
  int _pendingSmsDrafts = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final pendingDrafts = await _db.countPendingSmsDrafts();
    try {
      final data = await _service.buildDashboard(preset: _preset);
      setState(() {
        _data = data;
        _pendingSmsDrafts = pendingDrafts;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _pendingSmsDrafts = pendingDrafts;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('داشبورد'),
        actions: [
          IconButton(
            icon: const Icon(Icons.query_stats_outlined),
            tooltip: 'عملکرد عملیاتی',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OperationalPerformanceScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'تنظیمات',
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: BlueprintGridBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _QuickActionsRow(onDone: _load),
              if (_pendingSmsDrafts > 0) ...[
                const SizedBox(height: 10),
                _PendingSmsBanner(count: _pendingSmsDrafts, onTap: _load),
              ],
              const SizedBox(height: 16),
              PeriodSelectorWidget(
                selected: _preset,
                onChanged: (p) {
                  setState(() => _preset = p);
                  _load();
                },
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text('خطا در بارگذاری داشبورد: $_error',
                      style: const TextStyle(color: AppColors.negative)),
                )
              else if (_data != null)
                _buildContent(_data!)
              else
                const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(ManagementDashboardData data) {
    final hasAnyActivity = data.allProjects.isNotEmpty ||
        data.netRevenue.value != 0 ||
        data.customerReceipts != 0 ||
        data.otherCashInflows != 0;

    if (!hasAnyActivity) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Center(
          child: Text('هیچ فعالیت مالی‌ای در بازه انتخاب‌شده ثبت نشده است.',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(data.periodLabel, style: const TextStyle(color: AppColors.brass, fontWeight: FontWeight.w700)),
        AlertsSection(data: data),
        KpiOverviewSection(data: data),
        CashPositionSection(data: data),
        const SizedBox(height: 16),
        _sectionTitle('روند ماهانه'),
        TrendChartWidget(title: 'روند درآمد خالص', points: data.revenueTrend, color: AppColors.positive),
        const SizedBox(height: 10),
        TrendChartWidget(title: 'روند نتیجه عملیاتی', points: data.operatingResultTrend, color: AppColors.info),
        const SizedBox(height: 10),
        TrendChartWidget(title: 'روند خالص تغییر نقدینگی', points: data.cashFlowTrend, color: AppColors.teal),
        const SizedBox(height: 10),
        TrendChartWidget(
            title: 'روند حاشیه سود', points: data.contributionMarginTrend, color: AppColors.brass),
        ReceivablesSection(data: data),
        const SizedBox(height: 8),
        SettlementSection(data: data),
        ProjectPerformanceSection(data: data),
        CustomerPerformanceSection(data: data),
        PricingSection(data: data),
        DiagnosticsSection(data: data),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
    );
  }
}

/// ردیف دو دکمه اقدام سریع (دریافت/پرداخت) - جایگزین دکمه شناور واحد،
/// چون هر دو عملیات به یک اندازه پرتکرارند
class _QuickActionsRow extends StatelessWidget {
  final VoidCallback onDone;
  const _QuickActionsRow({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            label: 'دریافت سریع',
            icon: Icons.south_west_rounded,
            color: AppColors.positive,
            onTap: () async {
              final result =
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const QuickReceiptScreen()));
              if (result == true) onDone();
            },
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            label: 'پرداخت سریع',
            icon: Icons.north_east_rounded,
            color: AppColors.negative,
            onTap: () async {
              final result =
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const QuickExpenseScreen()));
              if (result == true) onDone();
            },
          ),
        ),
      ],
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _QuickActionButton({required this.label, required this.icon, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gridLine),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 7),
            Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
          ],
        ),
      ),
    );
  }
}

/// بنر پیش‌نویس‌های پیامکی در انتظار تأیید - منتقل‌شده از DashboardScreen قدیمی
class _PendingSmsBanner extends StatelessWidget {
  final int count;
  final VoidCallback onTap;
  const _PendingSmsBanner({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const SmsDraftsScreen()));
        onTap();
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
              '${pn(count)} پیش‌نویس پیامکی در انتظار تأیید',
              style: const TextStyle(fontSize: 13, color: AppColors.brass, fontWeight: FontWeight.w700),
            ),
            const Text('‹', style: TextStyle(color: AppColors.brass, fontSize: 16)),
          ],
        ),
      ),
    );
  }
}
