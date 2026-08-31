import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/counterparty.dart';
import '../../models/journal_entry.dart';
import '../../models/project.dart';
import '../../models/sms_draft.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/persian_amount_field.dart';

/// بررسی یک پیش‌نویس پیامکی: تأیید (با انتخاب حساب/پروژه) یا رد کردن.
/// چون پیامک بانکی همیشه یک حرکت نقدی واقعی است، دو حالت معنا دارد:
/// دریافت/پرداخت عادی (بستانکار درآمد یا بدهکار هزینه)، یا تسویه طلب/بدهی
/// قبلی (بستانکار/بدهکار حساب‌های دریافتنی/پرداختنی به‌جای درآمد/هزینه).
class SmsDraftReviewScreen extends StatefulWidget {
  final SmsDraftModel draft;
  const SmsDraftReviewScreen({super.key, required this.draft});

  @override
  State<SmsDraftReviewScreen> createState() => _SmsDraftReviewScreenState();
}

class _SmsDraftReviewScreenState extends State<SmsDraftReviewScreen> {
  final _db = DatabaseHelper.instance;
  late final _amount =
      TextEditingController(text: formatMoney(widget.draft.amount, withSuffix: false));
  final _description = TextEditingController();
  late String _date = widget.draft.date;
  late String _type = widget.draft.type; // 'دریافت' یا 'پرداخت'
  bool _isSettlement = false; // تسویه طلب/بدهی به‌جای ثبت درآمد/هزینه جدید

  List<AccountModel> _cashAccounts = [];
  List<AccountModel> _counterAccounts = []; // درآمد یا هزینه بسته به نوع
  List<ProjectModel> _projects = [];
  List<CounterpartyModel> _counterparties = [];
  int? _cashAccountId;
  int? _counterAccountId;
  int? _projectId;
  int? _counterpartyId;
  double? _currentBalance; // مانده طلب/بدهی فعلی، فقط در حالت تسویه
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final asset = await _db.getCashAccounts();
    final leafCounter = await _db.getPostableAccounts(
        type: _type == 'دریافت' ? kAccountIncome : kAccountExpense);
    final projects = await _db.getProjects();
    final counterparties = await _db.getCounterparties();
    setState(() {
      _cashAccounts = asset;
      _counterAccounts = leafCounter;
      _projects = projects;
      _counterparties = counterparties;
      _cashAccountId = asset.isNotEmpty ? asset.first.id : null;
      _counterAccountId = leafCounter.isNotEmpty ? leafCounter.first.id : null;
      _loading = false;
    });
    await _refreshBalanceHint();
  }

  Future<void> _refreshBalanceHint() async {
    if (_isSettlement && _counterpartyId != null) {
      final bal = _type == 'دریافت'
          ? await _db.receivableBalance(_counterpartyId!)
          : await _db.payableBalance(_counterpartyId!);
      if (mounted) setState(() => _currentBalance = bal);
    } else {
      setState(() => _currentBalance = null);
    }
  }

  Future<void> _confirm() async {
    if (_cashAccountId == null) return;
    if (_isSettlement && _counterpartyId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('برای تسویه طلب/بدهی، انتخاب طرف حساب الزامی است')));
      return;
    }

    setState(() => _saving = true);
    final amount = (parsePersianAmount(_amount.text) ?? 0).round();

    int? counterAccountId = _counterAccountId;
    if (_isSettlement) {
      final controlAccount =
          _type == 'دریافت' ? await _db.getReceivableAccount() : await _db.getPayableAccount();
      if (controlAccount == null) {
        setState(() => _saving = false);
        return;
      }
      counterAccountId = controlAccount.id;
    }
    if (counterAccountId == null) {
      setState(() => _saving = false);
      return;
    }

    final defaultDescription = _isSettlement
        ? (_type == 'دریافت' ? 'دریافت طلب (پیامک بانک)' : 'پرداخت بدهی (پیامک بانک)')
        : (_type == 'دریافت' ? 'دریافت وجه (پیامک بانک)' : 'پرداخت (پیامک بانک)');

    final entry = JournalEntryModel(
      date: _date,
      description: _description.text.trim().isEmpty ? defaultDescription : _description.text.trim(),
      createdAt: todayJalaliString(),
      lines: _type == 'دریافت'
          ? [
              JournalLineModel(
                  accountId: _cashAccountId!, debit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
              JournalLineModel(
                  accountId: counterAccountId, credit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
            ]
          : [
              JournalLineModel(
                  accountId: counterAccountId, debit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
              JournalLineModel(
                  accountId: _cashAccountId!, credit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
            ],
    );

    try {
      await _db.createManualJournal(entry);
      await _db.updateSmsDraftStatus(widget.draft.id!, kSmsDraftConfirmed);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _dismiss() async {
    await _db.updateSmsDraftStatus(widget.draft.id!, kSmsDraftDismissed);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final amountValue = parsePersianAmount(_amount.text);
    final overLimit = _isSettlement &&
        _currentBalance != null &&
        amountValue != null &&
        amountValue > _currentBalance!;

    return Scaffold(
      appBar: AppBar(title: const Text('بررسی پیش‌نویس پیامکی')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (widget.draft.sender != null && widget.draft.sender!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('فرستنده: ${widget.draft.sender}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(widget.draft.rawBody,
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'دریافت', label: Text('دریافت')),
                    ButtonSegment(value: 'پرداخت', label: Text('پرداخت')),
                  ],
                  selected: {_type},
                  onSelectionChanged: (s) {
                    setState(() => _type = s.first);
                    _load();
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_type == 'دریافت'
                      ? 'بابت تسویه طلب قبلی است (نه درآمد جدید)'
                      : 'بابت تسویه بدهی قبلی است (نه هزینه جدید)'),
                  value: _isSettlement,
                  onChanged: (v) {
                    setState(() => _isSettlement = v);
                    _refreshBalanceHint();
                  },
                ),
                const SizedBox(height: 8),
                PersianAmountField(
                  controller: _amount,
                  label: 'مبلغ (تومان)',
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: _cashAccountId,
                  decoration: InputDecoration(
                      labelText: _type == 'دریافت' ? 'واریز به حساب' : 'پرداخت از حساب'),
                  items: _cashAccounts
                      .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _cashAccountId = v),
                ),
                if (!_isSettlement) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _counterAccountId,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: _type == 'دریافت' ? 'بابت درآمد' : 'بابت هزینه'),
                    items: _counterAccounts
                        .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _counterAccountId = v),
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: _counterpartyId,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: _isSettlement ? 'طرف حساب *' : 'طرف حساب (اختیاری)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    ..._counterparties.map((c) => DropdownMenuItem(
                        value: c.id, child: Text('${c.name} (${c.roles.join('، ')})'))),
                  ],
                  onChanged: (v) {
                    setState(() => _counterpartyId = v);
                    _refreshBalanceHint();
                  },
                ),
                if (_isSettlement && _currentBalance != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _type == 'دریافت'
                        ? 'مانده طلب فعلی این طرف حساب: ${formatMoney(_currentBalance!)}'
                        : 'مانده بدهی فعلی به این طرف حساب: ${formatMoney(_currentBalance!)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  if (overLimit)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        _type == 'دریافت'
                            ? 'مبلغ دریافت بیشتر از مانده طلب است و امکان ثبت این عملیات وجود ندارد.'
                            : 'مبلغ پرداخت بیشتر از مانده بدهی است و امکان ثبت این عملیات وجود ندارد.',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.negative, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: _projectId,
                  decoration: const InputDecoration(labelText: 'پروژه (اختیاری)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    ..._projects.map((p) => DropdownMenuItem(value: p.id, child: Text(p.title))),
                  ],
                  onChanged: (v) => setState(() => _projectId = v),
                ),
                const SizedBox(height: 12),
                JalaliDateField(
                  label: 'تاریخ',
                  value: _date,
                  onChanged: (v) => setState(() => _date = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(labelText: 'شرح (اختیاری)'),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _dismiss,
                        child: const Text('رد کردن'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: (_saving || overLimit) ? null : _confirm,
                        child: _saving
                            ? const SizedBox(
                                height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('تأیید و ثبت'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
