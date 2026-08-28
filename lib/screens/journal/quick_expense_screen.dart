import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/client.dart';
import '../../models/project.dart';
import '../../models/journal_entry.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/persian_amount_field.dart';

/// ثبت سریع پرداخت/هزینه: بدهکار حساب هزینه، بستانکار صندوق/بانک.
/// شخص و پروژه هر دو مستقل و اختیاری‌اند (مثلاً پرداخت به یک فروشنده بدون پروژه).
class QuickExpenseScreen extends StatefulWidget {
  final int? presetProjectId;
  final int? presetClientId;
  const QuickExpenseScreen({super.key, this.presetProjectId, this.presetClientId});

  @override
  State<QuickExpenseScreen> createState() => _QuickExpenseScreenState();
}

class _QuickExpenseScreenState extends State<QuickExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _date = todayJalaliString();

  List<AccountModel> _cashAccounts = [];
  List<AccountModel> _expenseAccounts = [];
  List<ProjectModel> _projects = [];
  List<ClientModel> _clients = [];
  int? _cashAccountId;
  int? _expenseAccountId;
  int? _projectId;
  int? _clientId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _projectId = widget.presetProjectId;
    _clientId = widget.presetClientId;
    _load();
  }

  Future<void> _load() async {
    final asset = await _db.getPostableAccounts(type: kAccountAsset);
    final leafExpenses = await _db.getPostableAccounts(type: kAccountExpense);
    final projects = await _db.getProjects();
    final clients = await _db.getClients();

    int? initialClientId = _clientId;
    if (initialClientId == null && _projectId != null) {
      final matches = projects.where((p) => p.id == _projectId);
      if (matches.isNotEmpty) initialClientId = matches.first.clientId;
    }

    setState(() {
      _cashAccounts = asset;
      _expenseAccounts = leafExpenses;
      _projects = projects;
      _clients = clients;
      _cashAccountId = asset.isNotEmpty ? asset.first.id : null;
      _expenseAccountId = leafExpenses.isNotEmpty ? leafExpenses.first.id : null;
      _clientId = initialClientId;
      _loading = false;
    });
  }

  void _onProjectChanged(int? projectId) {
    setState(() {
      _projectId = projectId;
      if (projectId != null) {
        final matches = _projects.where((p) => p.id == projectId);
        if (matches.isNotEmpty) _clientId = matches.first.clientId;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cashAccountId == null || _expenseAccountId == null) return;
    setState(() => _saving = true);
    final amount = (parsePersianAmount(_amount.text) ?? 0).round();
    final entry = JournalEntryModel(
      date: _date,
      description: _description.text.trim().isEmpty ? 'پرداخت هزینه' : _description.text.trim(),
      createdAt: todayJalaliString(),
      lines: [
        JournalLineModel(
          accountId: _expenseAccountId!,
          debit: amount,
          projectId: _projectId,
          clientId: _clientId,
        ),
        JournalLineModel(
          accountId: _cashAccountId!,
          credit: amount,
          projectId: _projectId,
          clientId: _clientId,
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
      appBar: AppBar(title: const Text('ثبت هزینه / پرداخت')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  PersianAmountField(
                    controller: _amount,
                    label: 'مبلغ (تومان) *',
                    validator: (v) => (v == null || parsePersianAmount(v) == null)
                        ? 'مبلغ معتبر وارد کنید'
                        : null,
                  ),
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
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    value: _cashAccountId,
                    decoration: const InputDecoration(labelText: 'پرداخت از حساب'),
                    items: _cashAccounts
                        .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _cashAccountId = v),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _clientId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'شخص (اختیاری)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      ..._clients.map((c) => DropdownMenuItem(
                          value: c.id, child: Text('${c.name} (${c.relationType})'))),
                    ],
                    onChanged: (v) => setState(() => _clientId = v),
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
                        : const Text('ثبت هزینه'),
                  ),
                ],
              ),
            ),
    );
  }
}
