import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/counterparty.dart';
import '../../models/project.dart';
import '../../models/journal_entry.dart';
import '../../models/project_price_event.dart';
import '../../services/project_workflow_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/metric_strip.dart';
import '../../widgets/page_header.dart' show BlockHeading;
import '../../widgets/progress_meter.dart';
import '../../widgets/project_receipt_context_box.dart';
import '../../widgets/stamp_chip.dart';
import '../../widgets/quick_add_sheet.dart';
import '../../services/pdf_export_service.dart';
import '../../services/project_statement_builder.dart';
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

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  final _db = DatabaseHelper.instance;
  final _workflow = ProjectWorkflowService(DatabaseHelper.instance);
  final _pdf = PdfExportService();
  late ProjectModel _project;
  CounterpartyModel? _counterparty;
  List<JournalEntryModel> _entries = [];
  List<ProjectPriceEventModel> _priceEvents = [];
  Map<String, dynamic>? _summary;
  Set<int> _cashAccountIds = {};
  Map<int, AccountModel> _accountsById = {};
  int? _discountAccountId;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _load();
  }

  Future<void> _load() async {
    // داده قبلی روی صفحه می‌ماند (فقط نوار باریک پیشرفت)؛ چرخنده تمام‌صفحه
    // فقط برای اولین بارگذاری است.
    setState(() => _loading = true);
    final project = await _db.getProject(_project.id!);
    final client = await _db.getCounterparty(_project.counterpartyId);
    final entries = await _db.getJournalEntries(projectId: _project.id);
    final summary = await _db.projectFinancialSummary(_project.id!);
    final priceEvents = await _db.getProjectPriceEvents(_project.id!);
    final cashAccounts = await _db.getCashAccounts();
    final discountAccount = await _db.getServiceDiscountAccount();
    final accounts = await _db.getAccounts();
    if (!mounted) return;
    setState(() {
      _accountsById = {for (final a in accounts) a.id!: a};
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

      final lists = buildProjectStatementLists(
        entries: _entries,
        projectId: _project.id!,
        cashAccountIds: cashAccountIds,
        accountsById: accountsById,
        discountAccountId: discountAccount?.id,
      );

      await _pdf.exportProjectStatement(
        projectTitle: _project.title,
        counterpartyName: _counterparty?.name ?? '—',
        counterpartyPhone: _counterparty?.phone,
        summary: _summary!,
        receipts: lists.receipts,
        expenses: lists.expenses,
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
      await _workflow.reverseProjectReceipt(entry.id!);
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

  /// تبدیل یک سند دریافتِ اشتباه (که در واقع هزینه بوده - اشتباه در
  /// ماهیت، نه فقط مبلغ) به یک سند هزینه واقعی، در همان سند - رجوع به
  /// DatabaseHelper.convertReceiptToExpense.
  Future<void> _convertToExpense(JournalEntryModel entry) async {
    final result = await showConvertReceiptToExpenseSheet(context, entry);
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
      await _workflow.reverseProjectDiscount(entry.id!);
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
      await _workflow.reverseFinalAdjustment(entry.id!);
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

  /// ویرایش مستقیم مبلغ/تاریخ/دلیل یک سند تخفیف - بدون ساختن سند دوم؛
  /// رجوع به DatabaseHelper.updateProjectDiscount.
  Future<void> _editDiscount(JournalEntryModel entry) async {
    final result = await showEditDiscountSheet(context, entry);
    if (result == true) _load();
  }

  /// ویرایش مستقیم مبلغ/تاریخ/دلیل یک سند اصلاح مبلغ نهایی - بدون ساختن
  /// سند دوم؛ رجوع به DatabaseHelper.updateFinalAdjustment.
  Future<void> _editAdjustment(JournalEntryModel entry) async {
    final result = await showEditFinalAdjustmentSheet(context, entry);
    if (result == true) _load();
  }

  Future<void> _editProject() async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => ProjectFormScreen(existing: _project)));
    if (result == true) {
      final updated = await _db.getProject(_project.id!);
      if (updated != null && mounted) setState(() => _project = updated);
      _load();
    }
  }

  void _openMoreActions() {
    final finalized = _project.isFinalized;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('اقدام‌های دیگر', style: AppTextStyles.blockHeading),
              ),
            ),
            if (!finalized) ...[
              _sheetAction(ctx, Icons.edit_note_outlined, 'تغییر مبلغ برآوردی', _addPriceEvent),
              _sheetAction(ctx, Icons.flag_outlined, 'نهایی‌سازی پروژه', _finalize),
            ] else ...[
              _sheetAction(ctx, Icons.discount_outlined, 'ثبت تخفیف', _addDiscount),
              _sheetAction(ctx, Icons.tune_outlined, 'اصلاح مبلغ نهایی', _addFinalAdjustment),
            ],
            _sheetAction(ctx, Icons.menu_book_outlined, 'سند حسابداری دستی', _showAddOptions),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _sheetAction(BuildContext sheetContext, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.brassLight),
      title: Text(label),
      minTileHeight: 56,
      onTap: () {
        Navigator.pop(sheetContext);
        onTap();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        actions: [
          if (_exporting)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                  child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
            ),
          PopupMenuButton<String>(
            tooltip: 'گزینه‌های بیشتر',
            icon: const Icon(Icons.more_vert),
            onSelected: (choice) {
              switch (choice) {
                case 'edit':
                  _editProject();
                case 'analysis':
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ProjectEconomicsScreen(projectId: _project.id!)));
                case 'export':
                  _exportStatement();
                case 'cancel':
                  _cancelProject();
                case 'delete':
                  _deleteProject();
                case 'debug':
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => ProjectMetricsDebugScreen(projectId: _project.id!)),
                  );
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'edit', child: Text('ویرایش پروژه')),
              const PopupMenuItem(value: 'analysis', child: Text('تحلیل پروژه')),
              PopupMenuItem(value: 'export', enabled: !_exporting, child: const Text('خروجی صورتحساب (PDF)')),
              if (_project.status != kProjectStatusCancelled && _project.status != kProjectStatusFinalized)
                const PopupMenuItem(value: 'cancel', child: Text('لغو پروژه')),
              const PopupMenuItem(
                  value: 'delete', child: Text('حذف پروژه', style: TextStyle(color: AppColors.negative))),
              // این گزینه فقط در build دیباگ دیده می‌شود - صفحه‌ی تشخیصی داخلی
              // برای توسعه‌دهنده است و نباید در نسخه‌ی نصبی کاربر نهایی
              // (release/APK منتشرشده) قابل دسترس باشد.
              if (kDebugMode)
                const PopupMenuItem(value: 'debug', child: Text('Debug: شاخص‌های مالی')),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: BlueprintGridBackground(
        child: summary == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  SizedBox(
                    height: 2,
                    child: _loading ? const LinearProgressIndicator(minHeight: 2) : null,
                  ),
                  Expanded(
                    child: _OverviewTab(
                      project: _project,
                      counterparty: _counterparty,
                      entries: _entries,
                      priceEvents: _priceEvents,
                      summary: summary,
                      onLoad: _load,
                      cashAccountIds: _cashAccountIds,
                      accountsById: _accountsById,
                      discountAccountId: _discountAccountId,
                      onFixReceipt: _fixMistakenReceipt,
                      onEditReceipt: _editReceipt,
                      onConvertToExpense: _convertToExpense,
                      onFixDiscount: _fixMistakenDiscount,
                      onEditDiscount: _editDiscount,
                      onFixAdjustment: _fixMistakenAdjustment,
                      onEditAdjustment: _editAdjustment,
                    ),
                  ),
                  _BottomActionBar(
                    onReceive: _receivePayment,
                    onExpense: _addExpense,
                    onMore: _openMoreActions,
                  ),
                ],
              ),
      ),
    );
  }
}

/// نوار اقدام چسبیده به پایین: دو کار پرتکرار پروژه (دریافت وجه، ثبت هزینه)
/// همیشه در دسترس‌اند و بقیه (تخفیف، نهایی‌سازی، ...) پشت دکمه «⋯».
class _BottomActionBar extends StatelessWidget {
  final VoidCallback onReceive;
  final VoidCallback onExpense;
  final VoidCallback onMore;
  const _BottomActionBar({required this.onReceive, required this.onExpense, required this.onMore});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.gridLine)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 20,
            child: SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: onReceive,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('دریافت وجه')),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 14,
            child: SizedBox(
              height: 52,
              child: OutlinedButton(
                onPressed: onExpense,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  side: const BorderSide(color: AppColors.brass, width: 1.5),
                  foregroundColor: AppColors.brassLight,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
                child: const FittedBox(fit: BoxFit.scaleDown, child: Text('ثبت هزینه')),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 52,
            height: 52,
            child: Tooltip(
              message: 'اقدام‌های دیگر',
              child: Material(
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: AppColors.gridLine),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onMore,
                  child: const Icon(Icons.more_horiz, color: AppColors.textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// یک ردیف «گردش پروژه» - یا یک سند دفترکل، یا یک تغییر مبلغ برآوردی.
class _FlowItem {
  final String date;
  final int kindOrder; // ثانویه برای ترتیب ردیف‌های هم‌تاریخ
  final int id;
  final JournalEntryModel? entry;
  final ProjectPriceEventModel? event;
  _FlowItem({required this.date, required this.kindOrder, required this.id, this.entry, this.event});
}

/// صفحه اصلی جزئیات پروژه (پیش‌تر تب «خلاصه و مالی») - ادغام اطلاعات کلی،
/// وضعیت مالی، مسیر مبلغ، سودآوری و یک خط زمانی واحد «گردش پروژه» که
/// اسناد دفترکل و تغییرات مبلغ برآوردی را با هم، به ترتیب تاریخ نشان
/// می‌دهد. هر عدد فقط یک‌بار دیده می‌شود؛ تحلیل نسبت‌ها در صفحه «تحلیل
/// پروژه» (از منوی ⋯) است.
class _OverviewTab extends StatelessWidget {
  final ProjectModel project;
  final CounterpartyModel? counterparty;
  final List<JournalEntryModel> entries;
  final List<ProjectPriceEventModel> priceEvents;
  final Map<String, dynamic> summary;
  final VoidCallback onLoad;
  final Set<int> cashAccountIds;
  final Map<int, AccountModel> accountsById;
  final int? discountAccountId;
  final ValueChanged<JournalEntryModel> onFixReceipt;
  final ValueChanged<JournalEntryModel> onEditReceipt;
  final ValueChanged<JournalEntryModel> onConvertToExpense;
  final ValueChanged<JournalEntryModel> onFixDiscount;
  final ValueChanged<JournalEntryModel> onEditDiscount;
  final ValueChanged<JournalEntryModel> onFixAdjustment;
  final ValueChanged<JournalEntryModel> onEditAdjustment;

  const _OverviewTab({
    required this.project,
    required this.counterparty,
    required this.entries,
    required this.priceEvents,
    required this.summary,
    required this.onLoad,
    required this.cashAccountIds,
    required this.accountsById,
    required this.discountAccountId,
    required this.onFixReceipt,
    required this.onEditReceipt,
    required this.onConvertToExpense,
    required this.onFixDiscount,
    required this.onEditDiscount,
    required this.onFixAdjustment,
    required this.onEditAdjustment,
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
    final customerCredit = summary['customerCredit'] as double? ?? 0;
    final directProjectCost = summary['directProjectCost'] as double? ?? 0;
    final projectContribution = summary['projectContribution'] as double?;
    final projectMargin = summary['projectMargin'] as double?;
    final hasChanged = !isFinalized && currentExpected != null && currentExpected != initialEstimate;

    final remainingInfo = computeProjectRemaining(project, summary);
    final remaining = remainingInfo.value;
    // مبنای «دریافتی از ...»: درآمد خالص پس از نهایی‌سازی، و پیش از آن مبلغ
    // فعلی برآوردی.
    final base = isFinalized ? netRevenue : currentExpected;
    final progress = (base == null || base <= 0) ? 0.0 : totalReceived / base;
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    final settled = isFinalized && isSettled;

    final subtitle = [
      counterparty?.name ?? '—',
      if (project.projectTypes.isNotEmpty) project.projectTypes.join('، '),
      'شروع ${formatJalaliLong(project.startDate)}',
    ].join(' · ');

    return RefreshIndicator(
      onRefresh: () async => onLoad(),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(project.title,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.35)),
                      const SizedBox(height: 4),
                      Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      if (project.description != null && project.description!.trim().isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(project.description!,
                            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: isFinalized ? const StampChip('نهایی‌شده') : StatusChip(project.status),
                ),
              ],
            ),
          ),
          // ---------- عدد اصلی: مانده ----------
          SurfaceBox(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HeroAmount(label: remainingInfo.label, amount: (remaining ?? 0).abs(), fontSize: 32),
                if (settled) ...[
                  const SizedBox(height: 6),
                  const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 16, color: AppColors.positive),
                      SizedBox(width: 4),
                      Text('تسویه‌شده',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.positive)),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                ProgressMeter(
                  value: progress,
                  height: 8,
                  color: settled ? AppColors.positive : AppColors.brass,
                  semanticLabel: '${pn(percent)} درصد دریافت شده',
                ),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 4,
                  children: [
                    Text.rich(TextSpan(
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      children: [
                        const TextSpan(text: 'دریافتی '),
                        TextSpan(
                            text: formatMoney(totalReceived, withSuffix: false),
                            style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
                      ],
                    )),
                    Text(
                      base == null ? '—' : 'از ${formatMoney(base, withSuffix: false)} · ${pn(percent)}٪',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                if (customerCredit > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'مازاد دریافتی (بستانکاری مشتری): ${formatMoney(customerCredit, withSuffix: false)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.brassLight),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---------- مسیر مبلغ ----------
          SurfaceBox(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Column(
              children: [
                _pathRow('برآورد اولیه', formatMoney(initialEstimate, withSuffix: false)),
                if (!isFinalized) ...[
                  if (hasChanged) ...[
                    const Divider(height: 1),
                    _pathRow('مبلغ فعلی (پس از تغییرات)', formatMoney(currentExpected, withSuffix: false),
                        badge: currentExpected - initialEstimate),
                  ] else ...[
                    const Divider(height: 1),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text('هنوز تغییری نسبت به برآورد اولیه ثبت نشده',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ),
                    ),
                  ],
                ] else ...[
                  const Divider(height: 1),
                  _pathRow('مبلغ نهایی‌شده', formatMoney(grossFinalAmount ?? 0, withSuffix: false)),
                  if (discount > 0) ...[
                    const Divider(height: 1),
                    _pathRow('تخفیف', '− ${formatMoney(discount, withSuffix: false)}'),
                  ],
                  const Divider(height: 1, color: AppColors.lineStrong),
                  _pathRow('درآمد خالص', formatMoney(netRevenue ?? 0, withSuffix: false), bold: true),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // ---------- سودآوری ----------
          MetricStrip(
            items: isFinalized && projectContribution != null
                ? [
                    MetricItem(
                        label: 'هزینه مستقیم',
                        value: formatMoney(directProjectCost, withSuffix: false),
                        valueSize: 14),
                    MetricItem(
                      label: 'سود ناخالص',
                      value: formatMoney(projectContribution, withSuffix: false),
                      valueSize: 14,
                      valueColor: projectContribution < 0 ? AppColors.negative : null,
                    ),
                    MetricItem(
                      label: 'حاشیه سود',
                      value: projectMargin == null ? '—' : '${pn(projectMargin.toStringAsFixed(1))}٪',
                      valueSize: 14,
                    ),
                  ]
                : [
                    MetricItem(
                        label: 'مجموع دریافتی',
                        value: formatMoney(totalReceived, withSuffix: false),
                        valueSize: 14),
                    MetricItem(
                        label: 'هزینه مستقیم',
                        value: formatMoney(directProjectCost, withSuffix: false),
                        valueSize: 14),
                    MetricItem(
                      label: 'دریافتی − هزینه',
                      value: formatMoney(totalReceived - directProjectCost, withSuffix: false),
                      valueSize: 14,
                    ),
                  ],
          ),
          if (isFinalized && projectContribution != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'دریافتی − هزینه مستقیم (نقدی): ${formatMoney(totalReceived - directProjectCost, withSuffix: false)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
              ),
            ),
          // ---------- گردش پروژه ----------
          const BlockHeading('گردش پروژه'),
          ..._buildTimeline(context),
        ],
      ),
    );
  }

  Widget _pathRow(String label, String value, {bool bold = false, double? badge}) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: bold ? 44 : 40),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: bold ? 14 : 13,
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
                    color: bold ? AppColors.textPrimary : AppColors.textSecondary)),
          ),
          if (badge != null) ...[
            Text('${badge >= 0 ? '+' : '−'} ${formatMoney(badge.abs(), withSuffix: false)}',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            const SizedBox(width: 8),
          ],
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 14 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ],
      ),
    );
  }

  List<Widget> _buildTimeline(BuildContext context) {
    // تخفیف و اصلاح مبلغ نهایی هم‌زمان سند دفترکل دارند (پس از طریق سند
    // خودشان در خط زمانی می‌آیند)؛ فقط تغییرات برآوردیِ پیش از نهایی‌سازی
    // رویداد مستقل می‌شوند، تا یک اتفاق دوبار ردیف نشود.
    const timelineEventTypes = {kPriceEventAddition, kPriceEventReduction, kPriceEventAdjustment};
    final items = <_FlowItem>[
      for (final e in entries) _FlowItem(date: e.date, kindOrder: 1, id: e.id ?? 0, entry: e),
      for (final ev in priceEvents)
        if (timelineEventTypes.contains(ev.type))
          _FlowItem(date: ev.date, kindOrder: 0, id: ev.id ?? 0, event: ev),
    ]..sort((a, b) {
        final byDate = b.date.compareTo(a.date);
        if (byDate != 0) return byDate;
        final byKind = b.kindOrder.compareTo(a.kindOrder);
        return byKind != 0 ? byKind : b.id.compareTo(a.id);
      });

    if (items.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('هنوز گردشی برای این پروژه ثبت نشده',
              style: TextStyle(color: AppColors.textSecondary)),
        ),
      ];
    }

    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) rows.add(const Divider(height: 1));
      final item = items[i];
      rows.add(item.entry != null ? _entryRow(context, item.entry!) : _eventRow(item.event!));
    }
    return rows;
  }

  Widget _eventRow(ProjectPriceEventModel e) {
    final up = e.amount >= 0;
    return _FlowRow(
      icon: up ? Icons.add : Icons.remove,
      iconColor: AppColors.textSecondary,
      title: _eventTypeLabel(e.type),
      subtitle: '${formatJalaliLong(e.date)}${e.reason != null ? ' · ${e.reason}' : ''}',
      amount: '${up ? '+' : '−'} ${formatMoney(e.amount.abs(), withSuffix: false)}',
    );
  }

  Widget _entryRow(BuildContext context, JournalEntryModel e) {
    // آیا این سند قبلاً یک بار اصلاح شده؟ (یک سند دیگر در همین پروژه با
    // اشاره صریح به این سند در توضیحش) - مشترک بین هر سه نوع قابل‌اصلاح، تا
    // اصلاح دوباره ممکن نباشد.
    final alreadyReversed = entries.any((other) => other.description?.contains('(سند اصلی #${e.id})') == true);

    // سند «دریافت وجه پروژه» سیستمی - ویرایش مستقیم (updateProjectReceipt)
    // فقط روی ساختار ساده دو-سطری مجاز است؛ برگشت (reverseProjectReceipt)
    // روی هر «دریافت وجه پروژه»ای کار می‌کند (حتی سندهای چندسطریِ
    // تقسیم‌شده بابت مازاد دریافتی).
    final isReversibleReceipt = e.isSystemGenerated &&
        !alreadyReversed &&
        e.lines.any((l) => l.debit > 0 && cashAccountIds.contains(l.accountId));
    final isEditableReceipt = isReversibleReceipt && e.lines.length == 2;

    // سند «تخفیف» سیستمی - هم ویرایش مستقیم (updateProjectDiscount) و هم
    // برگشت (reverseProjectDiscount) در دسترس‌اند.
    final isFixableDiscount = e.isSystemGenerated &&
        !alreadyReversed &&
        discountAccountId != null &&
        e.lines.any((l) => l.accountId == discountAccountId && l.debit > 0);

    // سند «اصلاح مبلغ نهایی» سیستمی - تشخیص دوشرطی (توضیح + نبود سطر
    // نقد/بانک) تا با سند نهایی‌سازی (که حساب‌های یکسانی لمس می‌کند) اشتباه
    // گرفته نشود؛ رجوع به توضیح DatabaseHelper.reverseFinalAdjustment.
    final isFixableAdjustment = e.isSystemGenerated &&
        !alreadyReversed &&
        (e.description?.startsWith('اصلاح مبلغ نهایی') ?? false) &&
        !e.lines.any((l) => cashAccountIds.contains(l.accountId));

    final hasAnyFix = isReversibleReceipt || isFixableDiscount || isFixableAdjustment;

    // نوع ردیف برای آیکن و علامت مبلغ: ورودی/خروجی وجه نقد، تخفیف، نهایی‌سازی
    // یا سند عمومی. جهت فقط به رنگ وابسته نیست: پیکان و علامت +/− هم دارد.
    final cashIn = e.lines.where((l) => cashAccountIds.contains(l.accountId)).fold<int>(0, (s, l) => s + l.debit);
    final cashOut = e.lines.where((l) => cashAccountIds.contains(l.accountId)).fold<int>(0, (s, l) => s + l.credit);
    final discountDebit = discountAccountId == null
        ? 0
        : e.lines.where((l) => l.accountId == discountAccountId).fold<int>(0, (s, l) => s + l.debit);
    final isFinalizeEntry = e.isSystemGenerated && (e.description?.startsWith('نهایی‌سازی پروژه') ?? false);

    IconData icon;
    Color iconColor = AppColors.textSecondary;
    String amount;
    String? accountName;
    if (cashIn > cashOut) {
      icon = Icons.arrow_downward_rounded;
      iconColor = AppColors.positive;
      amount = '+ ${formatMoney((cashIn - cashOut).toDouble(), withSuffix: false)}';
      accountName = _cashAccountName(e);
    } else if (cashOut > cashIn) {
      icon = Icons.arrow_upward_rounded;
      iconColor = AppColors.negative;
      amount = '− ${formatMoney((cashOut - cashIn).toDouble(), withSuffix: false)}';
      accountName = _cashAccountName(e);
    } else if (discountDebit > 0) {
      icon = Icons.discount_outlined;
      amount = '− ${formatMoney(discountDebit.toDouble(), withSuffix: false)}';
    } else if (isFinalizeEntry) {
      icon = Icons.flag_outlined;
      iconColor = AppColors.brassLight;
      amount = formatMoney(e.totalDebit.toDouble(), withSuffix: false);
    } else {
      icon = Icons.receipt_long_outlined;
      amount = formatMoney(e.totalDebit.toDouble(), withSuffix: false);
    }

    return _FlowRow(
      icon: icon,
      iconColor: iconColor,
      emphasised: isFinalizeEntry,
      title: e.description ?? 'سند شماره ${pn(e.id!)}',
      subtitle: accountName == null ? formatJalaliLong(e.date) : '${formatJalaliLong(e.date)} · $accountName',
      amount: amount,
      onTap: () async {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => JournalEntryDetailScreen(entryId: e.id!)),
        );
        onLoad();
      },
      menu: hasAnyFix
          ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textSecondary, size: 20),
              tooltip: 'اصلاح این سند',
              onSelected: (choice) {
                if (choice == 'edit_receipt') {
                  onEditReceipt(e);
                } else if (choice == 'reverse_receipt') {
                  onFixReceipt(e);
                } else if (choice == 'convert_to_expense') {
                  onConvertToExpense(e);
                } else if (choice == 'edit_discount') {
                  onEditDiscount(e);
                } else if (choice == 'reverse_discount') {
                  onFixDiscount(e);
                } else if (choice == 'edit_adjustment') {
                  onEditAdjustment(e);
                } else if (choice == 'reverse_adjustment') {
                  onFixAdjustment(e);
                }
              },
              itemBuilder: (ctx) => [
                if (isEditableReceipt) ...[
                  const PopupMenuItem(value: 'edit_receipt', child: Text('ویرایش دریافت')),
                  const PopupMenuItem(
                      value: 'convert_to_expense', child: Text('تبدیل به هزینه (اشتباهاً دریافت ثبت شد)')),
                ],
                if (isReversibleReceipt)
                  const PopupMenuItem(value: 'reverse_receipt', child: Text('اصلاح دریافت اشتباه')),
                if (isFixableDiscount) ...[
                  const PopupMenuItem(value: 'edit_discount', child: Text('ویرایش تخفیف')),
                  const PopupMenuItem(value: 'reverse_discount', child: Text('اصلاح تخفیف اشتباه')),
                ],
                if (isFixableAdjustment) ...[
                  const PopupMenuItem(value: 'edit_adjustment', child: Text('ویرایش اصلاح مبلغ نهایی')),
                  const PopupMenuItem(value: 'reverse_adjustment', child: Text('اصلاح این اصلاح مبلغ نهایی')),
                ],
              ],
            )
          : null,
    );
  }

  String? _cashAccountName(JournalEntryModel e) {
    for (final l in e.lines) {
      if (cashAccountIds.contains(l.accountId)) return accountsById[l.accountId]?.name;
    }
    return null;
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
}

class _FlowRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final bool emphasised;
  final String title;
  final String subtitle;
  final String amount;
  final VoidCallback? onTap;
  final Widget? menu;

  const _FlowRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.amount,
    this.emphasised = false,
    this.onTap,
    this.menu,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 60),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: emphasised ? AppColors.brass.withValues(alpha: 0.14) : AppColors.surface,
                border: Border.all(
                    color: emphasised ? AppColors.brass : AppColors.gridLine, width: emphasised ? 1.5 : 1),
              ),
              child: Icon(icon, size: 16, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: emphasised ? FontWeight.w700 : FontWeight.w600,
                          color: emphasised ? AppColors.brassLight : AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(amount, style: AppTextStyles.rowAmount),
            // جای دکمه منو همیشه رزرو است تا مبلغ‌ها زیر هم تراز بمانند.
            SizedBox(width: 44, child: menu == null ? null : Center(child: menu)),
          ],
        ),
      ),
    );
  }
}
