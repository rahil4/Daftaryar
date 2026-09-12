import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/journal_entry.dart';
import '../../models/project.dart';
import '../../models/project_price_event.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/persian_amount_field.dart';
import '../../widgets/project_receipt_context_box.dart';

/// شیت‌های عملیات مالی پروژه (تغییر مبلغ، نهایی‌سازی، تخفیف، اصلاح مبلغ
/// نهایی، دریافت وجه) - همگی از تب «خلاصه و مالی» در ProjectDetailScreen
/// صدا زده می‌شوند. هرکدام true برمی‌گرداند اگر با موفقیت ثبت شده باشد.

Future<bool?> showPriceEventSheet(BuildContext context, ProjectModel project) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => _PriceEventSheet(project: project),
  );
}

Future<bool?> showFinalizeSheet(BuildContext context, ProjectModel project, double suggestedAmount) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => _FinalizeSheet(project: project, suggestedAmount: suggestedAmount),
  );
}

Future<bool?> showDiscountSheet(BuildContext context, ProjectModel project) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => _DiscountSheet(project: project),
  );
}

Future<bool?> showFinalAdjustmentSheet(BuildContext context, ProjectModel project) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => _FinalAdjustmentSheet(project: project),
  );
}

/// ویرایش مستقیم یک سند «تخفیف» موجود - رجوع به
/// DatabaseHelper.updateProjectDiscount.
Future<bool?> showEditDiscountSheet(BuildContext context, JournalEntryModel entry) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => _EditDiscountSheet(entry: entry),
  );
}

/// ویرایش مستقیم یک سند «اصلاح مبلغ نهایی» موجود - رجوع به
/// DatabaseHelper.updateFinalAdjustment.
Future<bool?> showEditFinalAdjustmentSheet(BuildContext context, JournalEntryModel entry) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => _EditFinalAdjustmentSheet(entry: entry),
  );
}

Future<bool?> showReceivePaymentSheet(
    BuildContext context, ProjectModel project, Map<String, dynamic>? summary) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => _ReceivePaymentSheet(project: project, summary: summary),
  );
}

/// ویرایش مستقیم یک سند «دریافت وجه پروژه» موجود - رجوع به
/// DatabaseHelper.updateProjectReceipt برای شرایط دقیق مجاز بودن.
Future<bool?> showEditReceiptSheet(BuildContext context, JournalEntryModel entry) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    builder: (ctx) => _EditReceiptSheet(entry: entry),
  );
}

// ---------------- شیت‌های عملیات ----------------

class _PriceEventSheet extends StatefulWidget {
  final ProjectModel project;
  const _PriceEventSheet({required this.project});

  @override
  State<_PriceEventSheet> createState() => _PriceEventSheetState();
}

class _PriceEventSheetState extends State<_PriceEventSheet> {
  final _db = DatabaseHelper.instance;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String _type = kPriceEventAddition;
  String _date = todayJalaliString();
  bool _saving = false;

  Future<void> _save() async {
    final amount = parsePersianAmount(_amount.text) ?? 0;
    if (amount <= 0) return;
    setState(() => _saving = true);
    final signedAmount = _type == kPriceEventReduction ? -amount : amount;
    await _db.addProjectPriceEvent(
      projectId: widget.project.id!,
      type: _type,
      amount: signedAmount,
      reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      date: _date,
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('تغییر مبلغ برآوردی پروژه', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: kPriceEventAddition, label: Text('افزایش')),
              ButtonSegment(value: kPriceEventReduction, label: Text('کاهش')),
              ButtonSegment(value: kPriceEventAdjustment, label: Text('اصلاح')),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 16),
          PersianAmountField(controller: _amount, label: 'مبلغ (تومان) *'),
          const SizedBox(height: 12),
          JalaliDateField(label: 'تاریخ', value: _date, onChanged: (v) => setState(() => _date = v)),
          const SizedBox(height: 12),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'دلیل (اختیاری)')),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ثبت'),
          ),
        ],
      ),
    );
  }
}

class _FinalizeSheet extends StatefulWidget {
  final ProjectModel project;
  final double suggestedAmount;
  const _FinalizeSheet({required this.project, required this.suggestedAmount});

  @override
  State<_FinalizeSheet> createState() => _FinalizeSheetState();
}

class _FinalizeSheetState extends State<_FinalizeSheet> {
  final _db = DatabaseHelper.instance;
  late final _amount =
      TextEditingController(text: formatMoney(widget.suggestedAmount, withSuffix: false));
  final _note = TextEditingController();
  String _date = todayJalaliString();
  bool _saving = false;

  Future<void> _save() async {
    final amount = parsePersianAmount(_amount.text) ?? 0;
    if (amount <= 0) return;
    setState(() => _saving = true);
    try {
      await _db.finalizeProject(
        projectId: widget.project.id!,
        finalAmount: amount,
        date: _date,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('نهایی‌سازی پروژه', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          const Text(
            'با نهایی‌سازی، درآمد پروژه شناسایی می‌شود و پیش‌دریافت‌های موجود به حساب دریافتنی منتقل می‌شوند. این عملیات فقط یک‌بار قابل انجام است.',
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 16),
          PersianAmountField(controller: _amount, label: 'مبلغ نهایی (تومان) *'),
          const SizedBox(height: 12),
          JalaliDateField(label: 'تاریخ', value: _date, onChanged: (v) => setState(() => _date = v)),
          const SizedBox(height: 12),
          TextField(controller: _note, decoration: const InputDecoration(labelText: 'یادداشت (اختیاری)')),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('نهایی‌سازی'),
          ),
        ],
      ),
    );
  }
}

class _DiscountSheet extends StatefulWidget {
  final ProjectModel project;
  const _DiscountSheet({required this.project});

  @override
  State<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<_DiscountSheet> {
  final _db = DatabaseHelper.instance;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String _date = todayJalaliString();
  bool _saving = false;

  Future<void> _save() async {
    final amount = parsePersianAmount(_amount.text) ?? 0;
    if (amount <= 0) return;
    setState(() => _saving = true);
    try {
      await _db.recordProjectDiscount(
        projectId: widget.project.id!,
        amount: amount,
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        date: _date,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ثبت تخفیف نهایی', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          PersianAmountField(controller: _amount, label: 'مبلغ تخفیف (تومان) *'),
          const SizedBox(height: 12),
          JalaliDateField(label: 'تاریخ', value: _date, onChanged: (v) => setState(() => _date = v)),
          const SizedBox(height: 12),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'دلیل (اختیاری)')),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ثبت تخفیف'),
          ),
        ],
      ),
    );
  }
}

class _FinalAdjustmentSheet extends StatefulWidget {
  final ProjectModel project;
  const _FinalAdjustmentSheet({required this.project});

  @override
  State<_FinalAdjustmentSheet> createState() => _FinalAdjustmentSheetState();
}

class _FinalAdjustmentSheetState extends State<_FinalAdjustmentSheet> {
  final _db = DatabaseHelper.instance;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String _direction = 'increase';
  String _date = todayJalaliString();
  bool _saving = false;

  Future<void> _save() async {
    final amount = parsePersianAmount(_amount.text) ?? 0;
    if (amount <= 0) return;
    setState(() => _saving = true);
    try {
      await _db.recordFinalAdjustment(
        projectId: widget.project.id!,
        amount: _direction == 'increase' ? amount : -amount,
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        date: _date,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('اصلاح مبلغ نهایی پروژه', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'increase', label: Text('افزایش درآمد')),
              ButtonSegment(value: 'decrease', label: Text('کاهش درآمد')),
            ],
            selected: {_direction},
            onSelectionChanged: (s) => setState(() => _direction = s.first),
          ),
          const SizedBox(height: 16),
          PersianAmountField(controller: _amount, label: 'مبلغ اصلاح (تومان) *'),
          const SizedBox(height: 12),
          JalaliDateField(label: 'تاریخ', value: _date, onChanged: (v) => setState(() => _date = v)),
          const SizedBox(height: 12),
          TextField(controller: _reason, decoration: const InputDecoration(labelText: 'دلیل (اختیاری)')),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('ثبت اصلاح'),
          ),
        ],
      ),
    );
  }
}

/// شیت ویرایش مستقیم سند تخفیف - در قالب _DiscountSheet، فقط پیش‌پرشده
/// با مقادیر فعلی سند و صدازننده DatabaseHelper.updateProjectDiscount.
class _EditDiscountSheet extends StatefulWidget {
  final JournalEntryModel entry;
  const _EditDiscountSheet({required this.entry});

  @override
  State<_EditDiscountSheet> createState() => _EditDiscountSheetState();
}

class _EditDiscountSheetState extends State<_EditDiscountSheet> {
  final _db = DatabaseHelper.instance;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String _date = todayJalaliString();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final discountAccount = await _db.getServiceDiscountAccount();
    final discountLine = widget.entry.lines.firstWhere((l) => l.accountId == discountAccount?.id);
    const prefix = 'تخفیف: ';
    final desc = widget.entry.description ?? '';
    setState(() {
      _amount.text = formatMoney(discountLine.debit.toDouble(), withSuffix: false);
      _reason.text = desc.startsWith(prefix) ? desc.substring(prefix.length) : '';
      _date = widget.entry.date;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final amount = parsePersianAmount(_amount.text) ?? 0;
    if (amount <= 0) return;
    setState(() => _saving = true);
    try {
      await _db.updateProjectDiscount(
        entryId: widget.entry.id!,
        amount: amount,
        date: _date,
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ویرایش سند تخفیف', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                PersianAmountField(controller: _amount, label: 'مبلغ تخفیف (تومان) *'),
                const SizedBox(height: 12),
                JalaliDateField(label: 'تاریخ', value: _date, onChanged: (v) => setState(() => _date = v)),
                const SizedBox(height: 12),
                TextField(controller: _reason, decoration: const InputDecoration(labelText: 'دلیل (اختیاری)')),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('ذخیره اصلاحات'),
                ),
              ],
            ),
    );
  }
}

/// شیت ویرایش مستقیم سند اصلاح مبلغ نهایی - در قالب _FinalAdjustmentSheet،
/// فقط پیش‌پرشده با مقادیر فعلی سند و صدازننده DatabaseHelper.updateFinalAdjustment.
class _EditFinalAdjustmentSheet extends StatefulWidget {
  final JournalEntryModel entry;
  const _EditFinalAdjustmentSheet({required this.entry});

  @override
  State<_EditFinalAdjustmentSheet> createState() => _EditFinalAdjustmentSheetState();
}

class _EditFinalAdjustmentSheetState extends State<_EditFinalAdjustmentSheet> {
  final _db = DatabaseHelper.instance;
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  String _direction = 'increase';
  String _date = todayJalaliString();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final arAccount = await _db.getReceivableAccount();
    final arLine = widget.entry.lines.firstWhere((l) => l.accountId == arAccount?.id);
    final signedAmount = arLine.debit > 0 ? arLine.debit.toDouble() : -arLine.credit.toDouble();
    const prefix = 'اصلاح مبلغ نهایی: ';
    final desc = widget.entry.description ?? '';
    setState(() {
      _amount.text = formatMoney(signedAmount.abs(), withSuffix: false);
      _direction = signedAmount >= 0 ? 'increase' : 'decrease';
      _reason.text = desc.startsWith(prefix) ? desc.substring(prefix.length) : '';
      _date = widget.entry.date;
      _loading = false;
    });
  }

  Future<void> _save() async {
    final amount = parsePersianAmount(_amount.text) ?? 0;
    if (amount <= 0) return;
    setState(() => _saving = true);
    try {
      await _db.updateFinalAdjustment(
        entryId: widget.entry.id!,
        amount: _direction == 'increase' ? amount : -amount,
        date: _date,
        reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ویرایش سند اصلاح مبلغ نهایی', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'increase', label: Text('افزایش درآمد')),
                    ButtonSegment(value: 'decrease', label: Text('کاهش درآمد')),
                  ],
                  selected: {_direction},
                  onSelectionChanged: (s) => setState(() => _direction = s.first),
                ),
                const SizedBox(height: 16),
                PersianAmountField(controller: _amount, label: 'مبلغ اصلاح (تومان) *'),
                const SizedBox(height: 12),
                JalaliDateField(label: 'تاریخ', value: _date, onChanged: (v) => setState(() => _date = v)),
                const SizedBox(height: 12),
                TextField(controller: _reason, decoration: const InputDecoration(labelText: 'دلیل (اختیاری)')),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('ذخیره اصلاحات'),
                ),
              ],
            ),
    );
  }
}

class _ReceivePaymentSheet extends StatefulWidget {
  final ProjectModel project;
  final Map<String, dynamic>? summary;
  const _ReceivePaymentSheet({required this.project, this.summary});

  @override
  State<_ReceivePaymentSheet> createState() => _ReceivePaymentSheetState();
}

class _ReceivePaymentSheetState extends State<_ReceivePaymentSheet> {
  final _db = DatabaseHelper.instance;
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _date = todayJalaliString();
  List<AccountModel> _cashAccounts = [];
  int? _cashAccountId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await _db.getCashAccounts();
    setState(() {
      _cashAccounts = accounts;
      _cashAccountId = accounts.isNotEmpty ? accounts.first.id : null;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_cashAccountId == null) return;
    final amount = parsePersianAmount(_amount.text) ?? 0;
    if (amount <= 0) return;
    setState(() => _saving = true);
    try {
      await _db.receiveProjectPayment(
        projectId: widget.project.id!,
        cashAccountId: _cashAccountId!,
        amount: amount,
        date: _date,
        description: _description.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('دریافت وجه پروژه', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  widget.project.isFinalized
                      ? 'این پروژه نهایی شده؛ دریافت به‌عنوان تسویه طلب ثبت می‌شود.'
                      : 'این پروژه هنوز نهایی نشده؛ دریافت به‌عنوان پیش‌دریافت ثبت می‌شود (نه درآمد).',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                if (widget.summary != null) ...[
                  const SizedBox(height: 12),
                  ProjectReceiptContextBox(project: widget.project, summary: widget.summary!),
                ],
                const SizedBox(height: 16),
                PersianAmountField(controller: _amount, label: 'مبلغ (تومان) *'),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _cashAccountId,
                  decoration: const InputDecoration(labelText: 'واریز به حساب'),
                  items: _cashAccounts
                      .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _cashAccountId = v),
                ),
                const SizedBox(height: 12),
                JalaliDateField(label: 'تاریخ', value: _date, onChanged: (v) => setState(() => _date = v)),
                const SizedBox(height: 12),
                TextField(
                    controller: _description,
                    decoration: const InputDecoration(labelText: 'شرح (اختیاری)')),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('ثبت دریافت'),
                ),
              ],
            ),
    );
  }
}

/// شیت ویرایش مستقیم سند دریافت وجه (مبلغ/حساب/تاریخ/توضیح) - در قالب و
/// اجزای همان _ReceivePaymentSheet، فقط پیش‌پرشده با مقادیر فعلی سند و
/// صدازننده DatabaseHelper.updateProjectReceipt به‌جای receiveProjectPayment.
class _EditReceiptSheet extends StatefulWidget {
  final JournalEntryModel entry;
  const _EditReceiptSheet({required this.entry});

  @override
  State<_EditReceiptSheet> createState() => _EditReceiptSheetState();
}

class _EditReceiptSheetState extends State<_EditReceiptSheet> {
  final _db = DatabaseHelper.instance;
  late final JournalLineModel _cashLine = widget.entry.lines.firstWhere((l) => l.debit > 0);
  late final _amount =
      TextEditingController(text: formatMoney(_cashLine.debit.toDouble(), withSuffix: false));
  late final _description = TextEditingController(text: widget.entry.description ?? '');
  late String _date = widget.entry.date;
  List<AccountModel> _cashAccounts = [];
  int? _cashAccountId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _cashAccountId = _cashLine.accountId;
    _load();
  }

  Future<void> _load() async {
    final accounts = await _db.getCashAccounts();
    setState(() {
      _cashAccounts = accounts;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (_cashAccountId == null) return;
    final amount = parsePersianAmount(_amount.text) ?? 0;
    if (amount <= 0) return;
    setState(() => _saving = true);
    try {
      await _db.updateProjectReceipt(
        entryId: widget.entry.id!,
        cashAccountId: _cashAccountId!,
        amount: amount,
        date: _date,
        description: _description.text.trim().isNotEmpty ? _description.text.trim() : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: _loading
          ? const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ویرایش سند دریافت', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                const Text(
                  'مبلغ، حساب نقد/بانک، تاریخ یا توضیح این سند را مستقیماً اصلاح کنید - خودِ همین سند در جای خودش به‌روزرسانی می‌شود.',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                PersianAmountField(controller: _amount, label: 'مبلغ (تومان) *'),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _cashAccountId,
                  decoration: const InputDecoration(labelText: 'حساب نقد/بانک'),
                  items: _cashAccounts
                      .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _cashAccountId = v),
                ),
                const SizedBox(height: 12),
                JalaliDateField(label: 'تاریخ', value: _date, onChanged: (v) => setState(() => _date = v)),
                const SizedBox(height: 12),
                TextField(
                    controller: _description,
                    decoration: const InputDecoration(labelText: 'شرح (اختیاری)')),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('ذخیره اصلاحات'),
                ),
              ],
            ),
    );
  }
}
