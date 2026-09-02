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
import 'widgets/kpi_card.dart';
import 'widgets/period_selector_widget.dart';
import 'widgets/trend_chart_widget.dart';
import '../operational/operational_performance_screen.dart';

/// تب یکپارچه «داشبورد مدیریتی» - ادغام اقدامات سریع/پیش‌نویس پیامکی با
/// داشبورد مدیریتی (ManagementDashboardService). این صفحه فقط مصرف‌کننده
/// ManagementDashboardService است و هیچ محاسبه مالی مستقلی انجام نمی‌دهد؛
/// همه فرمول‌ها (KPI، حرکت مطالبات، تطبیق نقدی، Diagnostics) از مدل/سرویس
/// موجود می‌آیند.
///
/// سلسله‌مراتب اطلاعاتی (به ترتیب اولویت مدیریتی):
/// وضعیت مالی فعلی (مستقل از بازه) → هشدارها (اگر باشند) → عملکرد دوره →
/// وصول مطالبات → جریان نقدی + روند → جزئیات ثانویه (پشت سوییچ کوچک).
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('داشبورد مدیریتی'),
            Text('وضعیت مالی و عملکرد دفتر',
                style: TextStyle(
                    fontSize: 11, color: AppColors.textSecondary.withValues(alpha: 0.9), fontWeight: FontWeight.w400)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'به‌روزرسانی',
            onPressed: _loading ? null : _load,
          ),
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
              if (_data != null) ...[
                const SizedBox(height: 10),
                _periodNotice(_data!.periodLabel),
              ],
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

  /// نوار فشردهٔ «بازه گزارش» - فقط periodLabel موجود را نمایش می‌دهد، هیچ
  /// تاریخی خودش نمی‌سازد.
  Widget _periodNotice(String label) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.gridLine),
      ),
      child: Row(
        children: [
          const Icon(Icons.event_note_outlined, size: 14, color: AppColors.brass),
          const SizedBox(width: 6),
          Text('بازه گزارش: $label',
              style: const TextStyle(fontSize: 12, color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildContent(ManagementDashboardData data) {
    // نکته حیاتی (مورد ۱۸): نبود فعالیت در بازه انتخابی به‌معنای نبود
    // وضعیت مالی برای کل دفتر نیست - وضعیت مالی فعلی (بخش A) همیشه نمایش
    // داده می‌شود، صرف‌نظر از این‌که بازه انتخابی فعالیتی داشته یا نه.
    final hasAnyActivity = data.allProjects.isNotEmpty ||
        data.netRevenue.value != 0 ||
        data.customerReceipts != 0 ||
        data.otherCashInflows != 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------- بخش A: وضعیت مالی فعلی (همیشه نمایان) ----------
        CurrentStateSection(data: data),

        // ---------- هشدارهای مدیریتی: بدون قایم‌شدن پشت سوییچ ----------
        if (data.alerts.isNotEmpty) ...[
          const SizedBox(height: 4),
          AlertsSection(data: data),
        ],

        if (!hasAnyActivity)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 36),
            child: Center(
              child: Text('در این بازه فعالیت مالی ثبت نشده است.',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
          )
        else ...[
          // ---------- بخش B: عملکرد دوره انتخاب‌شده ----------
          const SizedBox(height: 8),
          PeriodPerformanceSection(data: data),

          // ---------- بخش C: وصول مطالبات دوره ----------
          const SizedBox(height: 8),
          ReceivableCollectionSection(data: data),

          // ---------- بخش D + روند: دو ستونه در صفحه‌های عریض ----------
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final trend = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sectionHeading('روند عملکرد'),
                  TrendChartWidget(
                      title: 'روند نتیجه عملیاتی', points: data.operatingResultTrend, color: AppColors.info),
                ],
              );
              final cashFlow = CashPositionSection(data: data);
              if (constraints.maxWidth > 700) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: trend),
                    const SizedBox(width: 16),
                    Expanded(child: cashFlow),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [trend, const SizedBox(height: 20), cashFlow],
              );
            },
          ),

          // ---------- جزئیات ثانویه: پشت یک سوییچ کوچک، بدون تکرار KPIهای بالا ----------
          const SizedBox(height: 20),
          _DashboardDetailTabs(data: data),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _sectionHeading(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
    );
  }
}

enum _DetailGroup { profitability, performance, settlement }

/// جزئیات تحلیلی تکمیلی (نه اطلاعات اصلی مدیریتی که همه در بالا مستقیم
/// نمایش داده می‌شوند) - این سوییچ عمداً کوچک‌تر از قبل شده چون سودآوری،
/// نقدینگی، مطالبات و هشدارها دیگر پشت آن قایم نیستند؛ فقط نمودارهای روند
/// اضافه، قیمت‌گذاری، عملکرد تک‌تک پروژه/مشتری، و تشخیص کامل داده اینجا
/// باقی مانده‌اند - بدون تکرار KPIهایی که بالای صفحه از قبل دیده شده‌اند.
class _DashboardDetailTabs extends StatefulWidget {
  final ManagementDashboardData data;
  const _DashboardDetailTabs({required this.data});

  @override
  State<_DashboardDetailTabs> createState() => _DashboardDetailTabsState();
}

class _DashboardDetailTabsState extends State<_DashboardDetailTabs> {
  _DetailGroup _group = _DetailGroup.profitability;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _GroupSwitcher(selected: _group, onChanged: (g) => setState(() => _group = g)),
        const SizedBox(height: 16),
        switch (_group) {
          _DetailGroup.profitability => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 200,
                  child: KpiCard(title: 'حاشیه عملیاتی', kpi: data.operatingMargin, isPercentage: true),
                ),
                const SizedBox(height: 14),
                TrendChartWidget(
                    title: 'روند خالص تغییر نقدینگی', points: data.cashFlowTrend, color: AppColors.teal),
                const SizedBox(height: 10),
                TrendChartWidget(
                    title: 'روند حاشیه سود', points: data.contributionMarginTrend, color: AppColors.brass),
                PricingSection(data: data),
              ],
            ),
          _DetailGroup.performance => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProjectPerformanceSection(data: data),
                CustomerPerformanceSection(data: data),
              ],
            ),
          _DetailGroup.settlement => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettlementSection(data: data),
                DiagnosticsSection(data: data),
              ],
            ),
        },
      ],
    );
  }
}

/// سوییچ سه‌تایی به‌شکل Chip قابل‌کلیک، بدون وابستگی به TabController (طبق
/// همان الگوی امن AccountingScreen - بدون تودرتویی اسکرول)
class _GroupSwitcher extends StatelessWidget {
  final _DetailGroup selected;
  final ValueChanged<_DetailGroup> onChanged;
  const _GroupSwitcher({required this.selected, required this.onChanged});

  static const _labels = {
    _DetailGroup.profitability: 'سودآوری تفصیلی',
    _DetailGroup.performance: 'عملکرد پروژه/مشتری',
    _DetailGroup.settlement: 'تسویه و تشخیص',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _DetailGroup.values.map((g) {
          final active = g == selected;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(17),
              onTap: () => onChanged(g),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.brass : AppColors.surface,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: active ? AppColors.brass : AppColors.gridLine),
                ),
                child: Text(
                  _labels[g]!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: active ? const Color(0xFF15100A) : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// ردیف دو دکمه اقدام سریع (دریافت/پرداخت)
class _QuickActionsRow extends StatelessWidget {
  final VoidCallback onDone;
  const _QuickActionsRow({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _QuickActionButton(
            label: 'دریافت',
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
            label: 'پرداخت',
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

/// بنر پیش‌نویس‌های پیامکی در انتظار تأیید
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
