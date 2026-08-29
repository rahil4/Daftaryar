import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/counterparty.dart';
import '../../models/project.dart';
import '../../models/journal_entry.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/persian_amount_field.dart';

enum _ReceiptMode { cash, creditSale, settleReceivable }

/// ثبت دریافت/درآمد با سه حالت مجزا (مرحله ۳ - چرخه AR):
/// - نقدی: بدهکار صندوق/بانک، بستانکار درآمد (بدون تأثیر بر مطالبات)
/// - ایجاد طلب (نسیه): بدهکار حساب‌های دریافتنی، بستانکار درآمد (بدون تأثیر بر نقد)
/// - دریافت طلب (تسویه): بدهکار صندوق/بانک، بستانکار حساب‌های دریافتنی (بدون ایجاد درآمد جدید)
class QuickReceiptScreen extends StatefulWidget {
  final int? presetProjectId;
  final int? presetCounterpartyId;
  const QuickReceiptScreen({super.key, this.presetProjectId, this.presetCounterpartyId});

  @override
  State<QuickReceiptScreen> createState() => _QuickReceiptScreenState();
}

class _QuickReceiptScreenState extends State<QuickReceiptScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _date = todayJalaliString();
  _ReceiptMode _mode = _ReceiptMode.cash;

  List<AccountModel> _cashAccounts = [];
  List<AccountModel> _incomeAccounts = [];
  List<ProjectModel> _projects = [];
  List<CounterpartyModel> _counterparties = [];
  int? _cashAccountId;
  int? _incomeAccountId;
  int? _projectId;
  int? _counterpartyId;
  double? _currentReceivable;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _projectId = widget.presetProjectId;
    _counterpartyId = widget.presetCounterpartyId;
    _load();
  }

  Future<void> _load() async {
    final asset = await _db.getCashAccounts();
    final incomeAll = await _db.getPostableAccounts(type: kAccountIncome);
    // حساب «حساب‌های دریافتنی» نباید در لیست «بابت درآمد» انتخاب شود
    final arAccount = await _db.getReceivableAccount();
    final income = incomeAll.where((a) => a.id != arAccount?.id).toList();
    final projects = await _db.getProjects();
    final counterparties = await _db.getCounterparties();

    int? initialCounterpartyId = _counterpartyId;
    if (initialCounterpartyId == null && _projectId != null) {
      final matches = projects.where((p) => p.id == _projectId);
      if (matches.isNotEmpty) initialCounterpartyId = matches.first.counterpartyId;
    }

    setState(() {
      _cashAccounts = asset;
      _incomeAccounts = income;
      _projects = projects;
      _counterparties = counterparties;
      _cashAccountId = asset.isNotEmpty ? asset.first.id : null;
      _incomeAccountId = income.isNotEmpty ? income.first.id : null;
      _counterpartyId = initialCounterpartyId;
      _loading = false;
    });
    await _refreshReceivableHint();
  }

  Future<void> _refreshReceivableHint() async {
    if (_mode == _ReceiptMode.settleReceivable && _counterpartyId != null) {
      final bal = await _db.receivableBalance(_counterpartyId!);
      if (mounted) setState(() => _currentReceivable = bal);
    } else {
      setState(() => _currentReceivable = null);
    }
  }

  void _onProjectChanged(int? projectId) {
    setState(() {
      _projectId = projectId;
      if (projectId != null) {
        final matches = _projects.where((p) => p.id == projectId);
        if (matches.isNotEmpty) _counterpartyId = matches.first.counterpartyId;
      }
    });
    _refreshReceivableHint();
  }

  bool get _requiresCounterparty => _mode != _ReceiptMode.cash;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_requiresCounterparty && _counterpartyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('برای ایجاد طلب یا دریافت طلب، انتخاب طرف حساب الزامی است')));
      return;
    }

    setState(() => _saving = true);
    final amount = (parsePersianAmount(_amount.text) ?? 0).round();
    JournalEntryModel entry;

    if (_mode == _ReceiptMode.cash) {
      if (_cashAccountId == null || _incomeAccountId == null) return;
      entry = JournalEntryModel(
        date: _date,
        description: _description.text.trim().isEmpty ? 'دریافت وجه' : _description.text.trim(),
        createdAt: todayJalaliString(),
        lines: [
          JournalLineModel(
              accountId: _cashAccountId!, debit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
          JournalLineModel(
              accountId: _incomeAccountId!, credit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
        ],
      );
    } else if (_mode == _ReceiptMode.creditSale) {
      final arAccount = await _db.getReceivableAccount();
      if (arAccount == null || _incomeAccountId == null) {
        setState(() => _saving = false);
        return;
      }
      entry = JournalEntryModel(
        date: _date,
        description:
            _description.text.trim().isEmpty ? 'ایجاد طلب (فروش نسیه)' : _description.text.trim(),
        createdAt: todayJalaliString(),
        lines: [
          JournalLineModel(
              accountId: arAccount.id!, debit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
          JournalLineModel(
              accountId: _incomeAccountId!, credit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
        ],
      );
    } else {
      final arAccount = await _db.getReceivableAccount();
      if (arAccount == null || _cashAccountId == null) {
        setState(() => _saving = false);
        return;
      }
      entry = JournalEntryModel(
        date: _date,
        description: _description.text.trim().isEmpty ? 'دریافت طلب' : _description.text.trim(),
        createdAt: todayJalaliString(),
        lines: [
          JournalLineModel(
              accountId: _cashAccountId!, debit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
          JournalLineModel(
              accountId: arAccount.id!, credit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
        ],
      );
    }

    try {
      await _db.insertJournalEntry(entry);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final amountValue = parsePersianAmount(_amount.text);
    final overLimit = _mode == _ReceiptMode.settleReceivable &&
        _currentReceivable != null &&
        amountValue != null &&
        amountValue > _currentReceivable!;

    return Scaffold(
      appBar: AppBar(title: const Text('ثبت دریافت / درآمد')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SegmentedButton<_ReceiptMode>(
                    segments: const [
                      ButtonSegment(value: _ReceiptMode.cash, label: Text('نقدی')),
                      ButtonSegment(value: _ReceiptMode.creditSale, label: Text('ایجاد طلب')),
                      ButtonSegment(value: _ReceiptMode.settleReceivable, label: Text('دریافت طلب')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) {
                      setState(() {
                        _mode = s.first;
                        _amount.clear();
                      });
                      _refreshReceivableHint();
                    },
                  ),
                  const SizedBox(height: 16),
                  PersianAmountField(
                    controller: _amount,
                    label: 'مبلغ (تومان) *',
                    onChanged: (_) => setState(() {}),
                    validator: (v) => (v == null || parsePersianAmount(v) == null)
                        ? 'مبلغ معتبر وارد کنید'
                        : null,
                  ),
                  if (_mode != _ReceiptMode.creditSale) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _cashAccountId,
                      decoration: const InputDecoration(labelText: 'واریز به حساب'),
                      items: _cashAccounts
                          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _cashAccountId = v),
                    ),
                  ],
                  if (_mode != _ReceiptMode.settleReceivable) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _incomeAccountId,
                      decoration: const InputDecoration(labelText: 'بابت درآمد'),
                      items: _incomeAccounts
                          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _incomeAccountId = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _counterpartyId,
                    isExpanded: true,
                    decoration: InputDecoration(
                        labelText: _requiresCounterparty ? 'طرف حساب *' : 'طرف حساب (اختیاری)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      ..._counterparties.map((c) => DropdownMenuItem(
                          value: c.id, child: Text('${c.name} (${c.roles.join('، ')})'))),
                    ],
                    onChanged: (v) {
                      setState(() => _counterpartyId = v);
                      _refreshReceivableHint();
                    },
                  ),
                  if (_mode == _ReceiptMode.settleReceivable && _currentReceivable != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'مانده طلب فعلی این طرف حساب: ${formatMoney(_currentReceivable!)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (overLimit)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'مبلغ دریافت بیشتر از مانده طلب است و امکان ثبت این عملیات وجود ندارد.',
                          style: TextStyle(fontSize: 12, color: AppColors.negative, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _projectId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'پروژه (اختیاری)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      ..._projects.map((p) => DropdownMenuItem(value: p.id, child: Text(p.title))),
                    ],
                    onChanged: _onProjectChanged,
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
                  ElevatedButton(
                    onPressed: (_saving || overLimit) ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('ثبت'),
                  ),
                ],
              ),
            ),
    );
  }
}
