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

/// سند حسابداری دستی با چند سطر بدهکار/بستانکار دلخواه
class JournalFormScreen extends StatefulWidget {
  final int? presetProjectId;
  final int? presetCounterpartyId;
  const JournalFormScreen({super.key, this.presetProjectId, this.presetCounterpartyId});

  @override
  State<JournalFormScreen> createState() => _JournalFormScreenState();
}

class _JournalLineDraft {
  int? accountId;
  String side = 'debit'; // debit یا credit
  final amount = TextEditingController();
  final description = TextEditingController();
  int? projectId;
  int? counterpartyId;
}

class _JournalFormScreenState extends State<JournalFormScreen> {
  final _db = DatabaseHelper.instance;
  final _description = TextEditingController();
  String _date = todayJalaliString();
  List<AccountModel> _accounts = [];
  List<ProjectModel> _projects = [];
  List<CounterpartyModel> _counterparties = [];
  List<_JournalLineDraft> _lines = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _lines = [
      _JournalLineDraft()
        ..projectId = widget.presetProjectId
        ..counterpartyId = widget.presetCounterpartyId,
      _JournalLineDraft()
        ..projectId = widget.presetProjectId
        ..counterpartyId = widget.presetCounterpartyId,
    ];
    _load();
  }

  Future<void> _load() async {
    final accounts = await _db.getPostableAccounts();
    final projects = await _db.getProjects();
    final clients = await _db.getCounterparties();
    setState(() {
      _accounts = accounts;
      _projects = projects;
      _counterparties = clients;
      _loading = false;
    });
  }

  void _addLine() {
    setState(() => _lines.add(_JournalLineDraft()
      ..projectId = widget.presetProjectId
      ..counterpartyId = widget.presetCounterpartyId));
  }

  void _removeLine(int index) {
    setState(() => _lines.removeAt(index));
  }

  int get _totalDebit => _lines
      .where((l) => l.side == 'debit')
      .fold<int>(0, (s, l) => s + (parsePersianAmount(l.amount.text) ?? 0).round());

  int get _totalCredit => _lines
      .where((l) => l.side == 'credit')
      .fold<int>(0, (s, l) => s + (parsePersianAmount(l.amount.text) ?? 0).round());

  Future<void> _save() async {
    final validLines = _lines.where((l) {
      final amount = (parsePersianAmount(l.amount.text) ?? 0).round();
      return l.accountId != null && amount > 0;
    }).toList();

    if (validLines.length < 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('حداقل دو سطر معتبر لازم است')));
      return;
    }

    final totalDebit = validLines
        .where((l) => l.side == 'debit')
        .fold<int>(0, (s, l) => s + (parsePersianAmount(l.amount.text) ?? 0).round());
    final totalCredit = validLines
        .where((l) => l.side == 'credit')
        .fold<int>(0, (s, l) => s + (parsePersianAmount(l.amount.text) ?? 0).round());

    if (totalDebit != totalCredit) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('سند متوازن نیست؛ جمع بدهکار باید با جمع بستانکار برابر باشد')));
      return;
    }

    setState(() => _saving = true);

    final entry = JournalEntryModel(
      date: _date,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      createdAt: todayJalaliString(),
      lines: validLines
          .map((l) => JournalLineModel(
                accountId: l.accountId!,
                debit: l.side == 'debit' ? (parsePersianAmount(l.amount.text) ?? 0).round() : 0,
                credit: l.side == 'credit' ? (parsePersianAmount(l.amount.text) ?? 0).round() : 0,
                description: l.description.text.trim().isEmpty ? null : l.description.text.trim(),
                projectId: l.projectId,
                counterpartyId: l.counterpartyId,
              ))
          .toList(),
    );

    try {
      await _db.createManualJournal(entry);
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

  @override
  Widget build(BuildContext context) {
    final balanced = _totalDebit == _totalCredit && _totalDebit > 0;
    return Scaffold(
      appBar: AppBar(title: const Text('سند حسابداری جدید')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                JalaliDateField(
                  label: 'تاریخ سند',
                  value: _date,
                  onChanged: (v) => setState(() => _date = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(labelText: 'شرح سند'),
                ),
                const SizedBox(height: 20),
                Text('سطرها', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                for (int i = 0; i < _lines.length; i++) _buildLineCard(i),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _addLine,
                  icon: const Icon(Icons.add),
                  label: const Text('افزودن سطر'),
                ),
                const SizedBox(height: 20),
                Card(
                  color: AppColors.surfaceAlt,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('جمع بدهکار'),
                            Text(formatMoney(_totalDebit)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('جمع بستانکار'),
                            Text(formatMoney(_totalCredit)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          balanced ? 'سند متوازن است ✓' : 'سند متوازن نیست',
                          style: TextStyle(
                            color: balanced ? AppColors.positive : AppColors.negative,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('ثبت سند'),
                ),
              ],
            ),
    );
  }

  Widget _buildLineCard(int index) {
    final line = _lines[index];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: line.accountId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'حساب', isDense: true),
                    items: _accounts
                        .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (v) => setState(() => line.accountId = v),
                  ),
                ),
                if (_lines.length > 2)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => _removeLine(index),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'debit', label: Text('بدهکار')),
                      ButtonSegment(value: 'credit', label: Text('بستانکار')),
                    ],
                    selected: {line.side},
                    onSelectionChanged: (s) => setState(() => line.side = s.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            PersianAmountField(
              controller: line.amount,
              label: 'مبلغ (تومان)',
              isDense: true,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: line.counterpartyId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'طرف حساب (اختیاری)', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                ..._counterparties.map((c) => DropdownMenuItem(
                    value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) => setState(() => line.counterpartyId = v),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: line.projectId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'پروژه (اختیاری)', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('—')),
                ..._projects.map((p) => DropdownMenuItem(value: p.id, child: Text(p.title, overflow: TextOverflow.ellipsis))),
              ],
              onChanged: (v) => setState(() => line.projectId = v),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: line.description,
              decoration: const InputDecoration(labelText: 'شرح سطر (اختیاری)', isDense: true),
            ),
          ],
        ),
      ),
    );
  }
}
