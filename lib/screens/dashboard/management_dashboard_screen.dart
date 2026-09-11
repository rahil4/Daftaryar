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
import '../journal/quick_expense_screen.dart';
import '../journal/journal_entry_detail_screen.dart';
import '../journal/journal_form_screen.dart';
import '../projects/project_form_screen.dart';
import '../projects/projects_screen.dart';
import '../reports/reports_screen.dart';
import '../settings/settings_screen.dart';
import '../sms_drafts/sms_drafts_screen.dart';
import 'widgets/dashboard_sections.dart';
import 'widgets/period_selector_widget.dart';
import 'widgets/multi_trend_chart_widget.dart';

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
      final data = await _service.buildDashboard(preset: _preset);
      setState(() {
        _data = data;
        _pendingSmsDrafts = pendingDrafts;
        _health = health;
        _daysSinceLastBackup = daysSinceBackup;
        _isNewUser = isNewUser;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
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
              // بنر سلامت داده در بالاترین نقطه: اگر یکپارچگی ساختاری
              // مشکل دارد، کاربر نباید پیش از دیدن این هشدار تراکنش جدید
              // ثبت کند یا به اعداد داشبورد تکیه کند.
              if (_health != null && !_health!.isHealthy) ...[
                _HealthBanner(result: _health!),
                const SizedBox(height: 12),
              ],
              // راهنمای شروع کار: پیش از هر چیز دیگر، چون بدون طرف‌حساب/
              // پروژه، بقیه داشبورد فقط اعداد صفر بی‌معنا نشان می‌دهد.
              if (_isNewUser) _OnboardingCard(onDone: _load),
              _QuickActionsRow(onDone: _load),
              if (_pendingSmsDrafts > 0) ...[
                const SizedBox(height: 10),
                _PendingSmsBanner(count: _pendingSmsDrafts, onTap: _load),
              ],
              if (_daysSinceLastBackup == null ||
                  _daysSinceLastBackup! >= kBackupReminderThresholdDays) ...[
                const SizedBox(height: 10),
                _BackupReminderBanner(daysSince: _daysSinceLastBackup, onTap: _load),
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

        // ---------- عملکرد این بازه ----------
        _label('عملکرد این بازه'),
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
                // چهار ردیف زیر دقیقاً با «پرداختی» بالای همین کارت جمع
                // می‌بندد (projectPayments + projectOverheadPayments +
                // officePayments + otherCashOutflows) - قبلاً فقط دو ردیف
                // اول بود و عدد این کارت با «پرداختی» همخوانی نداشت.
                _kv('پروژه‌ها', formatMoney(data.projectPayments, withSuffix: false)),
                _kv('سربار پروژه‌ها', formatMoney(data.projectOverheadPayments, withSuffix: false)),
                _kv('دفتر', formatMoney(data.officePayments, withSuffix: false)),
                if (data.otherCashOutflows != 0)
                  _kv('سایر', formatMoney(data.otherCashOutflows, withSuffix: false)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // ---------- نمودار مقایسه‌ای درآمد و هزینه ----------
        MultiTrendChartWidget(
          title: 'درآمد و هزینه',
          series: [
            ChartSeries(label: 'درآمد', points: data.revenueTrend, color: AppColors.brass),
            ChartSeries(label: 'هزینه', points: data.expenseTrend, color: AppColors.negative),
          ],
        ),
        const SizedBox(height: 16),

        // ---------- طلب و پیش‌دریافت ----------
        _label('طلب و پیش‌دریافت'),
        // مطالبات (بدهی رسمی، پروژه‌های نهایی‌شده) و مانده تخمینی (بدهی
        // غیررسمی، پروژه‌های در جریان) هر دو یک مفهوم‌اند - «چقدر پول
        // طلبکاریم» - فقط با درجه قطعیت متفاوت؛ در یک کارت با هم دیده
        // می‌شوند تا کارت جدا و ناوبری تکراری نداشته باشیم. هر دو به تب
        // «سود مشتریان» می‌روند - جایی که این دو عدد به تفکیک مشتری/پروژه
        // دیده می‌شود (جایگزین صفحه حذف‌شده «طلب‌های باز»).
        _ReceivablesCard(
          receivable: data.receivableBalance,
          estimatedRemaining: data.estimatedRemainingTotal,
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ReportsScreen(initialTabIndex: 1))),
        ),
        const SizedBox(height: 10),

        // ---------- پروژه در جریان + پیش‌دریافت ----------
        Row(
          children: [
            Expanded(
                child: _SimpleStat(
                    label: 'پروژه در جریان ›',
                    value: pn(data.openProjectsCount),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ProjectsScreen(onlyOpenFinancially: true))))),
            const SizedBox(width: 8),
            Expanded(
                child: _SimpleStat(
                    label: 'پیش‌دریافت ›',
                    value: formatMoneyCompact(data.advanceBalance),
                    bordered: true,
                    color: AppColors.brass,
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const ReportsScreen(
                                initialTabIndex: 1, sortCustomersByUrgency: true))))),
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

/// کارت واحد «مطالبات + مانده تخمینی» - جایگزین دو _SimpleStat جدا که هر
/// دو به یک مقصد می‌رفتند؛ چون هر دو یک مفهوم‌اند (پول طلبکاری، با درجه
/// قطعیت متفاوت)، یک کارت با دو ستون منطقی‌تر از دو کارت جدا با ناوبری
/// تکراری است.
class _ReceivablesCard extends StatelessWidget {
  final double receivable;
  final double estimatedRemaining;
  final VoidCallback onTap;
  const _ReceivablesCard(
      {required this.receivable, required this.estimatedRemaining, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget col(String label, double value) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Text(formatMoneyCompact(value),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.brass)),
            ),
          ],
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.brass, width: 0.8),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(11),
          child: Row(
            children: [
              col('مطالبات ›', receivable),
              Container(width: 1, height: 34, margin: const EdgeInsets.symmetric(horizontal: 10), color: AppColors.gridLine),
              col('مانده تخمینی ›', estimatedRemaining),
            ],
          ),
        ),
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
        const SizedBox(width: 10),
        Expanded(
          child: _QuickActionButton(
            label: 'سند',
            icon: Icons.receipt_long_outlined,
            color: AppColors.brass,
            onTap: () async {
              final result =
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const JournalFormScreen()));
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

/// بنر یادآور پشتیبان‌گیری - وقتی هرگز پشتیبان گرفته نشده یا مدتی طولانی
/// (kBackupReminderThresholdDays) از آخرین پشتیبان موفق گذشته باشد. طبق
/// همان درسِ STABILITY.md: «پشتیبانی که هرگز گرفته نشده، پشتیبان نیست».
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
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
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

class _BackupReminderBanner extends StatelessWidget {
  final int? daysSince; // null یعنی هرگز پشتیبان گرفته نشده
  final VoidCallback onTap;
  const _BackupReminderBanner({required this.daysSince, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final message = daysSince == null
        ? 'هنوز هیچ پشتیبانی تهیه نکرده‌اید'
        : '${pn(daysSince!)} روز از آخرین پشتیبان‌گیری گذشته';
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
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
            Expanded(
              child: Text(
                '$message — همین حالا یک نسخه تهیه کنید',
                style: const TextStyle(fontSize: 13, color: AppColors.brass, fontWeight: FontWeight.w700),
              ),
            ),
            const Text('‹', style: TextStyle(color: AppColors.brass, fontSize: 16)),
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
