import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/project.dart';
import '../../models/project_price_event.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/persian_amount_field.dart';
import '../../widgets/stat_card.dart';

/// مدیریت کامل جریان مالی پروژه: تاریخچه تغییر مبلغ، نهایی‌سازی، دریافت وجه
/// (پیش‌دریافت پیش از Finalization / تسویه طلب پس از آن)، تخفیف نهایی، و
/// اصلاح مبلغ نهایی. همه اعداد مستقیم از Ledger محاسبه می‌شوند.
class ProjectFinanceScreen extends StatefulWidget {
  final ProjectModel project;
  const ProjectFinanceScreen({super.key, required this.project});

  @override
  State<ProjectFinanceScreen> createState() => _ProjectFinanceScreenState();
}

class _ProjectFinanceScreenState extends State<ProjectFinanceScreen> {
  final _db = DatabaseHelper.instance;
  late ProjectModel _project;
  Map<String, dynamic>? _summary;
  List<ProjectPriceEventModel> _events = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final project = await _db.getProject(_project.id!);
    final summary = await _db.projectFinancialSummary(_project.id!);
    final events = await _db.getProjectPriceEvents(_project.id!);
    setState(() {
      _project = project ?? _project;
      _summary = summary;
      _events = events;
      _loading = false;
    });
  }

  Future<void> _addPriceEvent() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _PriceEventSheet(project: _project),
    );
    if (result == true) _load();
  }

  Future<void> _finalize() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _FinalizeSheet(project: _project, suggestedAmount: _summary!['currentExpectedAmount']),
    );
    if (result == true) _load();
  }

  Future<void> _addDiscount() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _DiscountSheet(project: _project),
    );
    if (result == true) _load();
  }

  Future<void> _addFinalAdjustment() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _FinalAdjustmentSheet(project: _project),
    );
    if (result == true) _load();
  }

  Future<void> _receivePayment() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (ctx) => _ReceivePaymentSheet(project: _project),
    );
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final s = _summary;
    return Scaffold(
      appBar: AppBar(title: const Text('وضعیت مالی پروژه')),
      body: _loading || s == null
          ? const Center(child: CircularProgressIndicator())
          : BlueprintGridBackground(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        _statusChip(_project.isFinalized ? 'نهایی‌شده' : 'در جریان',
                            _project.isFinalized ? AppColors.brass : AppColors.textSecondary),
                        const SizedBox(width: 8),
                        _statusChip(
                            (s['isSettled'] as bool) ? 'تسویه‌شده' : 'تسویه‌نشده',
                            (s['isSettled'] as bool) ? AppColors.positive : AppColors.negative),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _row('برآورد اولیه', formatMoney(s['initialEstimate'])),
                            if (!_project.isFinalized)
                              _row('مبلغ مورد انتظار فعلی', formatMoney(s['currentExpectedAmount'])),
                            if (_project.isFinalized) ...[
                              _row('مبلغ نهایی ناخالص', formatMoney(s['grossFinalAmount'])),
                              if ((s['discount'] as double) > 0)
                                _row('تخفیف', '- ${formatMoney(s['discount'])}'),
                              _row('درآمد خالص', formatMoney(s['netRevenue']), bold: true),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.6,
                      children: [
                        StatCard(
                          title: 'مجموع دریافتی',
                          value: formatMoney(s['totalReceived']),
                          icon: Icons.south_west_rounded,
                          color: AppColors.positive,
                        ),
                        if ((s['customerAdvance'] as double) > 0)
                          StatCard(
                            title: 'پیش‌دریافت (تسویه‌نشده)',
                            value: formatMoney(s['customerAdvance']),
                            icon: Icons.savings_outlined,
                            color: AppColors.brass,
                          ),
                        if ((s['receivable'] as double) > 0)
                          StatCard(
                            title: 'مانده طلب',
                            value: formatMoney(s['receivable']),
                            icon: Icons.request_quote_outlined,
                            color: AppColors.negative,
                          ),
                        if ((s['customerCredit'] as double) > 0)
                          StatCard(
                            title: 'مازاد دریافتی (بستانکاری مشتری)',
                            value: formatMoney(s['customerCredit']),
                            icon: Icons.account_balance_wallet_outlined,
                            color: AppColors.positive,
                          ),
                        StatCard(
                          title: 'هزینه مستقیم پروژه',
                          value: formatMoney(s['directProjectCost']),
                          icon: Icons.north_east_rounded,
                          color: AppColors.negative,
                        ),
                        if (s['projectContribution'] != null)
                          StatCard(
                            title: 'سود ناخالص پروژه',
                            value: formatMoney(s['projectContribution']),
                            icon: Icons.trending_up_rounded,
                            color: (s['projectContribution'] as double) >= 0
                                ? AppColors.positive
                                : AppColors.negative,
                          ),
                        if (s['projectMargin'] != null)
                          StatCard(
                            title: 'حاشیه سود',
                            value: '${(s['projectMargin'] as double).toStringAsFixed(1)}٪',
                            icon: Icons.percent_rounded,
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _receivePayment,
                          icon: const Icon(Icons.south_west_rounded, size: 18),
                          label: const Text('دریافت وجه'),
                        ),
                        if (!_project.isFinalized) ...[
                          OutlinedButton.icon(
                            onPressed: _addPriceEvent,
                            icon: const Icon(Icons.edit_note_outlined, size: 18),
                            label: const Text('تغییر مبلغ برآوردی'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _finalize,
                            icon: const Icon(Icons.flag_outlined, size: 18),
                            label: const Text('نهایی‌سازی پروژه'),
                          ),
                        ] else ...[
                          OutlinedButton.icon(
                            onPressed: _addDiscount,
                            icon: const Icon(Icons.discount_outlined, size: 18),
                            label: const Text('ثبت تخفیف'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _addFinalAdjustment,
                            icon: const Icon(Icons.tune_outlined, size: 18),
                            label: const Text('اصلاح مبلغ نهایی'),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('تاریخچه تغییرات مبلغ', style: Theme.of(context).textTheme.titleMedium),
                    if (_events.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('هنوز تغییری ثبت نشده',
                            style: TextStyle(color: AppColors.textSecondary)),
                      )
                    else
                      ..._events.map((e) => Card(
                            child: ListTile(
                              leading: Icon(
                                e.amount >= 0 ? Icons.add_circle_outline : Icons.remove_circle_outline,
                                color: e.amount >= 0 ? AppColors.positive : AppColors.negative,
                              ),
                              title: Text('${_eventTypeLabel(e.type)} — ${formatMoney(e.amount.abs())}'),
                              subtitle: Text(
                                  '${formatJalaliLong(e.date)}${e.reason != null ? ' · ${e.reason}' : ''}'),
                            ),
                          )),
                  ],
                ),
              ),
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
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          Text(value,
              style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
        ],
      ),
    );
  }
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

class _ReceivePaymentSheet extends StatefulWidget {
  final ProjectModel project;
  const _ReceivePaymentSheet({required this.project});

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
                const SizedBox(height: 16),
                PersianAmountField(controller: _amount, label: 'مبلغ (تومان) *'),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _cashAccountId,
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
