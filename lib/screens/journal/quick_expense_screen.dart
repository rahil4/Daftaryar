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

enum _ExpenseMode { cash, creditExpense, settlePayable }

/// ثبت هزینه/پرداخت با سه حالت مجزا (مرحله ۳ - چرخه AP):
/// - نقدی: بدهکار هزینه، بستانکار صندوق/بانک (بدون تأثیر بر بدهی)
/// - ایجاد بدهی (نسیه): بدهکار هزینه، بستانکار حساب‌های پرداختنی (بدون تأثیر بر نقد)
/// - پرداخت بدهی (تسویه): بدهکار حساب‌های پرداختنی، بستانکار صندوق/بانک (بدون ایجاد هزینه جدید)
class QuickExpenseScreen extends StatefulWidget {
  final int? presetProjectId;
  final int? presetCounterpartyId;
  const QuickExpenseScreen({super.key, this.presetProjectId, this.presetCounterpartyId});

  @override
  State<QuickExpenseScreen> createState() => _QuickExpenseScreenState();
}

class _QuickExpenseScreenState extends State<QuickExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _date = todayJalaliString();
  _ExpenseMode _mode = _ExpenseMode.cash;

  List<AccountModel> _cashAccounts = [];
  List<AccountModel> _expenseAccounts = [];
  List<ProjectModel> _projects = [];
  List<CounterpartyModel> _counterparties = [];
  int? _cashAccountId;
  int? _expenseAccountId;
  int? _projectId;
  int? _counterpartyId;
  double? _currentPayable;
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
    final asset = await _db.getPostableAccounts(type: kAccountAsset);
    final leafExpenses = await _db.getPostableAccounts(type: kAccountExpense);
    final projects = await _db.getProjects();
    final counterparties = await _db.getCounterparties();

    int? initialCounterpartyId = _counterpartyId;
    if (initialCounterpartyId == null && _projectId != null) {
      final matches = projects.where((p) => p.id == _projectId);
      if (matches.isNotEmpty) initialCounterpartyId = matches.first.counterpartyId;
    }

    setState(() {
      _cashAccounts = asset;
      _expenseAccounts = leafExpenses;
      _projects = projects;
      _counterparties = counterparties;
      _cashAccountId = asset.isNotEmpty ? asset.first.id : null;
      _expenseAccountId = leafExpenses.isNotEmpty ? leafExpenses.first.id : null;
      _counterpartyId = initialCounterpartyId;
      _loading = false;
    });
    await _refreshPayableHint();
  }

  Future<void> _refreshPayableHint() async {
    if (_mode == _ExpenseMode.settlePayable && _counterpartyId != null) {
      final bal = await _db.payableBalance(_counterpartyId!);
      if (mounted) setState(() => _currentPayable = bal);
    } else {
      setState(() => _currentPayable = null);
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
    _refreshPayableHint();
  }

  bool get _requiresCounterparty => _mode != _ExpenseMode.cash;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_requiresCounterparty && _counterpartyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('برای ایجاد بدهی یا پرداخت بدهی، انتخاب طرف حساب الزامی است')));
      return;
    }

    setState(() => _saving = true);
    final amount = (parsePersianAmount(_amount.text) ?? 0).round();
    JournalEntryModel entry;

    if (_mode == _ExpenseMode.cash) {
      if (_cashAccountId == null || _expenseAccountId == null) return;
      entry = JournalEntryModel(
        date: _date,
        description: _description.text.trim().isEmpty ? 'پرداخت هزینه' : _description.text.trim(),
        createdAt: todayJalaliString(),
        lines: [
          JournalLineModel(
              accountId: _expenseAccountId!, debit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
          JournalLineModel(
              accountId: _cashAccountId!, credit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
        ],
      );
    } else if (_mode == _ExpenseMode.creditExpense) {
      final apAccount = await _db.getPayableAccount();
      if (apAccount == null || _expenseAccountId == null) {
        setState(() => _saving = false);
        return;
      }
      entry = JournalEntryModel(
        date: _date,
        description:
            _description.text.trim().isEmpty ? 'ایجاد بدهی (هزینه نسیه)' : _description.text.trim(),
        createdAt: todayJalaliString(),
        lines: [
          JournalLineModel(
              accountId: _expenseAccountId!, debit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
          JournalLineModel(
              accountId: apAccount.id!, credit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
        ],
      );
    } else {
      final apAccount = await _db.getPayableAccount();
      if (apAccount == null || _cashAccountId == null) {
        setState(() => _saving = false);
        return;
      }
      entry = JournalEntryModel(
        date: _date,
        description: _description.text.trim().isEmpty ? 'پرداخت بدهی' : _description.text.trim(),
        createdAt: todayJalaliString(),
        lines: [
          JournalLineModel(
              accountId: apAccount.id!, debit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
          JournalLineModel(
              accountId: _cashAccountId!, credit: amount, projectId: _projectId, counterpartyId: _counterpartyId),
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
    final overLimit = _mode == _ExpenseMode.settlePayable &&
        _currentPayable != null &&
        amountValue != null &&
        amountValue > _currentPayable!;

    return Scaffold(
      appBar: AppBar(title: const Text('ثبت هزینه / پرداخت')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SegmentedButton<_ExpenseMode>(
                    segments: const [
                      ButtonSegment(value: _ExpenseMode.cash, label: Text('نقدی')),
                      ButtonSegment(value: _ExpenseMode.creditExpense, label: Text('ایجاد بدهی')),
                      ButtonSegment(value: _ExpenseMode.settlePayable, label: Text('پرداخت بدهی')),
                    ],
                    selected: {_mode},
                    onSelectionChanged: (s) {
                      setState(() {
                        _mode = s.first;
                        _amount.clear();
                      });
                      _refreshPayableHint();
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
                  if (_mode != _ExpenseMode.settlePayable) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _expenseAccountId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'بابت هزینه'),
                      items: _expenseAccounts
                          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _expenseAccountId = v),
                    ),
                  ],
                  if (_mode != _ExpenseMode.creditExpense) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      value: _cashAccountId,
                      decoration: const InputDecoration(labelText: 'پرداخت از حساب'),
                      items: _cashAccounts
                          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _cashAccountId = v),
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
                      _refreshPayableHint();
                    },
                  ),
                  if (_mode == _ExpenseMode.settlePayable && _currentPayable != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'مانده بدهی فعلی به این طرف حساب: ${formatMoney(_currentPayable!)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (overLimit)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          '⚠️ این مبلغ از مانده بدهی فعلی بیشتر است؛ پس از ثبت، مانده این طرف حساب بدهکار (منفی) خواهد شد.',
                          style: TextStyle(fontSize: 12, color: AppColors.negative),
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
                    onPressed: _saving ? null : _save,
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
