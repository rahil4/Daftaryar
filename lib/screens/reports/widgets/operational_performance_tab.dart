import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../models/financial_reports.dart';
import '../../../models/management_dashboard_data.dart';
import '../../../models/operational_performance.dart';
import '../../../services/operational_performance_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/dashboard_period.dart';
import '../../../utils/formatters.dart';
import '../../../utils/reloadable.dart';
import '../../../widgets/metric_strip.dart';
import '../../../widgets/page_header.dart' show BlockHeading;
import '../../../widgets/period_segmented_control.dart';
import '../../../widgets/progress_meter.dart';
import '../../dashboard/widgets/trend_chart_widget.dart';

const Map<String, String> _kComparisonLabels = {
  'revenue': 'درآمد',
  'contribution': 'سود ناخالص',
  'projectVolume': 'تعداد پروژه نهایی‌شده',
  'periodReceiptToRevenueRatio': 'نسبت دریافتی به درآمد',
  'receivable': 'مانده مطالبات',
};

/// تب «عملکرد» گزارش‌ها - صرفاً نمایش‌دهنده خروجی
/// OperationalPerformanceService است؛ هیچ محاسبه مالی مستقلی در این فایل
/// انجام نمی‌شود (فقط درصد‌گیری نمایشی برای پهنای نوارها).
class OperationalPerformanceTab extends StatefulWidget {
  const OperationalPerformanceTab({super.key});

  @override
  State<OperationalPerformanceTab> createState() => _OperationalPerformanceTabState();
}

class _OperationalPerformanceTabState extends State<OperationalPerformanceTab>
    implements Reloadable<OperationalPerformanceTab> {
  final _service = OperationalPerformanceService();
  DashboardPeriodPreset _preset = DashboardPeriodPreset.thisMonth;
  String _customFrom = defaultCustomPeriodRange().from;
  String _customTo = defaultCustomPeriodRange().to;
  OperationalPerformanceData? _data;
  bool _loading = true;
  String? _error;
  // نتیجه دیرتر-رسیده یک بارگذاری قدیمی نباید روی نتیجه جدید بنشیند.
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Future<void> reload() => _load();

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final period = await _service.resolvePeriod(_preset, customFrom: _customFrom, customTo: _customTo);
      final data = await _service.buildOperationalPerformance(period: period);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        // اعداد قبلی کنار پیام خطا نمی‌مانند: معلوم نیست هنوز معتبرند.
        _data = null;
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
    return BlueprintGridBackground(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            PeriodSegmentedControl(
              selected: _preset,
              onChanged: _onPresetChanged,
              customFrom: _customFrom,
              customTo: _customTo,
              onCustomRangeChanged: (from, to) {
                setState(() {
                  _customFrom = from;
                  _customTo = to;
                });
                _load();
              },
            ),
            // هنگام تازه‌سازی، داده قبلی می‌ماند و فقط یک نوار باریک پیشرفت
            // می‌آید؛ چرخنده فقط برای اولین بارگذاری است.
            SizedBox(
              height: 8,
              child: (_loading && _data != null)
                  ? const Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(minHeight: 2))
                  : null,
            ),
            if (_data != null)
              ..._buildSections(_data!)
            else if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(child: Text(_error!, style: const TextStyle(color: AppColors.negative))),
              ),
          ],
        ),
      ),
    );
  }

  String _pct(double? v) => v == null ? '—' : '${pn(v.toStringAsFixed(1))}٪';
  String _money(double? v) => v == null ? '—' : formatMoney(v, withSuffix: false);

  List<Widget> _buildSections(OperationalPerformanceData d) {
    final finalizedTotal =
        d.lossProjectCount + d.lowMarginProjectCount + d.normalMarginProjectCount + d.highMarginProjectCount;
    final marginChange = d.contributionMarginChangePoints;
    return [
      // ---------- عدد اصلی ----------
      Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (d.finalizedContribution == null) ...[
              Text('سود ناخالص پروژه‌های نهایی‌شده · ${d.periodLabel}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              const Text('—', style: AppTextStyles.heroNumber),
            ] else
              HeroAmount(
                  label: 'سود ناخالص پروژه‌های نهایی‌شده · ${d.periodLabel}', amount: d.finalizedContribution!),
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('حاشیه سود ${_pct(d.finalizedContributionMargin)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                if (marginChange != null) ...[
                  const Text(' · ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  Icon(marginChange >= 0 ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                      size: 18, color: AppColors.textSecondary),
                  Text(
                    '${pn(marginChange.abs().toStringAsFixed(1))} واحد درصد ${marginChange >= 0 ? 'بیشتر' : 'کمتر'} از دوره قبل',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      // ---------- عملکرد مالی ----------
      MetricStrip(items: [
        MetricItem(label: 'درآمد', value: _money(d.finalizedRevenue), valueSize: 14),
        MetricItem(label: 'هزینه مستقیم', value: _money(d.finalizedDirectCost), valueSize: 14),
        MetricItem(label: 'میانگین هر پروژه', value: _money(d.revenuePerFinalizedProject), valueSize: 14),
      ]),
      const SizedBox(height: 12),
      // ---------- پروژه‌ها ----------
      MetricStrip(items: [
        MetricItem(label: 'پروژه جدید', value: pn(d.newProjectCount), valueSize: 18),
        MetricItem(label: 'نهایی‌شده', value: pn(d.finalizedProjectCount), valueSize: 18),
        MetricItem(label: 'در جریان (الان)', value: pn(d.openProjectCount), valueSize: 18),
      ]),
      if (d.cancelledProjectCount > 0)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('لغو‌شده (وضعیت فعلی): ${pn(d.cancelledProjectCount)}',
              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        ),
      if (d.comparisons.isNotEmpty) ...[
        const BlockHeading('رشد نسبت به دوره مشابه قبل'),
        SurfaceBox(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Column(
            children: [
              for (var i = 0; i < d.comparisons.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _comparisonRow(d.comparisons[i]),
              ],
            ],
          ),
        ),
      ],
      const SizedBox(height: 12),
      // ---------- سودآوری پروژه‌ها ----------
      _profitabilityCard(d, finalizedTotal),
      const SizedBox(height: 12),
      // ---------- وصول مطالبات ----------
      _collectionCard(d),
      const SizedBox(height: 12),
      // ---------- سهم مشتریان برتر ----------
      SurfaceBox(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('سهم مشتریان برتر از درآمد', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            const Text('کل دوره فعالیت، نه فقط این بازه',
                style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            _shareRow('۱ مشتری برتر', d.top1CustomerRevenueShare),
            const SizedBox(height: 10),
            _shareRow('۳ مشتری برتر', d.top3CustomerRevenueShare),
            const SizedBox(height: 10),
            _shareRow('۵ مشتری برتر', d.top5CustomerRevenueShare),
          ],
        ),
      ),
      // ---------- روند ماهانه ----------
      if (d.revenueTrend.isNotEmpty) ...[
        const SizedBox(height: 12),
        _MonthlyBarsCard(title: 'درآمد ماهانه', points: d.revenueTrend),
        const SizedBox(height: 12),
        TrendChartWidget(title: 'سود ناخالص', points: d.contributionTrend, color: AppColors.chartIncome),
        const SizedBox(height: 12),
        TrendChartWidget(title: 'تعداد پروژه نهایی‌شده', points: d.projectVolumeTrend, color: AppColors.chartExpense),
        const SizedBox(height: 12),
        TrendChartWidget(title: 'مانده مطالبات', points: d.receivableTrend, color: AppColors.rampLow),
      ],
      // ---------- تغییر قیمت و تخفیف ----------
      const BlockHeading('تغییر قیمت و تخفیف (بر مبنای تاریخ ثبت)'),
      _kvCard([
        ('افزایش قیمت', _money(d.totalPriceAdditions)),
        ('کاهش قیمت', _money(d.totalPriceReductions)),
        ('تغییر خالص قیمت', _money(d.netPriceChange)),
        ('مجموع تخفیف', _money(d.totalDiscount)),
        ('نرخ تخفیف', _pct(d.discountRate)),
      ]),
      // ---------- کارهای در جریان ----------
      const BlockHeading('کارهای در جریان (وضعیت فعلی)'),
      _kvCard([
        ('تعداد پروژه در جریان', pn(d.wipProjectCount)),
        ('برآورد اولیه', _money(d.wipInitialEstimate)),
        ('هزینه مستقیم ثبت‌شده', _money(d.wipDirectCost)),
        ('دریافتی تاکنون', _money(d.wipReceived)),
      ]),
      if (d.alerts.isNotEmpty) ...[
        const BlockHeading('هشدارها'),
        SurfaceBox(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < d.alerts.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _alertRow(d.alerts[i]),
              ],
            ],
          ),
        ),
      ],
      if (d.diagnostics.hasIssues) ...[
        const BlockHeading('ناسازگاری‌های داده (نیازمند بررسی)'),
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

  // ---------------- اجزا ----------------

  Widget _profitabilityCard(OperationalPerformanceData d, int total) {
    final segments = <({String label, int count, Color color, bool critical})>[
      (label: 'حاشیه بالا', count: d.highMarginProjectCount, color: AppColors.rampHigh, critical: false),
      (label: 'حاشیه عادی', count: d.normalMarginProjectCount, color: AppColors.rampMid, critical: false),
      (label: 'حاشیه کم', count: d.lowMarginProjectCount, color: AppColors.rampLow, critical: false),
      (label: 'زیان‌ده', count: d.lossProjectCount, color: AppColors.statusCritical, critical: true),
    ];
    return SurfaceBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(total == 0 ? 'سودآوری پروژه‌های نهایی‌شده' : 'سودآوری ${pn(total)} پروژه نهایی‌شده',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          if (total == 0)
            const Text('در این بازه پروژه نهایی‌شده‌ای نیست.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
          else ...[
            Semantics(
              label: 'از ${pn(total)} پروژه: ${segments.map((s) => '${pn(s.count)} ${s.label}').join('، ')}',
              child: SizedBox(
                height: 14,
                child: Row(
                  children: [
                    for (final s in segments)
                      if (s.count > 0)
                        Expanded(
                          flex: s.count,
                          child: Container(
                            margin: const EdgeInsetsDirectional.only(end: 2),
                            decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(4)),
                          ),
                        ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              runSpacing: 8,
              children: [
                for (final s in segments)
                  FractionallySizedBox(
                    widthFactor: 0.5,
                    child: Row(
                      children: [
                        // علامت زیان‌ده فقط به رنگ وابسته نیست: آیکن هشدار دارد.
                        s.critical
                            ? Icon(Icons.warning_amber_rounded, size: 12, color: s.color)
                            : Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3)),
                              ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(s.label,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ),
                        const SizedBox(width: 6),
                        Text(pn(s.count), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
              ],
            ),
            if (d.averageProjectMargin != null) ...[
              const SizedBox(height: 10),
              Text('میانگین حاشیه سود پروژه‌ها: ${_pct(d.averageProjectMargin)}',
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ],
          ],
        ],
      ),
    );
  }

  Widget _collectionCard(OperationalPerformanceData d) {
    final rate = d.periodArCollectionRate;
    final progress = rate == null ? 0.0 : rate / 100;
    return SurfaceBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              const Expanded(
                child: Text('وصول مطالبات', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              Text(_pct(rate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 10),
          ProgressMeter(
            value: progress,
            height: 8,
            color: AppColors.chartIncome,
            semanticLabel: rate == null ? 'نرخ وصول نامشخص' : '${pn(rate.round())} درصد مطالبات این بازه وصول شده',
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            runSpacing: 4,
            children: [
              _inlineValue('دریافتی این بازه', _money(d.totalReceived)),
              _inlineValue('مانده مطالبات (پایان بازه)', _money(d.receivableBalance)),
            ],
          ),
          const SizedBox(height: 6),
          _inlineValue('پیش‌دریافت مشتریان (پایان بازه)', _money(d.customerCredit)),
        ],
      ),
    );
  }

  Widget _inlineValue(String label, String value) {
    return Text.rich(TextSpan(
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      children: [
        TextSpan(text: '$label '),
        TextSpan(text: value, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
      ],
    ));
  }

  Widget _shareRow(String label, double? share) {
    final value = share == null ? 0.0 : share / 100;
    return Row(
      children: [
        SizedBox(width: 84, child: Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
        const SizedBox(width: 10),
        Expanded(child: ProgressMeter(value: value, height: 8, color: AppColors.chartIncome)),
        const SizedBox(width: 10),
        SizedBox(
          width: 40,
          child: Text(_pct(share),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
      ],
    );
  }

  Widget _kvCard(List<(String, String)> rows) {
    return SurfaceBox(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(
                    child: Text(rows[i].$1, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  Text(rows[i].$2, style: AppTextStyles.rowAmount),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _comparisonRow(FinancialPeriodComparison c) {
    final label = _kComparisonLabels[c.metricName] ?? c.metricName;
    final isCount = c.metricName == 'projectVolume';
    final isRatio = c.metricName == 'periodReceiptToRevenueRatio';
    String fmt(double v) =>
        isCount ? pn(v.round()) : (isRatio ? '${pn(v.toStringAsFixed(1))}٪' : formatMoney(v, withSuffix: false));
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTextStyles.rowTitle),
                  const SizedBox(height: 2),
                  Text('دوره قبل: ${c.previousValue == null ? '—' : fmt(c.previousValue!)}',
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(fmt(c.currentValue), style: AppTextStyles.rowAmount),
                // تغییر عمداً خنثی (نه سبز/قرمز): «بالا رفتن» برای مانده
                // مطالبات خبر خوب نیست و رنگ نباید قضاوت کند.
                DeltaLabel(percent: c.growthRate),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _alertRow(ManagementAlert a) {
    final color = a.severity == ManagementAlertSeverity.error
        ? AppColors.negative
        : (a.severity == ManagementAlertSeverity.warning ? AppColors.brassLight : AppColors.textSecondary);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(a.severity == ManagementAlertSeverity.error ? Icons.error_outline : Icons.warning_amber_rounded,
              color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.title, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text(a.message, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _diagnosticsCard(FinancialReportDiagnostics diag) {
    final rows = <(String, int)>[
      ('ناسازگاری درآمد محاسبه‌شده با دفتر', diag.revenueLedgerMismatchCount),
      ('مانده منفی مطالبات', diag.negativeARCount),
      ('مانده منفی پیش‌دریافت', diag.negativeAdvanceCount),
      ('مانده منفی اعتبار مشتری', diag.negativeCustomerCreditCount),
      ('خطای تطبیق نقدی', diag.cashReconciliationErrors),
    ].where((r) => r.$2 > 0).toList();
    return SurfaceBox(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Row(
                children: [
                  Expanded(child: Text(rows[i].$1, style: const TextStyle(fontSize: 13))),
                  Text(pn(rows[i].$2),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.negative)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// نمودار ستونی ماهانه با مقدار بالای هر ستون. محور زمان چپ‌به‌راست (قدیمی
/// سمت چپ) - همان قرارداد نمودار داشبورد. اگر ماه‌ها زیاد باشند، افقی
/// اسکرول می‌شود تا برچسب‌ها در هم نروند.
class _MonthlyBarsCard extends StatelessWidget {
  final String title;
  final List<TrendPoint> points;
  const _MonthlyBarsCard({required this.title, required this.points});

  @override
  Widget build(BuildContext context) {
    final values = [for (final p in points) p.value];
    final maxV = values.whereType<double>().fold<double>(0, math.max);
    const plotHeight = 110.0;

    Widget slot(TrendPoint p, double width) {
      final v = p.value;
      final h = (v == null || maxV <= 0) ? 0.0 : math.max(v / maxV * plotHeight, v > 0 ? 2.0 : 0.0);
      return SizedBox(
        width: width,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(v == null ? '—' : formatMoneyCompact(v),
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Container(
              width: 28,
              height: h,
              decoration: const BoxDecoration(
                color: AppColors.chartIncome,
                borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ),
          ],
        ),
      );
    }

    return SurfaceBox(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, constraints) {
            final slotWidth = math.max(60.0, constraints.maxWidth / points.length);
            final content = Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                children: [
                  Container(
                    height: plotHeight + 34,
                    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.lineStrong))),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      for (final p in points) slot(p, slotWidth),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    for (final p in points)
                      SizedBox(
                        width: slotWidth,
                        child: Text(p.label,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                      ),
                  ]),
                ],
              ),
            );
            return slotWidth * points.length > constraints.maxWidth + 0.5
                ? SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: content)
                : content;
          }),
        ],
      ),
    );
  }
}
