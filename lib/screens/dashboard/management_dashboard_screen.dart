import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/management_dashboard_data.dart';
import '../../services/management_dashboard_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/dashboard_period.dart';
import '../../utils/formatters.dart';
import '../journal/quick_receipt_screen.dart';
import '../journal/quick_expense_screen.dart';
import '../journal/journal_entry_detail_screen.dart';
import '../reports/outstanding_receivables_screen.dart';
import '../settings/settings_screen.dart';
import '../sms_drafts/sms_drafts_screen.dart';
import 'widgets/dashboard_sections.dart';
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------- موجودی حساب‌ها (وضعیت فعلی، مستقل از بازه) ----------
        _label('موجودی حساب‌ها · الان'),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              children: [
                for (final b in data.bankBalances)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(b.name, style: const TextStyle(fontSize: 12.5)),
                        Text(formatMoney(b.balance, withSuffix: false),
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                if (data.bankBalances.isNotEmpty) const Divider(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('جمع کل',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brass)),
                    Text(formatMoney(data.closingCash, withSuffix: false),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.brass)),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),

        // ---------- انتخاب‌گر بازه ----------
        PeriodSelectorWidget(
          selected: _preset,
          onChanged: (p) {
            setState(() => _preset = p);
            _load();
          },
        ),
        const SizedBox(height: 12),

        // ---------- دریافتی / پرداختی این بازه ----------
        Row(
          children: [
            Expanded(
                child: _SimpleStat(
                    label: 'دریافتی',
                    value: formatMoneyCompact(data.customerReceipts + data.otherCashInflows),
                    color: AppColors.positive)),
            const SizedBox(width: 8),
            Expanded(
                child: _SimpleStat(
                    label: 'پرداختی',
                    value: formatMoneyCompact(data.projectPayments +
                        data.projectOverheadPayments +
                        data.officePayments +
                        data.otherCashOutflows),
                    color: AppColors.negative)),
          ],
        ),
        const SizedBox(height: 10),

        // ---------- هزینه‌های این بازه (تفکیک پروژه/دفتر) ----------
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('هزینه‌های این بازه',
                    style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                _kv('پروژه‌ها', formatMoney(data.projectPayments, withSuffix: false)),
                _kv('دفتر', formatMoney(data.officePayments, withSuffix: false)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---------- نمودار روند ----------
        TrendChartWidget(
            title: 'روند این بازه', points: data.revenueTrend, color: AppColors.brass),
        const SizedBox(height: 16),

        // ---------- مطالبات و مانده تخمینی (قابل‌کلیک) ----------
        Row(
          children: [
            Expanded(
                child: _SimpleStat(
                    label: 'مطالبات ›',
                    value: formatMoneyCompact(data.receivableBalance),
                    color: AppColors.brass,
                    bordered: true,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const OutstandingReceivablesScreen())))),
            const SizedBox(width: 8),
            Expanded(
                child: _SimpleStat(
                    label: 'مانده تخمینی ›',
                    value: formatMoneyCompact(data.estimatedRemainingTotal),
                    color: AppColors.brass,
                    bordered: true,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const OutstandingReceivablesScreen())))),
          ],
        ),
        const SizedBox(height: 10),

        // ---------- پروژه در جریان + پیش‌دریافت ----------
        Row(
          children: [
            Expanded(
                child: _SimpleStat(
                    label: 'پروژه در جریان',
                    value:
                        '${pn(data.openProjectsCount)} · ${formatMoneyCompact(data.openProjectsTotal)}')),
            const SizedBox(width: 8),
            Expanded(
                child: _SimpleStat(
                    label: 'پیش‌دریافت', value: formatMoneyCompact(data.advanceBalance))),
          ],
        ),
        const SizedBox(height: 18),

        // ---------- آخرین تراکنش‌ها ----------
        if (data.recentEntries.isNotEmpty) ...[
          _label('آخرین تراکنش‌ها'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: [
                  for (final e in data.recentEntries)
                    InkWell(
                      onTap: () async {
                        await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => JournalEntryDetailScreen(entryId: e.entryId)));
                        _load();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(e.description,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 12.5)),
                                  const SizedBox(height: 2),
                                  Text(formatJalaliLong(e.date),
                                      style: const TextStyle(
                                          fontSize: 10, color: AppColors.textSecondary)),
                                ],
                              ),
                            ),
                            Text(
                              '${e.isInflow ? '+' : '-'}${formatMoneyCompact(e.amount)}',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700,
                                  color: e.isInflow ? AppColors.positive : AppColors.negative),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],

        // ---------- هشدارها (فقط اگر وجود داشته باشند) ----------
        if (data.alerts.isNotEmpty) ...[
          const SizedBox(height: 8),
          AlertsSection(data: data),
        ],
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          Text(value, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

/// کارت آماری ساده و فشرده داشبورد - جایگزین KpiCard در چیدمان ساده‌شده،
/// بدون درصد رشد و بدون تأکید بصری اضافه.
class _SimpleStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  final bool bordered;
  final VoidCallback? onTap;
  const _SimpleStat(
      {required this.label, required this.value, this.color, this.bordered = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: const EdgeInsets.all(11),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Text(value,
                style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800, color: color ?? AppColors.textPrimary)),
          ),
        ],
      ),
    );

    return Card(
      shape: bordered
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: AppColors.brass, width: 0.8))
          : null,
      child: onTap == null
          ? body
          : InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: body),
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
