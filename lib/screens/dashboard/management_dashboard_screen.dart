import 'package:flutter/material.dart';

import '../../models/management_dashboard_data.dart';
import '../../services/management_dashboard_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/dashboard_period.dart';
import 'widgets/dashboard_sections.dart';
import 'widgets/period_selector_widget.dart';
import 'widgets/trend_chart_widget.dart';
import '../operational/operational_performance_screen.dart';

/// صفحه اصلی داشبورد مدیریتی. این صفحه فقط مصرف‌کننده ManagementDashboardService
/// است و هیچ محاسبه مالی مستقلی انجام نمی‌دهد.
class ManagementDashboardScreen extends StatefulWidget {
  const ManagementDashboardScreen({super.key});

  @override
  State<ManagementDashboardScreen> createState() => _ManagementDashboardScreenState();
}

class _ManagementDashboardScreenState extends State<ManagementDashboardScreen> {
  final _service = ManagementDashboardService();
  DashboardPeriodPreset _preset = DashboardPeriodPreset.thisMonth;
  ManagementDashboardData? _data;
  bool _loading = true;
  String? _error;

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
    try {
      final data = await _service.buildDashboard(preset: _preset);
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('داشبورد مدیریتی'),
        actions: [
          IconButton(
            icon: const Icon(Icons.query_stats_outlined),
            tooltip: 'عملکرد عملیاتی',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const OperationalPerformanceScreen()),
            ),
          ),
        ],
      ),
      body: BlueprintGridBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
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
