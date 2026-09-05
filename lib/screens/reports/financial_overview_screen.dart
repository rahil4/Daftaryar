import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/management_dashboard_data.dart';
import '../../models/operational_performance.dart';
import '../../services/management_dashboard_service.dart';
import '../../services/operational_performance_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/dashboard_period.dart';
import '../../utils/formatters.dart';
import '../../widgets/section_title.dart';
import '../dashboard/widgets/dashboard_sections.dart';
import '../dashboard/widgets/period_selector_widget.dart';
import '../dashboard/widgets/trend_chart_widget.dart';

/// یک ردیف حساب سرمایه (والد یا زیرحساب مثل «برداشت مالک») + مانده فعلی‌اش.
class _EquityAccountRow {
  final AccountModel account;
  final double balance;
  const _EquityAccountRow({required this.account, required this.balance});
}

/// صفحه یکپارچه «وضعیت مالی» - جایگزین سه تب پیشین گزارش‌ها (تحلیل و روند،
/// عملکرد عملیاتی، تحلیل مدیریتی) که هرکدام سرویس محاسباتی و انتخاب‌گر بازه
/// جدای خودشان را داشتند و مجموعاً یک صفحه شلوغ و کم‌کاربرد ساخته بودند.
///
/// این صفحه هیچ فرمول مالی جدیدی نمی‌سازد و هیچ‌کدام از دو سرویس موجود
/// (ManagementDashboardService/OperationalPerformanceService) را تغییر
/// نمی‌دهد - صرفاً همان دو منبع داده را با یک انتخاب‌گر بازه مشترک فراخوانی
/// و در یک چیدمان اولویت‌بندی‌شده نمایش می‌دهد: ابتدا KPIهای اصلی و
/// نقدینگی/مطالبات (آنچه روزمره لازم است)، سپس نمودار روند، و در آخر
/// جزئیات ریزتر (عملکرد پروژه/مشتری/قیمت‌گذاری/سلامت داده) پشت آکاردئون -
/// تا از دست نروند ولی پیش‌فرض شلوغ نکنند.
class FinancialOverviewScreen extends StatefulWidget {
  final bool embedded;
  const FinancialOverviewScreen({super.key, this.embedded = false});

  @override
  State<FinancialOverviewScreen> createState() => _FinancialOverviewScreenState();
}

class _FinancialOverviewScreenState extends State<FinancialOverviewScreen> {
  final _db = DatabaseHelper.instance;
  final _managementService = ManagementDashboardService();
  final _operationalService = OperationalPerformanceService();
  DashboardPeriodPreset _preset = DashboardPeriodPreset.thisMonth;
  ManagementDashboardData? _management;
  OperationalPerformanceData? _operational;
  List<_EquityAccountRow> _equityRows = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// حرکت حساب سرمایه و زیرحساب‌هایش (مثل «برداشت مالک») **در بازه انتخابی**
  /// - همان accountBalance موجود، فقط با fromDate/toDate همان بازه‌ای که
  /// PeriodSelectorWidget انتخاب کرده (دقیقاً مثل ReceivableCollectionSection
  /// که «وصول مطالبات دوره» را نشان می‌دهد، نه مانده کل‌عمر).
  Future<List<_EquityAccountRow>> _loadEquityRows(DashboardPeriodRange period) async {
    final accounts = await _db.getAccounts(type: kAccountEquity);
    final rows = <_EquityAccountRow>[];
    for (final acc in accounts) {
      final bal = await _db.accountBalance(acc.id!, fromDate: period.fromDate, toDate: period.toDate);
      rows.add(_EquityAccountRow(account: acc, balance: bal['balance']!));
    }
    return rows;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final period = await _operationalService.resolvePeriod(_preset);
      final management = await _managementService.buildDashboard(preset: _preset);
      final operational = await _operationalService.buildOperationalPerformance(period: period);
      final equityRows = await _loadEquityRows(period);
      setState(() {
        _management = management;
        _operational = operational;
        _equityRows = equityRows;
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
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text('خطا در بارگذاری: $_error', style: const TextStyle(color: AppColors.negative)),
            )
          else if (_management != null && _operational != null)
            ..._buildContent(_management!, _operational!),
        ],
      ),
    );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('وضعیت مالی')),
      body: BlueprintGridBackground(child: content),
    );
  }

  List<Widget> _buildContent(ManagementDashboardData m, OperationalPerformanceData o) {
    return [
      AlertsSection(data: m),
      if (o.warnings.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            children: o.warnings
                .map((w) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(w, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ))
                .toList(),
          ),
        ),

      // ---- خلاصه اصلی: همان چیزی که روزمره لازم است ----
      PeriodPerformanceSection(data: m),
      CashPositionSection(data: m),
      ReceivableCollectionSection(data: m),
      if (_equityRows.isNotEmpty) _EquitySection(rows: _equityRows),

      const SizedBox(height: 8),
      const SectionTitle('روند'),
      const SizedBox(height: 4),
      TrendChartWidget(title: 'روند درآمد', points: m.revenueTrend, color: AppColors.positive),
      const SizedBox(height: 10),
      TrendChartWidget(title: 'روند نتیجه عملیاتی', points: m.operatingResultTrend, color: AppColors.info),
      const SizedBox(height: 10),
      TrendChartWidget(title: 'روند جریان نقدی', points: m.cashFlowTrend, color: AppColors.brass),
      const SizedBox(height: 10),
      TrendChartWidget(title: 'روند حاشیه سود', points: m.contributionMarginTrend, color: AppColors.negative),

      const SizedBox(height: 20),
      _DetailAccordion(
        title: 'فعالیت و عملکرد پروژه‌ها',
        children: [
          _ActivityCountsGrid(o: o),
          const SizedBox(height: 12),
          _MarginDistributionGrid(o: o),
          const SizedBox(height: 12),
          _WipSummary(o: o),
          const SizedBox(height: 12),
          ProjectPerformanceSection(data: m),
        ],
      ),
      _DetailAccordion(
        title: 'تحلیل مشتریان',
        children: [
          Row(
            children: [
              Expanded(child: _MiniStat(label: 'سهم مشتری برتر', value: _pctText(o.top1CustomerRevenueShare))),
              const SizedBox(width: 8),
              Expanded(
                  child: _MiniStat(label: 'سهم ۳ مشتری برتر', value: _pctText(o.top3CustomerRevenueShare))),
            ],
          ),
          const SizedBox(height: 8),
          CustomerPerformanceSection(data: m),
        ],
      ),
      _DetailAccordion(
        title: 'قیمت‌گذاری و تخفیف',
        children: [PricingSection(data: m)],
      ),
      _DetailAccordion(
        title: 'وضعیت پروژه‌ها و سلامت داده',
        children: [
          SettlementSection(data: m),
          const SizedBox(height: 16),
          DiagnosticsSection(data: m),
        ],
      ),
      const SizedBox(height: 24),
    ];
  }
}

String _pctText(double? v) => v == null ? '—' : '${v.toStringAsFixed(1)}٪';

/// بخش سرمایه و زیرحساب‌هایش (مثل «برداشت مالک») - حرکت هر حساب **در بازه
/// انتخابی** (نه مانده کل‌عمر)، مستقیم از دفتر کل
/// (DatabaseHelper.accountBalance با fromDate/toDate همان بازه)، بدون هیچ
/// فرمول جدید. اگر کاربر زیرحسابی زیر «سرمایه» نساخته باشد، فقط همان یک
/// حساب پیش‌فرض نمایش داده می‌شود.
class _EquitySection extends StatelessWidget {
  final List<_EquityAccountRow> rows;
  const _EquitySection({required this.rows});

  Widget _row(String label, double value, {bool indented = false, bool bold = false}) {
    return Padding(
      padding: EdgeInsets.only(right: indented ? 16 : 0, top: 4, bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: indented ? 12.5 : 13,
                  color: indented ? AppColors.textSecondary : AppColors.textPrimary,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.normal)),
          Text(formatMoney(value, withSuffix: false),
              style: TextStyle(
                  fontSize: indented ? 12.5 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: value < 0 ? AppColors.negative : AppColors.textPrimary)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final parents = rows.where((r) => r.account.parentId == null).toList();
    final total = rows.fold<double>(0, (s, r) => s + r.balance);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('سرمایه (بازه انتخابی)'),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'حرکت هر حساب فقط در همین بازه - نه مانده کل‌عمر.',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              children: [
                for (final parent in parents) ...[
                  _row(parent.account.name, parent.balance),
                  for (final child in rows.where((r) => r.account.parentId == parent.account.id))
                    _row(child.account.name, child.balance, indented: true),
                ],
                const Divider(),
                _row('خالص تغییر سرمایه', total, bold: true),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// بخش قابل‌جمع‌شدن برای جزئیاتی که روزمره لازم نیستند ولی نباید گم شوند.
class _DetailAccordion extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _DetailAccordion({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          children: children,
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ],
        ),
      ),
    );
  }
}

/// شمار فعالیت پروژه‌ها در بازه انتخابی - از OperationalPerformanceData؛
/// معادلی در ManagementDashboardData ندارد (آنجا فقط شمار Finalized/
/// Settled/Unsettled وضعیت فعلی موجود است، نه فعالیت خودِ بازه).
class _ActivityCountsGrid extends StatelessWidget {
  final OperationalPerformanceData o;
  const _ActivityCountsGrid({required this.o});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1.6,
      children: [
        _MiniStat(label: 'کل پروژه‌ها', value: pn(o.projectCount)),
        _MiniStat(label: 'جدید در بازه', value: pn(o.newProjectCount)),
        _MiniStat(label: 'نهایی‌شده در بازه', value: pn(o.finalizedProjectCount)),
      ],
    );
  }
}

/// توزیع نتیجه پروژه‌های نهایی‌شده (زیان‌ده/حاشیه پایین/متعارف/بالا) - فقط
/// در OperationalPerformanceData موجود است.
class _MarginDistributionGrid extends StatelessWidget {
  final OperationalPerformanceData o;
  const _MarginDistributionGrid({required this.o});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('توزیع نتیجه پروژه‌های نهایی‌شده',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.9,
          children: [
            _MiniStat(label: 'زیان‌ده', value: pn(o.lossProjectCount)),
            _MiniStat(label: 'حاشیه پایین', value: pn(o.lowMarginProjectCount)),
            _MiniStat(label: 'حاشیه متعارف', value: pn(o.normalMarginProjectCount)),
            _MiniStat(label: 'حاشیه بالا', value: pn(o.highMarginProjectCount)),
          ],
        ),
        const SizedBox(height: 8),
        _MiniStat(label: 'نرخ زیان‌دهی', value: _pctText(o.lossProjectRate)),
      ],
    );
  }
}

/// خلاصه پروژه‌های در جریان (WIP) - برآورد اولیه، نه درآمد قطعی؛ فقط در
/// OperationalPerformanceData موجود است.
class _WipSummary extends StatelessWidget {
  final OperationalPerformanceData o;
  const _WipSummary({required this.o});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('پروژه‌های در جریان (WIP)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 1.9,
          children: [
            _MiniStat(label: 'تعداد', value: pn(o.wipProjectCount)),
            _MiniStat(label: 'برآورد اولیه', value: formatMoney(o.wipInitialEstimate, withSuffix: false)),
            _MiniStat(label: 'هزینه مستقیم ثبت‌شده', value: formatMoney(o.wipDirectCost, withSuffix: false)),
            _MiniStat(label: 'دریافتی (پیش‌دریافت)', value: formatMoney(o.wipReceived, withSuffix: false)),
          ],
        ),
      ],
    );
  }
}
