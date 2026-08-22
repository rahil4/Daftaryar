import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/project.dart';
import '../../models/journal_entry.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/persian_amount_field.dart';

/// ثبت سریع دریافت وجه: بدهکار صندوق/بانک، بستانکار حساب درآمد
class QuickReceiptScreen extends StatefulWidget {
  final int? presetProjectId;
  const QuickReceiptScreen({super.key, this.presetProjectId});

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
  int? _cashAccountId;
  int? _incomeAccountId;
  int? _projectId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _projectId = widget.presetProjectId;
    _load();
  }

  Future<void> _load() async {
    final asset = await _db.getAccounts(type: kAccountAsset);
    final incomeAll = await _db.getAccounts(type: kAccountIncome);
    // فقط حساب‌های برگ (بدون زیرحساب) برای انتخاب مناسب‌اند، هماهنگ با فرم ثبت هزینه
    final income = incomeAll.where((a) => !incomeAll.any((x) => x.parentId == a.id)).toList();
    final projects = await _db.getProjects();
    setState(() {
      _cashAccounts = asset;
      _incomeAccounts = income;
      _projects = projects;
      _cashAccountId = asset.isNotEmpty ? asset.first.id : null;
      _incomeAccountId = income.isNotEmpty ? income.first.id : null;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_cashAccountId == null || _incomeAccountId == null) return;
    setState(() => _saving = true);
    final amount = parsePersianAmount(_amount.text) ?? 0;
    final entry = JournalEntryModel(
      date: _date,
      description: _description.text.trim().isEmpty ? 'دریافت وجه' : _description.text.trim(),
      createdAt: todayJalaliString(),
      lines: [
        JournalLineModel(accountId: _cashAccountId!, debit: amount, projectId: _projectId),
        JournalLineModel(accountId: _incomeAccountId!, credit: amount, projectId: _projectId),
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
                    value: _projectId,
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
