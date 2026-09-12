import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
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
  Set<int> _cashAccountIds = {};
  int? _discountAccountId;
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
    final cashAccounts = await _db.getCashAccounts();
    final discountAccount = await _db.getServiceDiscountAccount();
    setState(() {
      _project = project ?? _project;
      _counterparty = client;
      _entries = entries;
      _summary = summary;
      _priceEvents = priceEvents;
      _cashAccountIds = cashAccounts.map((a) => a.id!).toSet();
      _discountAccountId = discountAccount?.id;
      _loading = false;
    });
  }

  /// خروجی PDF صورتحساب مختص همین پروژه - برای ارسال به کارفرما، بدون
  /// افشای بقیه پروژه‌های او (برخلاف خروجی سطح طرف‌حساب که همه را با هم
  /// می‌آورد). عمداً فقط دو نوع رویداد واقعی و قابل‌فهم فهرست می‌شود -
  /// دریافت‌های نقدی (بدهکار شدن یک حساب نقدی/بانکی) و هزینه‌های مستقیم
  /// پروژه (دقیقاً همان قاعده projectDirectCost: حساب نوع هزینه، به‌جز
  /// حساب تخفیف) - نه هر سطر دفترکل؛ سندهای سیستمی مثل شناسایی درآمد یا
  /// انتقال پیش‌دریافت داخلی‌اند و نباید در صورتحسابی که به کارفرما داده
  /// می‌شود دیده شوند.
  Future<void> _exportStatement() async {
    if (_summary == null) return;
    setState(() => _exporting = true);
    try {
      final cashAccounts = await _db.getCashAccounts();
      final cashAccountIds = cashAccounts.map((a) => a.id).toSet();
      final accounts = await _db.getAccounts();
      final accountsById = {for (final a in accounts) a.id!: a};
      final discountAccount = await _db.getServiceDiscountAccount();

      final receipts = <Map<String, dynamic>>[];
      final expenses = <Map<String, dynamic>>[];
      for (final e in _entries) {
        for (final l in e.lines) {
          if (l.projectId != _project.id) continue;
          if (cashAccountIds.contains(l.accountId)) {
            if (l.debit > 0) {
              receipts.add({
                'date': e.date,
                'description': e.description ?? 'دریافت وجه',
                'amount': l.debit,
              });
            } else if (l.credit > 0) {
              // برگشت/اصلاح یک دریافت اشتباه قبلی (رجوع به
              // DatabaseHelper.reverseProjectReceipt) - عمداً به‌جای حذف
              // بی‌صدا از صورتحساب، به‌صورت مبلغ منفی در همان فهرست
              // دریافت‌ها نشان داده می‌شود تا برای مشتری هم روشن باشد که
              // یک دریافت قبلی اصلاح/لغو شده، نه این‌که رقمی گم شده باشد.
              receipts.add({
                'date': e.date,
                'description': e.description ?? 'اصلاح دریافت',
                'amount': -l.credit,
              });
            }
          } else if (l.debit > 0 &&
              accountsById[l.accountId]?.type == kAccountExpense &&
              l.accountId != discountAccount?.id) {
            expenses.add({
              'date': e.date,
              'description': e.description ?? accountsById[l.accountId]?.name ?? 'هزینه پروژه',
              'amount': l.debit,
            });
          }
        }
      }
      receipts.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
      expenses.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      await _pdf.exportProjectStatement(
        projectTitle: _project.title,
        counterpartyName: _counterparty?.name ?? '—',
        counterpartyPhone: _counterparty?.phone,
        summary: _summary!,
        receipts: receipts,
        expenses: expenses,
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

  /// اصلاح یک سند «دریافت وجه» اشتباه (مثلاً چیزی که باید هزینه ثبت
  /// می‌شد). چون سند دریافت وجه سیستمی است و برای حفظ یکپارچگی حساب‌ها
  /// قابل حذف نیست، به‌جای حذف یک سند برگشتِ دقیقاً معکوس ثبت می‌شود (سند
  /// اصلی حذف نمی‌شود، فقط اثرش خنثی می‌گردد؛ رجوع به
  /// DatabaseHelper.reverseProjectReceipt). بلافاصله بعد، از کاربر می‌پرسد
  /// این تراکنش در واقع چه بود تا فرم ثبت صحیح باز شود.
  Future<void> _fixMistakenReceipt(JournalEntryModel entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اصلاح دریافت اشتباه'),
        content: const Text(
            'یک سند برگشت، دقیقاً معکوس این دریافت ثبت می‌شود (خودِ سند اصلی حذف نمی‌شود، فقط برای حفظ سوابق در تاریخچه می‌ماند و اثرش خنثی می‌شود). سپس می‌توانید تراکنش صحیح را ثبت کنید. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اصلاح شود')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.reverseProjectReceipt(entry.id!);
      await _load();
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('تراکنش صحیح چه بود؟'),
          content: const Text('این تراکنش در واقع باید چگونه ثبت می‌شد؟'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('فعلاً هیچ‌کدام')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'expense'), child: const Text('ثبت هزینه')),
            TextButton(onPressed: () => Navigator.pop(ctx, 'receipt'), child: const Text('دریافت وجه')),
          ],
        ),
      );
      if (choice == 'expense') {
        await _addExpense();
      } else if (choice == 'receipt') {
        await _receivePayment();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    }
  }

  /// ویرایش مستقیم مبلغ/حساب نقد/تاریخ/توضیح یک سند دریافت وجه - بدون
  /// ساختن سند دوم؛ رجوع به DatabaseHelper.updateProjectReceipt.
  Future<void> _editReceipt(JournalEntryModel entry) async {
    final result = await showEditReceiptSheet(context, entry);
    if (result == true) _load();
  }

  /// اصلاح یک سند «تخفیف» اشتباه - رجوع به DatabaseHelper.reverseProjectDiscount
  /// برای این‌که چرا اینجا فقط برگشت ممکن است، نه ویرایش مستقیم.
  Future<void> _fixMistakenDiscount(JournalEntryModel entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اصلاح تخفیف اشتباه'),
        content: const Text(
            'یک سند برگشت، دقیقاً معکوس این تخفیف ثبت می‌شود (خودِ سند اصلی حذف نمی‌شود، فقط برای حفظ سوابق در تاریخچه می‌ماند و اثرش خنثی می‌شود). سپس می‌توانید تخفیف صحیح را ثبت کنید. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اصلاح شود')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.reverseProjectDiscount(entry.id!);
      await _load();
      if (!mounted) return;
      await _addDiscount();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    }
  }

  /// اصلاح یک سند «اصلاح مبلغ نهایی» اشتباه - رجوع به
  /// DatabaseHelper.reverseFinalAdjustment.
  Future<void> _fixMistakenAdjustment(JournalEntryModel entry) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اصلاح این اصلاح مبلغ نهایی'),
        content: const Text(
            'یک سند برگشت، دقیقاً معکوس این اصلاح ثبت می‌شود (خودِ سند اصلی حذف نمی‌شود، فقط برای حفظ سوابق در تاریخچه می‌ماند و اثرش خنثی می‌شود). سپس می‌توانید اصلاح صحیح را ثبت کنید. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('اصلاح شود')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.reverseFinalAdjustment(entry.id!);
      await _load();
      if (!mounted) return;
      await _addFinalAdjustment();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    }
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
                    cashAccountIds: _cashAccountIds,
                    discountAccountId: _discountAccountId,
                    onFixReceipt: _fixMistakenReceipt,
                    onEditReceipt: _editReceipt,
                    onFixDiscount: _fixMistakenDiscount,
                    onFixAdjustment: _fixMistakenAdjustment,
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
  final Set<int> cashAccountIds;
  final int? discountAccountId;
  final ValueChanged<JournalEntryModel> onFixReceipt;
  final ValueChanged<JournalEntryModel> onEditReceipt;
  final ValueChanged<JournalEntryModel> onFixDiscount;
  final ValueChanged<JournalEntryModel> onFixAdjustment;

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
    required this.cashAccountIds,
    required this.discountAccountId,
    required this.onFixReceipt,
    required this.onEditReceipt,
    required this.onFixDiscount,
    required this.onFixAdjustment,
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
                  // دریافتی/هزینه مستقیم/مابه‌التفاوت (و پیش از نهایی‌سازی:
                  // مانده تخمینی) - همان کارت «وضعیت مالی»، جدا از بخش
                  // قرارداد بالا با یک Divider؛ هر رقم یک ردیف، هم‌سبک با
                  // ردیف‌های بالا.
                  const Divider(),
                  _amountRow('مجموع دریافتی', formatMoney(totalReceived), valueColor: AppColors.positive),
                  _amountRow('هزینه مستقیم', formatMoney(directProjectCost), valueColor: AppColors.negative),
                  _amountRow('مابه‌التفاوت دریافتی و هزینه', formatMoney(totalReceived - directProjectCost),
                      valueColor: AppColors.brass),
                  if (!isFinalized && currentExpected != null)
                    _amountRow('مانده تخمینی', formatMoney(currentExpected - totalReceived),
                        valueColor: AppColors.brass),
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
          // دکمه‌های عملیات - همان سبک اکشن‌های سریع داشبورد (Container
          // پرشده با حاشیه ملایم، رنگ آیکن و متن هر دو هم‌رنگ عملیات)،
          // فقط با سایز کمی جمع‌وجورتر چون برچسب‌های این‌جا بلندترند.
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: Icons.south_west_rounded,
                  color: AppColors.positive,
                  label: 'دریافت وجه',
                  onPressed: onReceivePayment,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionButton(
                  icon: Icons.north_east_rounded,
                  color: AppColors.negative,
                  label: 'ثبت هزینه',
                  onPressed: onAddExpense,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (!isFinalized) ...[
                Expanded(
                  child: _ActionButton(
                    icon: Icons.edit_note_outlined,
                    color: AppColors.brass,
                    label: 'تغییر مبلغ برآوردی',
                    onPressed: onAddPriceEvent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.flag_outlined,
                    color: AppColors.brass,
                    label: 'نهایی‌سازی پروژه',
                    onPressed: onFinalize,
                  ),
                ),
              ] else ...[
                Expanded(
                  child: _ActionButton(
                    icon: Icons.discount_outlined,
                    color: AppColors.brass,
                    label: 'ثبت تخفیف',
                    onPressed: onAddDiscount,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.tune_outlined,
                    color: AppColors.brass,
                    label: 'اصلاح مبلغ نهایی',
                    onPressed: onAddFinalAdjustment,
                  ),
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
            ...entries.map((e) {
              // آیا این سند قبلاً یک بار اصلاح شده؟ (یک سند دیگر در همین
              // پروژه با اشاره صریح به این سند در توضیحش) - مشترک بین هر
              // سه نوع قابل‌اصلاح، تا اصلاح دوباره ممکن نباشد.
              final alreadyReversed =
                  entries.any((other) => other.description?.contains('(سند اصلی #${e.id})') == true);

              // سند «دریافت وجه پروژه» سیستمی - ویرایش مستقیم
              // (updateProjectReceipt) فقط روی ساختار ساده دو-سطری مجاز
              // است؛ برگشت (reverseProjectReceipt) روی هر «دریافت وجه
              // پروژه»ای کار می‌کند (حتی سندهای چندسطریِ تقسیم‌شده بابت
              // مازاد دریافتی).
              final isReversibleReceipt = e.isSystemGenerated &&
                  !alreadyReversed &&
                  e.lines.any((l) => l.debit > 0 && cashAccountIds.contains(l.accountId));
              final isEditableReceipt = isReversibleReceipt && e.lines.length == 2;

              // سند «تخفیف» سیستمی - فقط برگشت (نه ویرایش مستقیم؛ رجوع به
              // توضیح DatabaseHelper.reverseProjectDiscount).
              final isReversibleDiscount = e.isSystemGenerated &&
                  !alreadyReversed &&
                  discountAccountId != null &&
                  e.lines.any((l) => l.accountId == discountAccountId && l.debit > 0);

              // سند «اصلاح مبلغ نهایی» سیستمی - تشخیص دوشرطی (توضیح +
              // نبود سطر نقد/بانک) تا با سند نهایی‌سازی (که حساب‌های
              // یکسانی لمس می‌کند) اشتباه گرفته نشود؛ رجوع به توضیح
              // DatabaseHelper.reverseFinalAdjustment.
              final isReversibleAdjustment = e.isSystemGenerated &&
                  !alreadyReversed &&
                  (e.description?.startsWith('اصلاح مبلغ نهایی') ?? false) &&
                  !e.lines.any((l) => cashAccountIds.contains(l.accountId));

              final hasAnyFix = isReversibleReceipt || isReversibleDiscount || isReversibleAdjustment;

              return Card(
                child: ListTile(
                  leading: const Icon(Icons.receipt_long_outlined, color: AppColors.brass),
                  title: Text(e.description ?? 'سند شماره ${pn(e.id!)}'),
                  subtitle: Text('${formatJalaliLong(e.date)} · ${formatMoney(e.totalDebit)}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (hasAnyFix)
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.build_outlined, color: AppColors.brass, size: 20),
                          tooltip: 'اصلاح این سند',
                          onSelected: (choice) {
                            if (choice == 'edit') {
                              onEditReceipt(e);
                            } else if (choice == 'reverse_receipt') {
                              onFixReceipt(e);
                            } else if (choice == 'reverse_discount') {
                              onFixDiscount(e);
                            } else if (choice == 'reverse_adjustment') {
                              onFixAdjustment(e);
                            }
                          },
                          itemBuilder: (ctx) => [
                            if (isEditableReceipt)
                              const PopupMenuItem(value: 'edit', child: Text('ویرایش دریافت')),
                            if (isReversibleReceipt)
                              const PopupMenuItem(value: 'reverse_receipt', child: Text('اصلاح دریافت اشتباه')),
                            if (isReversibleDiscount)
                              const PopupMenuItem(value: 'reverse_discount', child: Text('اصلاح تخفیف اشتباه')),
                            if (isReversibleAdjustment)
                              const PopupMenuItem(
                                  value: 'reverse_adjustment', child: Text('اصلاح این اصلاح مبلغ نهایی')),
                          ],
                        ),
                      const Icon(Icons.chevron_left),
                    ],
                  ),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => JournalEntryDetailScreen(entryId: e.id!)),
                    );
                    onLoad();
                  },
                ),
              );
            }),
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

  Widget _amountRow(String label, String value, {Widget? badge, bool bold = false, Color? valueColor}) {
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
                  color: valueColor ?? AppColors.textPrimary)),
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

/// دکمه عملیات تب «خلاصه و مالی» - عیناً همان سبک _QuickActionButton
/// داشبورد (Container پرشده با حاشیه ملایم، آیکن و متن هم‌رنگ با عملیات)،
/// فقط کمی جمع‌وجورتر چون برچسب‌های این‌جا («نهایی‌سازی پروژه»،
/// «تغییر مبلغ برآوردی») از دکمه‌های سه‌تایی داشبورد بلندترند.
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.gridLine),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
