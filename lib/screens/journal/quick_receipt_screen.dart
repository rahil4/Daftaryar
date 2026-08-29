import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/counterparty.dart';
import '../../models/project.dart';
import '../../models/journal_entry.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/persian_amount_field.dart';

/// ثبت سریع دریافت وجه: بدهکار صندوق/بانک، بستانکار حساب درآمد.
/// شخص و پروژه هر دو مستقل و اختیاری‌اند (مثلاً دریافت از یک شخص بدون پروژه).
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

  List<AccountModel> _cashAccounts = [];
  List<AccountModel> _incomeAccounts = [];
  List<ProjectModel> _projects = [];
  List<CounterpartyModel> _counterparties = [];
  int? _cashAccountId;
  int? _incomeAccountId;
  int? _projectId;
  int? _counterpartyId;
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
    final income = await _db.getPostableAccounts(type: kAccountIncome);
    final projects = await _db.getProjects();
    final clients = await _db.getCounterparties();

    // اگر پروژه از قبل انتخاب شده و شخصی هنوز مشخص نشده، کارفرمای همان پروژه را پیشنهاد بده
    int? initialCounterpartyId = _counterpartyId;
    if (initialCounterpartyId == null && _projectId != null) {
      final matches = projects.where((p) => p.id == _projectId);
      if (matches.isNotEmpty) initialCounterpartyId = matches.first.counterpartyId;
    }

    setState(() {
      _cashAccounts = asset;
      _incomeAccounts = income;
      _projects = projects;
      _counterparties = clients;
      _cashAccountId = asset.isNotEmpty ? asset.first.id : null;
      _incomeAccountId = income.isNotEmpty ? income.first.id : null;
      _counterpartyId = initialCounterpartyId;
      _loading = false;
    });
  }

  void _onProjectChanged(int? projectId) {
    setState(() {
      _projectId = projectId;
      if (projectId != null) {
        final matches = _projects.where((p) => p.id == projectId);
        if (matches.isNotEmpty) _counterpartyId = matches.first.counterpartyId;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cashAccountId == null || _incomeAccountId == null) return;
    setState(() => _saving = true);
    final amount = (parsePersianAmount(_amount.text) ?? 0).round();
    final entry = JournalEntryModel(
      date: _date,
      description: _description.text.trim().isEmpty ? 'دریافت وجه' : _description.text.trim(),
      createdAt: todayJalaliString(),
      lines: [
        JournalLineModel(
          accountId: _cashAccountId!,
          debit: amount,
          projectId: _projectId,
          counterpartyId: _counterpartyId,
        ),
        JournalLineModel(
          accountId: _incomeAccountId!,
          credit: amount,
          projectId: _projectId,
          counterpartyId: _counterpartyId,
        ),
      ],
    );
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
    return Scaffold(
      appBar: AppBar(title: const Text('ثبت دریافت وجه')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  PersianAmountField(
                    controller: _amount,
                    label: 'مبلغ دریافتی (تومان) *',
                    validator: (v) => (v == null || parsePersianAmount(v) == null)
                        ? 'مبلغ معتبر وارد کنید'
                        : null,
                  ),
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
                  DropdownButtonFormField<int>(
                    value: _incomeAccountId,
                    decoration: const InputDecoration(labelText: 'بابت درآمد'),
                    items: _incomeAccounts
                        .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _incomeAccountId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _counterpartyId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'طرف حساب (اختیاری)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      ..._counterparties.map((c) => DropdownMenuItem(
                          value: c.id, child: Text('${c.name} (${c.roles.join('، ')})'))),
                    ],
                    onChanged: (v) => setState(() => _counterpartyId = v),
                  ),
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
                        : const Text('ثبت دریافت'),
                  ),
                ],
              ),
            ),
    );
  }
}
