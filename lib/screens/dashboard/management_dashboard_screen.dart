import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../db/database_helper.dart';
import '../../models/management_dashboard_data.dart';
import '../../services/backup_service.dart';
import '../../services/data_health_service.dart';
import '../../services/management_dashboard_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/dashboard_period.dart';
import '../../utils/formatters.dart';
import '../../utils/reloadable.dart';
import '../counterparties/counterparty_form_screen.dart';
import '../journal/quick_receipt_screen.dart';
import '../journal/journal_entry_detail_screen.dart';
import '../projects/project_form_screen.dart';
import '../projects/projects_screen.dart';
import '../reports/receivables_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../sms_drafts/sms_drafts_screen.dart';
import '../../widgets/metric_strip.dart';
import '../../widgets/page_header.dart';
import '../../widgets/period_segmented_control.dart';
import 'widgets/combo_trend_chart_widget.dart';

/// اگر بیش از این تعداد روز از آخرین پشتیبان‌گیری موفق گذشته باشد (یا
/// اصلاً پشتیبانی گرفته نشده باشد)، بنر یادآور در داشبورد نمایش داده
/// می‌شود.
const int kBackupReminderThresholdDays = 14;

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

class _ManagementDashboardScreenState extends State<ManagementDashboardScreen>
    with Reloadable<ManagementDashboardScreen> {
  final _service = ManagementDashboardService();
  final _db = DatabaseHelper.instance;
  final _healthService = DataHealthService();
  DashboardPeriodPreset _preset = DashboardPeriodPreset.thisMonth;
  String _customFrom = defaultCustomPeriodRange().from;
  String _customTo = defaultCustomPeriodRange().to;
  // شماره آخرین بارگذاری: اگر کاربر پیش از تمام‌شدن یک بارگذاری، بازه را
  // عوض کند، نتیجه دیرتر-رسیده بارگذاری قدیمی نباید روی نتیجه جدید بنشیند.
  int _loadToken = 0;
  ManagementDashboardData? _data;
  bool _loading = true;
  String? _error;
  int _pendingSmsDrafts = 0;
  HealthCheckResult? _health;
  int? _daysSinceLastBackup; // null یعنی هرگز پشتیبان گرفته نشده
  bool _isNewUser = false; // بدون هیچ طرف‌حساب/پروژه‌ای - نمایش راهنمای شروع کار

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
    final pendingDrafts = await _db.countPendingSmsDrafts();
    // بررسی سلامت ساختاری - در try جدا، چون خودِ بررسی هرگز نباید باعث
    // شکست بارگذاری داشبورد شود.
    HealthCheckResult? health;
    try {
      health = await _healthService.run();
    } catch (_) {
      health = null;
    }
    final lastBackupDate = await _db.getSetting(kLastBackupDateSettingKey);
    final daysSinceBackup = _daysSince(lastBackupDate);
    // راهنمای شروع کار فقط تا وقتی هیچ طرف‌حساب/پروژه‌ای تعریف نشده معنا
    // دارد؛ به محض اولین مورد از هرکدام، خودش برای همیشه کنار می‌رود.
    final counterparties = await _db.getCounterparties();
    final projects = await _db.getProjects();
    final isNewUser = counterparties.isEmpty && projects.isEmpty;
    try {
      final data = await _service.buildDashboard(
          preset: _preset, customFrom: _customFrom, customTo: _customTo);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _data = data;
        _pendingSmsDrafts = pendingDrafts;
        _health = health;
        _daysSinceLastBackup = daysSinceBackup;
        _isNewUser = isNewUser;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
        // اعداد قبلی کنار پیام خطا نمی‌مانند: معلوم نیست هنوز معتبرند.
        _data = null;
        _pendingSmsDrafts = pendingDrafts;
        _health = health;
        _daysSinceLastBackup = daysSinceBackup;
        _isNewUser = isNewUser;
        _loading = false;
      });
    }
  }

  /// تعداد روز گذشته از تاریخ ثبت‌شده تا امروز؛ null اگر تاریخی ثبت نشده
  /// (هرگز پشتیبان گرفته نشده) یا قابل‌تجزیه نباشد - در آن حالت یادآور
  /// همیشه (به‌عنوان «هرگز») نمایش داده می‌شود.
  int? _daysSince(String? dateStr) {
    if (dateStr == null) return null;
    final date = parseJalaliString(dateStr);
    if (date == null) return null;
    return Jalali.now().julianDayNumber - date.julianDayNumber;
  }

  bool get _backupDue =>
      !_isNewUser &&
      (_daysSinceLastBackup == null || _daysSinceLastBackup! >= kBackupReminderThresholdDays);

  Future<void> _push(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: pageHeader(context, title: 'داشبورد'),
      body: BlueprintGridBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              // هنگام تازه‌سازی، داده قبلی روی صفحه می‌ماند و فقط یک نوار
              // باریک پیشرفت بالای آن می‌آید؛ چرخنده تمام‌صفحه فقط برای اولین
              // بارگذاری است که هنوز چیزی برای نمایش نیست.
              SizedBox(
                height: 2,
                child: (_loading && _data != null) ? const LinearProgressIndicator(minHeight: 2) : null,
              ),
              // بنر سلامت داده در بالاترین نقطه: اگر یکپارچگی ساختاری
              // مشکل دارد، کاربر نباید پیش از دیدن این هشدار تراکنش جدید
              // ثبت کند یا به اعداد داشبورد تکیه کند.
              if (_health != null && !_health!.isHealthy) ...[
                const SizedBox(height: 8),
                _HealthBanner(result: _health!),
              ],
              // راهنمای شروع کار: پیش از هر چیز دیگر، چون بدون طرف‌حساب/
              // پروژه، بقیه داشبورد فقط اعداد صفر بی‌معنا نشان می‌دهد.
              if (_isNewUser) ...[
                const SizedBox(height: 8),
                _OnboardingCard(onDone: _load),
              ],
              if (_data != null)
                _buildContent(_data!)
              else if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Text('خطا در بارگذاری داشبورد: $_error',
                      style: const TextStyle(color: AppColors.negative)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// تغییر یک شاخص نسبت به دوره قبل، به درصد؛ جهت از مقایسه مستقیم دو مقدار
  /// می‌آید (نه از علامت مقدار قبلی) تا بهبود یک عدد منفی هم «رو به بالا»
  /// دیده شود. null وقتی مقدار قبلی صفر یا نامعلوم است.
  double? _change(double? current, double? previous) {
    if (current == null || previous == null || previous == 0) return null;
    return (current - previous) / previous.abs() * 100;
  }

  Widget _buildContent(ManagementDashboardData data) {
    final expenseNow = (data.directProjectCost.value ?? 0) +
        (data.projectOverhead.value ?? 0) +
        (data.officeExpense.value ?? 0);
    final prevParts = [
      data.directProjectCost.previousValue,
      data.projectOverhead.previousValue,
      data.officeExpense.previousValue,
    ];
    final expensePrev =
        prevParts.any((v) => v == null) ? null : prevParts.fold<double>(0, (s, v) => s + v!);

    final followUps = _followUpRows(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------- موجودی (وضعیت فعلی، مستقل از بازه) ----------
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 14),
          child: HeroAmount(label: 'موجودی نقد و بانک · الان', amount: data.closingCash, fontSize: 36),
        ),
        if (data.bankBalances.isNotEmpty) ...[
          const Divider(height: 1),
          const SizedBox(height: 12),
          _AccountBalancesGrid(balances: data.bankBalances),
        ],
        const SizedBox(height: 18),

        // ---------- انتخاب‌گر بازه ----------
        PeriodSegmentedControl(
          selected: _preset,
          onChanged: (p) {
            setState(() => _preset = p);
            _load();
          },
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
        const SizedBox(height: 14),

        // ---------- عملکرد این بازه ----------
        SurfaceBox(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MetricStrip(
                framed: false,
                items: [
                  MetricItem(
                    label: 'درآمد',
                    value: _moneyOrDash(data.netRevenue.value),
                    footer: DeltaLabel(
                        percent: _change(data.netRevenue.value, data.netRevenue.previousValue)),
                  ),
                  MetricItem(
                    label: 'هزینه',
                    value: formatMoney(expenseNow, withSuffix: false),
                    footer: DeltaLabel(percent: _change(expenseNow, expensePrev)),
                  ),
                  MetricItem(
                    label: 'سود عملیاتی',
                    value: _moneyOrDash(data.operatingResult.value),
                    footer: DeltaLabel(
                        percent:
                            _change(data.operatingResult.value, data.operatingResult.previousValue)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text('درصدها: تغییر نسبت به دوره هم‌طول قبل',
                  style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // نمودار ترکیبی: درآمد/هزینه (تعهدی، ستون) + دریافتی (نقدی، خط).
        ComboTrendChartWidget(
          title: 'درآمد و هزینه',
          income: data.revenueTrend,
          expense: data.expenseTrend,
          receipts: data.receiptsTrend,
          caption: data.trendCaption,
          receiptsTotal: data.customerReceipts + data.otherCashInflows,
        ),
        const SizedBox(height: 10),
        _CashOutBreakdown(data: data),

        // ---------- نیاز به پیگیری ----------
        const BlockHeading('نیاز به پیگیری'),
        SurfaceBox(
          padding: EdgeInsets.zero,
          child: followUps.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('فعلاً موردی برای پیگیری نیست.',
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                )
              : Column(
                  children: [
                    for (var i = 0; i < followUps.length; i++) ...[
                      if (i > 0) const Divider(height: 1),
                      followUps[i],
                    ],
                  ],
                ),
        ),

        // ---------- آخرین تراکنش‌ها ----------
        if (data.recentEntries.isNotEmpty) ...[
          const BlockHeading('آخرین تراکنش‌ها'),
          for (var i = 0; i < data.recentEntries.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _RecentEntryRow(
              entry: data.recentEntries[i],
              onTap: () => _push(JournalEntryDetailScreen(entryId: data.recentEntries[i].entryId)),
            ),
          ],
        ],
      ],
    );
  }

  String _moneyOrDash(double? v) => v == null ? '—' : formatMoney(v, withSuffix: false);

  /// ردیف‌های «نیاز به پیگیری»: هر چیزی که کاربر باید درباره‌اش کاری بکند،
  /// در یک فهرست واحد (به‌جای بنرها و کارت‌های پراکنده قبلی).
  List<Widget> _followUpRows(ManagementDashboardData data) {
    final rows = <Widget>[];
    if (data.receivableBalance > 0) {
      rows.add(_FollowUpRow(
        icon: Icons.receipt_long_outlined,
        title: 'مطالبات باز',
        subtitle: '${pn(data.outstandingProjects.length)} پروژه نهایی‌شده',
        amount: data.receivableBalance,
        onTap: () => _push(const ReceivablesScreen()),
      ));
    }
    if (data.openProjectsCount > 0) {
      rows.add(_FollowUpRow(
        icon: Icons.work_outline,
        title: 'مانده تخمینی پروژه‌های در جریان',
        subtitle: '${pn(data.openProjectsCount)} پروژه',
        amount: data.estimatedRemainingTotal,
        onTap: () => _push(const ProjectsScreen(onlyOpenFinancially: true)),
      ));
    }
    if (data.advanceBalance > 0) {
      rows.add(_FollowUpRow(
        icon: Icons.savings_outlined,
        title: 'پیش‌دریافت مشتریان',
        subtitle: 'دریافت‌شده پیش از نهایی‌شدن پروژه',
        amount: data.advanceBalance,
        onTap: () => _push(const ReportsScreen(initialTabIndex: 1, sortCustomersByUrgency: true)),
      ));
    }
    if (_pendingSmsDrafts > 0) {
      rows.add(_FollowUpRow(
        icon: Icons.sms_outlined,
        title: 'پیش‌نویس پیامکی',
        subtitle: '${pn(_pendingSmsDrafts)} مورد در انتظار تأیید',
        onTap: () => _push(const SmsDraftsScreen()),
      ));
    }
    if (_backupDue) {
      rows.add(_FollowUpRow(
        icon: Icons.cloud_upload_outlined,
        title: 'پشتیبان‌گیری',
        subtitle: _daysSinceLastBackup == null
            ? 'هنوز هیچ پشتیبانی تهیه نکرده‌اید'
            : 'آخرین پشتیبان ${pn(_daysSinceLastBackup!)} روز پیش',
        onTap: () => _push(const SettingsScreen()),
      ));
    }
    for (final a in data.alerts) {
      // «مطالبات باز» همان ردیف اول این فهرست است؛ دوباره تکرار نمی‌شود.
      if (a.title == 'مطالبات باز') continue;
      final isError = a.severity == ManagementAlertSeverity.error;
      rows.add(_FollowUpRow(
        icon: isError ? Icons.error_outline : Icons.warning_amber_rounded,
        iconColor: isError
            ? AppColors.negative
            : (a.severity == ManagementAlertSeverity.warning ? AppColors.brass : AppColors.textSecondary),
        title: a.title,
        subtitle: a.message,
      ));
    }
    return rows;
  }
}

/// موجودی هر حساب نقدی/بانکی، سه‌تا در هر ردیف با خط جداکننده بین‌شان.
class _AccountBalancesGrid extends StatelessWidget {
  final List<BankBalanceEntry> balances;
  const _AccountBalancesGrid({required this.balances});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var start = 0; start < balances.length; start += 3) {
      final chunk = balances.skip(start).take(3).toList();
      if (start > 0) rows.add(const SizedBox(height: 12));
      rows.add(MetricStrip(
        framed: false,
        items: [
          for (final b in chunk)
            MetricItem(label: b.name, value: formatMoney(b.balance, withSuffix: false), valueSize: 13),
          // ردیف ناقص با خانه خالی پر می‌شود تا عرض ستون‌ها یکسان بماند.
          for (var i = chunk.length; i < 3; i++) const MetricItem(label: '', value: ''),
        ],
      ));
    }
    return Column(children: rows);
  }
}

/// تفکیک پرداخت‌های نقدی بازه (پروژه/سربار/دفتر/سایر) - پیش‌فرض بسته، چون
/// جزئیات ثانویه است.
class _CashOutBreakdown extends StatelessWidget {
  final ManagementDashboardData data;
  const _CashOutBreakdown({required this.data});

  @override
  Widget build(BuildContext context) {
    final total = data.projectPayments +
        data.projectOverheadPayments +
        data.officePayments +
        data.otherCashOutflows;
    Widget kv(String label, double value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              Text(formatMoney(value, withSuffix: false), style: AppTextStyles.rowAmount),
            ],
          ),
        );
    return SurfaceBox(
      padding: EdgeInsets.zero,
      // Material شفاف: تا موج لمس ردیف روی سطح کارت دیده شود.
      child: Material(
        type: MaterialType.transparency,
        child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          iconColor: AppColors.textSecondary,
          collapsedIconColor: AppColors.textSecondary,
          title: Row(
            children: [
              const Expanded(
                child: Text('پرداخت‌های نقدی این بازه', style: AppTextStyles.rowTitle),
              ),
              Text(formatMoney(total, withSuffix: false), style: AppTextStyles.rowAmount),
            ],
          ),
          children: [
            kv('پروژه‌ها', data.projectPayments),
            kv('سربار پروژه‌ها', data.projectOverheadPayments),
            kv('دفتر', data.officePayments),
            if (data.otherCashOutflows != 0) kv('سایر', data.otherCashOutflows),
          ],
        ),
        ),
      ),
    );
  }
}

class _FollowUpRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final double? amount;
  final VoidCallback? onTap;

  const _FollowUpRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.iconColor = AppColors.brassLight,
    this.amount,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title, style: AppTextStyles.rowTitle),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (amount != null) ...[
                const SizedBox(width: 8),
                Text(formatMoney(amount!, withSuffix: false), style: AppTextStyles.rowAmount),
              ],
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.chevron_left, size: 18, color: AppColors.textSecondary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentEntryRow extends StatelessWidget {
  final RecentEntryView entry;
  final VoidCallback onTap;
  const _RecentEntryRow({required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final inflow = entry.isInflow;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.gridLine),
                ),
                // جهت با شکل پیکان و علامت +/− هم گفته می‌شود، نه فقط با رنگ.
                child: Icon(
                  inflow ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                  size: 16,
                  color: inflow ? AppColors.positive : AppColors.negative,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(entry.description,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.rowTitle),
                    const SizedBox(height: 2),
                    Text(formatJalaliLong(entry.date),
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${inflow ? '+' : '−'} ${formatMoney(entry.amount, withSuffix: false)}',
                  style: AppTextStyles.rowAmount),
            ],
          ),
        ),
      ),
    );
  }
}

/// راهنمای شروع کار - فقط برای کاربر تازه (بدون هیچ طرف‌حساب/پروژه‌ای)
/// نمایش داده می‌شود؛ به محض افزودن اولین طرف‌حساب یا پروژه، خودش دیگر
/// هرگز دیده نمی‌شود (تصمیم بر مبنای همان دو شمارش در _load، بدون هیچ
/// Setting یا فیلد ماندگار جدید).
class _OnboardingCard extends StatelessWidget {
  final VoidCallback onDone;
  const _OnboardingCard({required this.onDone});

  Future<void> _go(BuildContext context, Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    onDone();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.brass, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.rocket_launch_outlined, color: AppColors.brass, size: 18),
                const SizedBox(width: 7),
                Text('شروع کار با دفتریار',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800, color: AppColors.brass)),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'برای اینکه اعداد داشبورد معنا پیدا کنند، این چند قدم را انجام دهید:',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            _OnboardingStep(
              number: 1,
              title: 'تعریف اولین طرف‌حساب',
              subtitle: 'مشتری یا کارفرمایی که با او کار می‌کنید',
              onTap: () => _go(context, const CounterpartyFormScreen()),
            ),
            _OnboardingStep(
              number: 2,
              title: 'تعریف اولین پروژه',
              subtitle: 'برای ردیابی جدا‌گانه درآمد و هزینه هر کار',
              onTap: () => _go(context, const ProjectFormScreen()),
            ),
            _OnboardingStep(
              number: 3,
              title: 'ثبت اولین دریافت یا موجودی افتتاحیه',
              subtitle: 'مثلاً موجودی فعلی صندوق یا حساب بانکی',
              onTap: () => _go(context, const QuickReceiptScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnboardingStep extends StatelessWidget {
  final int number;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _OnboardingStep(
      {required this.number, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.brass.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(pn(number),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.brass)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.chevron_left, color: AppColors.brass, size: 18),
          ],
        ),
      ),
    );
  }
}

/// بنر هشدار سلامت داده - فقط وقتی مشکلی وجود دارد نمایش داده می‌شود.
/// عمداً در بالاترین نقطه داشبورد قرار می‌گیرد (نه در تب گزارش‌ها) چون
/// مشکل یکپارچگی ساختاری یعنی همه اعداد صفحه غیرقابل‌اتکا هستند.
class _HealthBanner extends StatelessWidget {
  final HealthCheckResult result;
  const _HealthBanner({required this.result});

  @override
  Widget build(BuildContext context) {
    final color = result.hasCritical ? AppColors.negative : AppColors.brass;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(result.hasCritical ? Icons.error_outline : Icons.warning_amber_outlined,
                  color: color, size: 18),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  result.hasCritical ? 'مشکل در یکپارچگی داده‌ها' : 'هشدار سلامت داده',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: color),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...result.issues.take(3).map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ${i.title}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Padding(
                      padding: const EdgeInsets.only(right: 10, top: 1),
                      child: Text(i.detail,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ),
                  ],
                ),
              )),
          if (result.issues.length > 3)
            Text('و ${pn(result.issues.length - 3)} مورد دیگر',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          if (result.hasCritical) ...[
            const SizedBox(height: 6),
            const Text(
              'تا رفع این مشکل، اعداد این صفحه ممکن است نادرست باشند.',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.negative),
            ),
          ],
        ],
      ),
    );
  }
}
