import 'package:flutter/material.dart';

import '../../../models/financial_reports.dart';
import '../../../models/management_dashboard_data.dart';
import '../../../models/operational_performance.dart';
import '../../../services/operational_performance_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/dashboard_period.dart';
import '../../../utils/formatters.dart';
import '../../../utils/reloadable.dart';
import '../../../widgets/stat_card.dart';
import '../../dashboard/widgets/period_selector_widget.dart';
import '../../dashboard/widgets/trend_chart_widget.dart';

const Map<String, String> _kComparisonLabels = {
  'revenue': 'درآمد',
  'contribution': 'سود ناخالص',
  'projectVolume': 'تعداد پروژه Finalize‌شده',
  'periodReceiptToRevenueRatio': 'نسبت دریافتی به درآمد',
  'receivable': 'مانده مطالبات',
};

/// تب «عملکرد عملیاتی» گزارش‌ها - صرفاً نمایش‌دهنده خروجی
/// OperationalPerformanceService است؛ هیچ محاسبه مالی مستقلی در این فایل
/// انجام نمی‌شود.
class OperationalPerformanceTab extends StatefulWidget {
  const OperationalPerformanceTab({super.key});

  @override
  State<OperationalPerformanceTab> createState() => _OperationalPerformanceTabState();
}

class _OperationalPerformanceTabState extends State<OperationalPerformanceTab>
    implements Reloadable<OperationalPerformanceTab> {
  final _service = OperationalPerformanceService();
  DashboardPeriodPreset _preset = DashboardPeriodPreset.thisMonth;
  OperationalPerformanceData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final period = await _service.resolvePeriod(_preset);
      final data = await _service.buildOperationalPerformance(period: period);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        _loading = false;
      });
    }
  }

  void _onPresetChanged(DashboardPeriodPreset preset) {
    setState(() => _preset = preset);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: [
          PeriodSelectorWidget(selected: _preset, onChanged: _onPresetChanged),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 60),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 40),
              child: Center(child: Text(_error!, style: const TextStyle(color: AppColors.negative))),
            )
          else if (_data != null)
            ..._buildSections(_data!),
        ],
      ),
    );
  }

  List<Widget> _buildSections(OperationalPerformanceData d) {
    return [
      Text(d.periodLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      _sectionTitle('فعالیت پروژه‌ها در این بازه'),
      _grid([
        StatCard(title: 'پروژه جدید', value: pn(d.newProjectCount)),
        StatCard(title: 'Finalize‌شده', value: pn(d.finalizedProjectCount)),
        StatCard(title: 'در جریان (وضعیت فعلی)', value: pn(d.openProjectCount)),
        StatCard(title: 'لغو‌شده', value: pn(d.cancelledProjectCount)),
      ]),
      _sectionTitle('عملکرد مالی بازه (پروژه‌های Finalize‌شده)'),
      _grid([
        StatCard(title: 'درآمد', value: formatMoney(d.finalizedRevenue), color: AppColors.positive),
        StatCard(title: 'هزینه مستقیم', value: formatMoney(d.finalizedDirectCost), color: AppColors.negative),
        StatCard(
          title: 'سود ناخالص',
          value: d.finalizedContribution == null ? '—' : formatMoney(d.finalizedContribution!),
          color: AppColors.teal,
        ),
        StatCard(title: 'حاشیه سود (تجمعی)', value: _pct(d.finalizedContributionMargin)),
        StatCard(
          title: 'درآمد به ازای هر پروژه',
          value: d.revenuePerFinalizedProject == null ? '—' : formatMoney(d.revenuePerFinalizedProject!),
        ),
        StatCard(title: 'میانگین حاشیه سود پروژه‌ها', value: _pct(d.averageProjectMargin)),
      ]),
      if (d.comparisons.isNotEmpty) ...[
        _sectionTitle('رشد نسبت به دوره مشابه قبل'),
        Card(
          child: Column(
            children: d.comparisons.map(_comparisonRow).toList(),
          ),
        ),
      ],
      _sectionTitle('پراکندگی سودآوری پروژه‌های Finalize‌شده'),
      _grid([
        StatCard(title: 'زیان‌ده', value: pn(d.lossProjectCount), color: AppColors.negative),
        StatCard(title: 'حاشیه کم', value: pn(d.lowMarginProjectCount), color: AppColors.brass),
        StatCard(title: 'حاشیه عادی', value: pn(d.normalMarginProjectCount)),
        StatCard(title: 'حاشیه بالا', value: pn(d.highMarginProjectCount), color: AppColors.positive),
      ]),
      _sectionTitle('تمرکز درآمد روی مشتریان (کل دوره فعالیت)'),
      _grid([
        StatCard(title: 'سهم ۱ مشتری برتر', value: _pct(d.top1CustomerRevenueShare)),
        StatCard(title: 'سهم ۳ مشتری برتر', value: _pct(d.top3CustomerRevenueShare)),
        StatCard(title: 'سهم ۵ مشتری برتر', value: _pct(d.top5CustomerRevenueShare)),
      ]),
      _sectionTitle('تغییر قیمت و تخفیف (بر مبنای تاریخ ثبت)'),
      _grid([
        StatCard(title: 'افزایش قیمت', value: formatMoney(d.totalPriceAdditions), color: AppColors.positive),
        StatCard(title: 'کاهش قیمت', value: formatMoney(d.totalPriceReductions), color: AppColors.negative),
        StatCard(
          title: 'تغییر خالص قیمت',
          value: formatMoney(d.netPriceChange),
          color: d.netPriceChange >= 0 ? AppColors.positive : AppColors.negative,
        ),
        StatCard(title: 'مجموع تخفیف', value: formatMoney(d.totalDiscount), color: AppColors.negative),
        StatCard(title: 'نرخ تخفیف', value: _pct(d.discountRate)),
      ]),
      _sectionTitle('وصول مطالبات'),
      _grid([
        StatCard(title: 'دریافتی این بازه', value: formatMoney(d.totalReceived), color: AppColors.positive),
        StatCard(title: 'مانده مطالبات (پایان بازه)', value: formatMoney(d.receivableBalance)),
        StatCard(title: 'پیش‌دریافت مشتریان (پایان بازه)', value: formatMoney(d.customerCredit)),
        StatCard(title: 'نرخ وصول مطالبات این بازه', value: _pct(d.periodArCollectionRate)),
      ]),
      _sectionTitle('کارهای در جریان (وضعیت فعلی)'),
      _grid([
        StatCard(title: 'تعداد پروژه در جریان', value: pn(d.wipProjectCount)),
        StatCard(title: 'برآورد اولیه', value: formatMoney(d.wipInitialEstimate)),
        StatCard(title: 'هزینه مستقیم ثبت‌شده', value: formatMoney(d.wipDirectCost), color: AppColors.negative),
        StatCard(title: 'دریافتی تاکنون', value: formatMoney(d.wipReceived), color: AppColors.positive),
      ]),
      if (d.revenueTrend.isNotEmpty) ...[
        _sectionTitle('روند ماهانه'),
        TrendChartWidget(title: 'درآمد', points: d.revenueTrend, color: AppColors.brass),
        const SizedBox(height: 12),
        TrendChartWidget(title: 'سود ناخالص', points: d.contributionTrend, color: AppColors.teal),
        const SizedBox(height: 12),
        TrendChartWidget(title: 'تعداد پروژه Finalize‌شده', points: d.projectVolumeTrend, color: AppColors.info),
        const SizedBox(height: 12),
        TrendChartWidget(title: 'مانده مطالبات', points: d.receivableTrend, color: AppColors.negative),
      ],
      if (d.alerts.isNotEmpty) ...[
        _sectionTitle('هشدارها'),
        ...d.alerts.map(_alertTile),
      ],
      if (d.diagnostics.hasIssues) ...[
        _sectionTitle('ناسازگاری‌های داده (نیازمند بررسی)'),
        _diagnosticsCard(d.diagnostics),
      ],
      if (d.warnings.isNotEmpty) ...[
        const SizedBox(height: 16),
        ...d.warnings.map((w) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(w, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
            )),
      ],
    ];
  }

  Widget _sectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
    );
  }

  Widget _grid(List<Widget> cards) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: cards,
    );
  }

  String _pct(double? v) => v == null ? '—' : '${pn(v.toStringAsFixed(1))}٪';

  Widget _comparisonRow(FinancialPeriodComparison c) {
    final label = _kComparisonLabels[c.metricName] ?? c.metricName;
    final isCount = c.metricName == 'projectVolume';
    final isRatio = c.metricName == 'periodReceiptToRevenueRatio';
    String fmt(double v) => isCount ? pn(v.round()) : (isRatio ? '${pn(v.toStringAsFixed(1))}٪' : formatMoney(v));
    final rate = c.growthRate;
    final positive = rate != null && rate >= 0;
    return ListTile(
      dense: true,
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text('دوره قبل: ${c.previousValue == null ? '—' : fmt(c.previousValue!)}',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      trailing: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(fmt(c.currentValue), style: const TextStyle(fontWeight: FontWeight.w700)),
          if (rate != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(positive ? Icons.trending_up : Icons.trending_down,
                    size: 14, color: positive ? AppColors.positive : AppColors.negative),
                const SizedBox(width: 2),
                Text('${pn(rate.abs().toStringAsFixed(1))}٪',
                    style: TextStyle(
                        fontSize: 11, color: positive ? AppColors.positive : AppColors.negative)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _alertTile(ManagementAlert a) {
    final color = a.severity == ManagementAlertSeverity.error
        ? AppColors.negative
        : (a.severity == ManagementAlertSeverity.warning ? AppColors.brass : AppColors.textSecondary);
    return Card(
      child: ListTile(
        leading: Icon(Icons.warning_amber_rounded, color: color),
        title: Text(a.title, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
        subtitle: Text(a.message),
      ),
    );
  }

  Widget _diagnosticsCard(FinancialReportDiagnostics diag) {
    final rows = <Widget>[];
    void addRow(String label, int count) {
      if (count == 0) return;
      rows.add(ListTile(
        dense: true,
        title: Text(label),
        trailing: Text(pn(count), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.negative)),
      ));
    }

    addRow('ناسازگاری درآمد محاسبه‌شده با Ledger', diag.revenueLedgerMismatchCount);
    addRow('مانده منفی مطالبات', diag.negativeARCount);
    addRow('مانده منفی پیش‌دریافت', diag.negativeAdvanceCount);
    addRow('مانده منفی اعتبار مشتری', diag.negativeCustomerCreditCount);
    addRow('خطای تطبیق نقدی', diag.cashReconciliationErrors);
    return Card(child: Column(children: rows));
  }
}
