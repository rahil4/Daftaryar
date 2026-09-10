import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/counterparty.dart';
import '../../models/project.dart';
import '../../models/journal_entry.dart';
import '../../models/project_price_event.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/quick_add_sheet.dart';
import '../../services/pdf_export_service.dart';
import '../journal/journal_entry_detail_screen.dart';
import '../journal/quick_expense_screen.dart';
import 'project_form_screen.dart';
import 'project_finance_sheets.dart';
import 'project_economics_screen.dart';
import 'project_metrics_debug_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  final ProjectModel project;
  const ProjectDetailScreen({super.key, required this.project});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  final _db = DatabaseHelper.instance;
  final _pdf = PdfExportService();
  late ProjectModel _project;
  CounterpartyModel? _counterparty;
  List<JournalEntryModel> _entries = [];
  List<ProjectPriceEventModel> _priceEvents = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final project = await _db.getProject(_project.id!);
    final client = await _db.getCounterparty(_project.counterpartyId);
    final entries = await _db.getJournalEntries(projectId: _project.id);
    final summary = await _db.projectFinancialSummary(_project.id!);
    final priceEvents = await _db.getProjectPriceEvents(_project.id!);
    setState(() {
      _project = project ?? _project;
      _counterparty = client;
      _entries = entries;
      _summary = summary;
      _priceEvents = priceEvents;
      _loading = false;
    });
  }

  /// خروجی PDF صورتحساب مختص همین پروژه - برای ارسال به کارفرما، بدون
  /// افشای بقیه پروژه‌های او (برخلاف خروجی سطح طرف‌حساب که همه را با هم
  /// می‌آورد).
  Future<void> _exportStatement() async {
    setState(() => _exporting = true);
    try {
      final cashFlow = await _db.projectFinancials(_project.id!);
      final transactions = <Map<String, dynamic>>[];
      for (final e in _entries) {
        for (final l in e.lines) {
          if (l.projectId != _project.id) continue;
          if (l.debit == 0 && l.credit == 0) continue;
          transactions.add({
            'date': e.date,
            'description': e.description ?? _project.title,
            'type': l.credit > 0 ? 'دریافت' : 'پرداخت',
            'amount': l.credit > 0 ? l.credit : l.debit,
          });
        }
      }
      transactions.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      await _pdf.exportProjectStatement(
        projectTitle: _project.title,
        counterpartyName: _counterparty?.name ?? '—',
        counterpartyPhone: _counterparty?.phone,
        agreedAmount: _project.agreedAmount,
        received: cashFlow['received']!,
        transactions: transactions,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  /// لغو پروژه: یک Workflow مستقل و کوچک، نه یک انتخاب ساده در فرم عمومی
  /// ویرایش پروژه. اطلاعات مالی (اسناد، رویدادهای قیمت) دست‌نخورده می‌مانند؛
  /// فقط وضعیت عملیاتی پروژه تغییر می‌کند.
  Future<void> _cancelProject() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('لغو پروژه'),
        content: const Text(
            'وضعیت این پروژه به «لغوشده» تغییر می‌کند. اسناد مالی و تاریخچه قیمت حذف نمی‌شوند. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('لغو پروژه', style: TextStyle(color: AppColors.negative))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _db.cancelProject(_project.id!);
        final updated = await _db.getProject(_project.id!);
        if (updated != null && mounted) setState(() => _project = updated);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        }
      }
    }
  }

  Future<void> _deleteProject() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف پروژه'),
        content: const Text(
            'اگر این پروژه سند مالی یا تاریخچه تغییر مبلغ ثبت‌شده داشته باشد، برای حفظ سوابق قابل حذف نخواهد بود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: AppColors.negative))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _db.deleteProject(_project.id!);
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        }
      }
    }
  }

  void _showAddOptions() {
    showQuickAddSheet(context, presetProjectId: _project.id, onDone: _load);
  }

  Future<void> _addPriceEvent() async {
    final result = await showPriceEventSheet(context, _project);
    if (result == true) _load();
  }

  Future<void> _finalize() async {
    final result = await showFinalizeSheet(context, _project, _summary!['currentExpectedAmount']);
    if (result == true) _load();
  }

  Future<void> _addDiscount() async {
    final result = await showDiscountSheet(context, _project);
    if (result == true) _load();
  }

  Future<void> _addFinalAdjustment() async {
    final result = await showFinalAdjustmentSheet(context, _project);
    if (result == true) _load();
  }

  Future<void> _receivePayment() async {
    final result = await showReceivePaymentSheet(context, _project, _summary);
    if (result == true) _load();
  }

  Future<void> _addExpense() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => QuickExpenseScreen(presetProjectId: _project.id)),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_project.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics_outlined),
            tooltip: 'Debug: شاخص‌های مالی (Metrics Layer)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ProjectMetricsDebugScreen(projectId: _project.id!)),
            ),
          ),
          IconButton(
            icon: _exporting
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.ios_share_outlined),
            tooltip: 'خروجی صورتحساب',
            onPressed: _exporting ? null : _exportStatement,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final result = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ProjectFormScreen(existing: _project)));
              if (result == true) {
                final updated = await _db.getProject(_project.id!);
                if (updated != null) setState(() => _project = updated);
                _load();
              }
            },
          ),
          if (_project.status != kProjectStatusCancelled &&
              _project.status != kProjectStatusFinalized)
            IconButton(
              icon: const Icon(Icons.block_outlined),
              tooltip: 'لغو پروژه',
              onPressed: _cancelProject,
            ),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteProject),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'خلاصه و مالی'),
            Tab(text: 'تحلیل'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : BlueprintGridBackground(
              child: TabBarView(
                controller: _tab,
                children: [
                  _OverviewTab(
                    project: _project,
                    counterparty: _counterparty,
                    entries: _entries,
                    priceEvents: _priceEvents,
                    summary: _summary!,
                    onLoad: _load,
                    onAddOptions: _showAddOptions,
                    onReceivePayment: _receivePayment,
                    onAddExpense: _addExpense,
                    onAddPriceEvent: _addPriceEvent,
                    onFinalize: _finalize,
                    onAddDiscount: _addDiscount,
                    onAddFinalAdjustment: _addFinalAdjustment,
                  ),
                  ProjectEconomicsScreen(projectId: _project.id!, embedded: true),
                ],
              ),
            ),
    );
  }
}

/// تب «خلاصه و مالی» - ادغام دو تب قبلی «خلاصه» و «مالی» که همان چند عدد
/// پایه (برآورد اولیه، دریافتی، هزینه مستقیم، سود، مانده طلب) را با چیدمان
/// کمی متفاوت دوبار نشان می‌دادند. حالا هر عدد فقط یک‌بار دیده می‌شود:
/// اطلاعات کلی پروژه → وضعیت مالی یکپارچه → دکمه‌های عملیات → تاریخچه
/// تغییرات مبلغ → اسناد. تحلیل نسبت‌ها/مقایسه با میانگین در تب «تحلیل»
/// جداست.
class _OverviewTab extends StatelessWidget {
  final ProjectModel project;
  final CounterpartyModel? counterparty;
  final List<JournalEntryModel> entries;
  final List<ProjectPriceEventModel> priceEvents;
  final Map<String, dynamic> summary;
  final VoidCallback onLoad;
  final VoidCallback onAddOptions;
  final VoidCallback onReceivePayment;
  final VoidCallback onAddExpense;
  final VoidCallback onAddPriceEvent;
  final VoidCallback onFinalize;
  final VoidCallback onAddDiscount;
  final VoidCallback onAddFinalAdjustment;

  const _OverviewTab({
    required this.project,
    required this.counterparty,
    required this.entries,
    required this.priceEvents,
    required this.summary,
    required this.onLoad,
    required this.onAddOptions,
    required this.onReceivePayment,
    required this.onAddExpense,
    required this.onAddPriceEvent,
    required this.onFinalize,
    required this.onAddDiscount,
    required this.onAddFinalAdjustment,
  });

  @override
  Widget build(BuildContext context) {
    final initialEstimate = summary['initialEstimate'] as double;
    final currentExpected = summary['currentExpectedAmount'] as double?;
    final isFinalized = summary['isFinalized'] as bool;
    final isSettled = summary['isSettled'] as bool;
    final grossFinalAmount = summary['grossFinalAmount'] as double?;
    final discount = summary['discount'] as double? ?? 0;
    final netRevenue = summary['netRevenue'] as double?;
    final totalReceived = summary['totalReceived'] as double? ?? 0;
    final receivable = summary['receivable'] as double? ?? 0;
    final customerCredit = summary['customerCredit'] as double? ?? 0;
    final directProjectCost = summary['directProjectCost'] as double? ?? 0;
    final projectContribution = summary['projectContribution'] as double?;
    final projectMargin = summary['projectMargin'] as double?;
    final hasChanged = !isFinalized && currentExpected != null && currentExpected != initialEstimate;

    return RefreshIndicator(
      onRefresh: () async => onLoad(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(counterparty?.name ?? '—'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.category_outlined, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(project.projectTypes.join('، ')),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.event_outlined, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text('شروع: ${formatJalaliLong(project.startDate)}'),
                    ],
                  ),
                  if (project.description != null) ...[
                    const SizedBox(height: 8),
                    Text(project.description!, style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _statusChip(isFinalized ? 'نهایی‌شده' : 'در جریان',
                  isFinalized ? AppColors.brass : AppColors.textSecondary),
              const SizedBox(width: 8),
              _statusChip(
                  isSettled ? 'تسویه‌شده' : 'تسویه‌نشده', isSettled ? AppColors.positive : AppColors.negative),
            ],
          ),
          const SizedBox(height: 16),
          // کارت واحد «وضعیت مالی» - جایگزین دو کارت جدا («روند مبلغ» در
          // خلاصه قبلی + جدول اعداد در مالی قبلی) که همین اعداد را دوبار
          // نشان می‌دادند.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('وضعیت مالی', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 10),
                  _amountRow('برآورد اولیه (زمان ایجاد پروژه)', formatMoney(initialEstimate)),
                  if (!isFinalized) ...[
                    if (hasChanged) ...[
                      const SizedBox(height: 4),
                      _amountRow(
                        'مبلغ فعلی (پس از تغییرات)',
                        formatMoney(currentExpected),
                        badge: _deltaBadge(currentExpected - initialEstimate),
                        bold: true,
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('هنوز تغییری نسبت به برآورد اولیه ثبت نشده',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ),
                  ] else ...[
                    const SizedBox(height: 4),
                    _amountRow('مبلغ نهایی ناخالص', formatMoney(grossFinalAmount ?? 0)),
                    if (discount > 0) _amountRow('تخفیف', '- ${formatMoney(discount)}'),
                    const Divider(),
                    _amountRow('درآمد خالص (مبنای محاسبات پس از نهایی‌سازی)', formatMoney(netRevenue ?? 0),
                        bold: true),
                  ],
                  // دریافتی/هزینه مستقیم/مابه‌التفاوت - همان کارت «وضعیت
                  // مالی»، جدا از بخش قرارداد بالا با یک Divider؛ خطی و
                  // بدون کارت جداگانه، چون این سه رقم به همان وزن اعداد
                  // بالا نیاز ندارند.
                  const Divider(),
                  _cashLine(totalReceived, directProjectCost),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              if (receivable > 0)
                StatCard(
                  title: 'مانده طلب',
                  value: formatMoney(receivable),
                  icon: Icons.request_quote_outlined,
                  valueColor: AppColors.negative,
                ),
              if (customerCredit > 0)
                StatCard(
                  title: 'مازاد دریافتی (بستانکاری مشتری)',
                  value: formatMoney(customerCredit),
                  icon: Icons.account_balance_wallet_outlined,
                  valueColor: AppColors.positive,
                ),
              if (projectContribution != null)
                StatCard(
                  title: 'سود ناخالص پروژه',
                  value: formatMoney(projectContribution),
                  icon: Icons.trending_up_rounded,
                  valueColor: projectContribution >= 0 ? AppColors.positive : AppColors.negative,
                ),
              if (projectMargin != null)
                StatCard(
                  title: 'حاشیه سود',
                  value: '${projectMargin.toStringAsFixed(1)}٪',
                  icon: Icons.percent_rounded,
                ),
            ],
          ),
          const SizedBox(height: 20),
          // چهار دکمه عملیات همیشه در یک شبکه ۲×۲ هم‌عرض و هم‌سبک (خط
          // برنزی یکسان) - فقط رنگ آیکن جهت عملیات (دریافت/پرداخت) را نشان
          // می‌دهد؛ قبلاً «دریافت وجه» پرکنتراست‌تر از بقیه بود و باعث
          // می‌شد چیدمان یک‌دست به‌نظر نرسد.
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 2.6,
            children: [
              _ActionButton(
                icon: Icons.south_west_rounded,
                iconColor: AppColors.positive,
                label: 'دریافت وجه',
                onPressed: onReceivePayment,
              ),
              _ActionButton(
                icon: Icons.north_east_rounded,
                iconColor: AppColors.negative,
                label: 'ثبت هزینه',
                onPressed: onAddExpense,
              ),
              if (!isFinalized) ...[
                _ActionButton(
                  icon: Icons.edit_note_outlined,
                  iconColor: AppColors.brass,
                  label: 'تغییر مبلغ برآوردی',
                  onPressed: onAddPriceEvent,
                ),
                _ActionButton(
                  icon: Icons.flag_outlined,
                  iconColor: AppColors.brass,
                  label: 'نهایی‌سازی پروژه',
                  onPressed: onFinalize,
                ),
              ] else ...[
                _ActionButton(
                  icon: Icons.discount_outlined,
                  iconColor: AppColors.brass,
                  label: 'ثبت تخفیف',
                  onPressed: onAddDiscount,
                ),
                _ActionButton(
                  icon: Icons.tune_outlined,
                  iconColor: AppColors.brass,
                  label: 'اصلاح مبلغ نهایی',
                  onPressed: onAddFinalAdjustment,
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          Text('تاریخچه تغییرات مبلغ', style: Theme.of(context).textTheme.titleMedium),
          if (priceEvents.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('هنوز تغییری ثبت نشده', style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            ...priceEvents.map((e) => Card(
                  child: ListTile(
                    leading: Icon(
                      e.amount >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                      color: e.amount >= 0 ? AppColors.positive : AppColors.negative,
                    ),
                    title: Text('${_eventTypeLabel(e.type)} — ${formatMoney(e.amount.abs())}'),
                    subtitle:
                        Text('${formatJalaliLong(e.date)}${e.reason != null ? ' · ${e.reason}' : ''}'),
                  ),
                )),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('اسناد این پروژه (${pn(entries.length)})', style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: onAddOptions,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('ثبت جدید'),
              ),
            ],
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child:
                  Text('هنوز سندی برای این پروژه ثبت نشده', style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            ...entries.map((e) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long_outlined, color: AppColors.brass),
                    title: Text(e.description ?? 'سند شماره ${pn(e.id!)}'),
                    subtitle: Text('${formatJalaliLong(e.date)} · ${formatMoney(e.totalDebit)}'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => JournalEntryDetailScreen(entryId: e.id!)),
                      );
                      onLoad();
                    },
                  ),
                )),
        ],
      ),
    );
  }

  String _eventTypeLabel(String type) {
    switch (type) {
      case kPriceEventAddition:
        return 'افزایش مبلغ';
      case kPriceEventReduction:
        return 'کاهش مبلغ';
      case kPriceEventAdjustment:
        return 'اصلاح مبلغ';
      case kPriceEventFinalAdjustment:
        return 'اصلاح پس از نهایی‌سازی';
      case kPriceEventDiscount:
        return 'تخفیف';
      default:
        return type;
    }
  }

  Widget _statusChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  /// ردیف «دریافتی / هزینه مستقیم / مابه‌التفاوت» - داخل کارت «وضعیت
  /// مالی»، زیر بخش قرارداد. نام «مابه‌التفاوت دریافتی و هزینه» عمداً
  /// «سود» یا «مانده» نیست: نه معادل «سود ناخالص پروژه» است (که خودش جدا،
  /// تعهدی و از netRevenue محاسبه می‌شود)، نه معادل «مانده طلب» - فقط
  /// دریافتی نقدی منهای هزینه مستقیم است.
  Widget _cashLine(double totalReceived, double directProjectCost) {
    final diff = totalReceived - directProjectCost;
    Widget seg(String label, String value, Color color) {
      return Expanded(
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(value,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      );
    }

    Widget sep() => Container(width: 1, height: 30, margin: const EdgeInsets.symmetric(horizontal: 4), color: AppColors.gridLine);

    return Row(
      children: [
        seg('مجموع دریافتی', formatMoney(totalReceived), AppColors.positive),
        sep(),
        seg('هزینه مستقیم', formatMoney(directProjectCost), AppColors.negative),
        sep(),
        seg('مابه‌التفاوت دریافتی و هزینه', formatMoney(diff), AppColors.brass),
      ],
    );
  }

  Widget _amountRow(String label, String value, {Widget? badge, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ),
          if (badge != null) ...[badge, const SizedBox(width: 8)],
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  /// نشان کوچک اختلاف مبلغ فعلی نسبت به برآورد اولیه - سبز برای افزایش،
  /// قرمز برای کاهش (بدون قضاوت این‌که کدام برای دفتر بهتر است؛ فقط جهت
  /// تغییر مبلغ قرارداد را نشان می‌دهد)
  Widget _deltaBadge(double delta) {
    final positive = delta >= 0;
    final color = positive ? AppColors.positive : AppColors.negative;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: Text('${positive ? '+' : '-'} ${formatMoney(delta.abs())}',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

/// دکمه عملیات یکسان برای شبکه ۲×۲ تب «خلاصه و مالی» - همه دکمه‌ها یک
/// حاشیه برنزی و یک قالب دارند؛ فقط رنگ آیکن جهت عملیات (دریافت/پرداخت)
/// را متمایز می‌کند، نه کل ظاهر دکمه.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
      icon: Icon(icon, size: 18, color: iconColor),
      label: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5)),
    );
  }
}
