import 'package:flutter/material.dart';

import '../../models/management_dashboard_data.dart';
import '../../models/operational_performance.dart';
import '../../services/operational_performance_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/dashboard_period.dart';
import '../../utils/formatters.dart';
import '../dashboard/widgets/period_selector_widget.dart';
import '../dashboard/widgets/trend_chart_widget.dart';

/// صفحه مستقل تحلیل عملکرد عملیاتی. فقط مصرف‌کننده ViewModel آماده از
/// OperationalPerformanceService است؛ هیچ دسترسی مستقیمی به دیتابیس ندارد.
class OperationalPerformanceScreen extends StatefulWidget {
  final bool embedded;
  const OperationalPerformanceScreen({super.key, this.embedded = false});

  @override
  State<OperationalPerformanceScreen> createState() => _OperationalPerformanceScreenState();
}

class _OperationalPerformanceScreenState extends State<OperationalPerformanceScreen> {
  final _service = OperationalPerformanceService();
  DashboardPeriodPreset _preset = DashboardPeriodPreset.thisMonth;
  OperationalPerformanceData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final range = await _service.resolvePeriod(_preset);
    final data = await _service.buildOperationalPerformance(period: range);
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  String _fmt(double? v, {bool pct = false, bool points = false}) {
    if (v == null) return '—';
    if (points) return '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)} واحد درصد';
    return pct ? '${v.toStringAsFixed(1)}٪' : formatMoney(v);
  }

  @override
  Widget build(BuildContext context) {
    final content = RefreshIndicator(
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
          else if (_data != null)
            _buildContent(_data!)
        ],
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('عملکرد عملیاتی')),
      body: BlueprintGridBackground(child: content),
    );
  }

  Widget _buildContent(OperationalPerformanceData d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(d.periodLabel, style: const TextStyle(color: AppColors.brass, fontWeight: FontWeight.w700)),
        if (d.warnings.isNotEmpty) ...[
          const SizedBox(height: 8),
          ...d.warnings.map((w) => Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.textSecondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(w, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              )),
        ],
        if (d.alerts.isNotEmpty) ...[
          _section('هشدارها'),
          ...d.alerts.map((a) => Card(
                child: ListTile(
                  leading: Icon(Icons.warning_amber_rounded,
                      color: a.severity == ManagementAlertSeverity.error
                          ? AppColors.negative
                          : AppColors.brass),
                  title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(a.message),
                ),
              )),
        ],
        _section('فعالیت پروژه‌ها'),
        _statsGrid([
          _stat('کل پروژه‌ها', pn(d.projectCount)),
          _stat('پروژه جدید در بازه', pn(d.newProjectCount)),
          _stat('نهایی‌شده در بازه', pn(d.finalizedProjectCount)),
          _stat('تسویه‌شده (فعلی)', pn(d.settledProjectCount)),
          _stat('باز (فعلی)', pn(d.openProjectCount)),
          _stat('لغوشده', pn(d.cancelledProjectCount)),
        ]),
        _section('حجم پروژه در برابر حجم مالی'),
        _statsGrid([
          _stat('درآمد به‌ازای هر پروژه نهایی‌شده', _fmt(d.revenuePerFinalizedProject)),
          _stat('سود ناخالص به‌ازای هر پروژه', _fmt(d.contributionPerFinalizedProject)),
          _stat('میانگین حاشیه پروژه‌ها (نه نسبت تجمعی)', _fmt(d.averageProjectMargin, pct: true)),
        ]),
        _section('عملکرد مالی بازه (بر مبنای تاریخ سند)'),
        _statsGrid([
          _stat('درآمد خالص', _fmt(d.finalizedRevenue)),
          _stat('هزینه مستقیم', _fmt(d.finalizedDirectCost)),
          _stat('سود ناخالص', _fmt(d.finalizedContribution)),
          _stat('حاشیه سود تجمعی بازه', _fmt(d.finalizedContributionMargin, pct: true)),
        ]),
        _section('رشد نسبت به دوره قبل'),
        _statsGrid([
          _stat('رشد درآمد', _fmt(d.revenueGrowthRate, pct: true)),
          _stat('رشد میانگین درآمد هر پروژه', _fmt(d.averageRevenueGrowthRate, pct: true)),
          _stat('رشد سود ناخالص', _fmt(d.contributionGrowthRate, pct: true)),
          _stat('رشد حجم پروژه', _fmt(d.projectVolumeGrowthRate, pct: true)),
          _stat('تغییر حاشیه سود', _fmt(d.contributionMarginChangePoints, points: true)),
        ]),
        _section('توزیع نتیجه پروژه‌های نهایی‌شده'),
        _statsGrid([
          _stat('زیان‌ده', pn(d.lossProjectCount)),
          _stat('حاشیه پایین', pn(d.lowMarginProjectCount)),
          _stat('حاشیه متعارف', pn(d.normalMarginProjectCount)),
          _stat('حاشیه بالا', pn(d.highMarginProjectCount)),
          _stat('نرخ زیان‌دهی', _fmt(d.lossProjectRate, pct: true)),
        ]),
        _section('قیمت‌گذاری و تخفیف (بر مبنای تاریخ رویداد)'),
        _statsGrid([
          _stat('مجموع افزایش قیمت', _fmt(d.totalPriceAdditions)),
          _stat('مجموع کاهش قیمت', _fmt(d.totalPriceReductions)),
          _stat('خالص تغییر قیمت', _fmt(d.netPriceChange)),
          _stat('مجموع تخفیف', _fmt(d.totalDiscount)),
          _stat('نرخ تخفیف', _fmt(d.discountRate, pct: true)),
        ]),
        _section('وصول مطالبات'),
        _statsGrid([
          _stat('دریافتی بازه', _fmt(d.totalReceived)),
          _stat('مانده طلب (پایان بازه)', _fmt(d.receivableBalance)),
          _stat('بستانکاری مشتری (پایان بازه)', _fmt(d.customerCredit)),
          _stat('نسبت دریافت نقدی به درآمد دوره', _fmt(d.periodReceiptToRevenueRatio, pct: true)),
          _stat('نرخ وصول مطالبات این بازه', _fmt(d.periodArCollectionRate, pct: true)),
          _stat('شکاف وصول', _fmt(d.collectionGap)),
        ]),
        _section('تمرکز مشتری (کل عمر داده‌ها)'),
        _statsGrid([
          _stat('سهم مشتری برتر', _fmt(d.top1CustomerRevenueShare, pct: true)),
          _stat('سهم ۳ مشتری برتر', _fmt(d.top3CustomerRevenueShare, pct: true)),
          _stat('سهم ۵ مشتری برتر', _fmt(d.top5CustomerRevenueShare, pct: true)),
        ]),
        _section('پروژه‌های در جریان (WIP) — برآورد اولیه، نه درآمد قطعی'),
        _statsGrid([
          _stat('تعداد پروژه در جریان', pn(d.wipProjectCount)),
          _stat('مجموع برآورد اولیه', _fmt(d.wipInitialEstimate)),
          _stat('هزینه مستقیم ثبت‌شده', _fmt(d.wipDirectCost)),
          _stat('دریافتی (پیش‌دریافت)', _fmt(d.wipReceived)),
        ]),
        _section('روند ماهانه (Observed - نه پیش‌بینی)'),
        TrendChartWidget(title: 'روند درآمد', points: d.revenueTrend, color: AppColors.positive),
        const SizedBox(height: 10),
        TrendChartWidget(title: 'روند سود ناخالص', points: d.contributionTrend, color: AppColors.info),
        const SizedBox(height: 10),
        TrendChartWidget(title: 'روند تعداد پروژه نهایی‌شده', points: d.projectVolumeTrend, color: AppColors.brass),
        const SizedBox(height: 10),
        TrendChartWidget(title: 'روند مانده مطالبات', points: d.receivableTrend, color: AppColors.negative),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
    );
  }

  Widget _statsGrid(List<Widget> items) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.9,
      children: items,
    );
  }

  Widget _stat(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}
