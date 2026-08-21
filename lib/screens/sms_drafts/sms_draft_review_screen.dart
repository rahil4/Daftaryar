import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/journal_entry.dart';
import '../../models/project.dart';
import '../../models/sms_draft.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/persian_amount_field.dart';
import '../../services/notification_service.dart';

/// بررسی یک پیش‌نویس پیامکی: تأیید (با انتخاب حساب/پروژه) یا رد کردن
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

  List<AccountModel> _cashAccounts = [];
  List<AccountModel> _counterAccounts = []; // درآمد یا هزینه بسته به نوع
  List<ProjectModel> _projects = [];
  int? _cashAccountId;
  int? _counterAccountId;
  int? _projectId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final asset = await _db.getAccounts(type: kAccountAsset);
    final counterAll = await _db.getAccounts(
        type: _type == 'دریافت' ? kAccountIncome : kAccountExpense);
    final leafCounter = _type == 'دریافت'
        ? counterAll
        : counterAll.where((a) => !counterAll.any((x) => x.parentId == a.id)).toList();
    final projects = await _db.getProjects();
    setState(() {
      _cashAccounts = asset;
      _counterAccounts = leafCounter;
      _projects = projects;
      _cashAccountId = asset.isNotEmpty ? asset.first.id : null;
      _counterAccountId = leafCounter.isNotEmpty ? leafCounter.first.id : null;
      _loading = false;
    });
  }

  Future<void> _confirm() async {
    if (_cashAccountId == null || _counterAccountId == null) return;
    setState(() => _saving = true);
    final amount = parsePersianAmount(_amount.text) ?? 0;

    final entry = JournalEntryModel(
      date: _date,
      description: _description.text.trim().isEmpty
          ? (_type == 'دریافت' ? 'دریافت وجه (پیامک بانک)' : 'پرداخت (پیامک بانک)')
          : _description.text.trim(),
      createdAt: todayJalaliString(),
      lines: _type == 'دریافت'
          ? [
              JournalLineModel(accountId: _cashAccountId!, debit: amount, projectId: _projectId),
              JournalLineModel(accountId: _counterAccountId!, credit: amount, projectId: _projectId),
            ]
          : [
              JournalLineModel(accountId: _counterAccountId!, debit: amount, projectId: _projectId),
              JournalLineModel(accountId: _cashAccountId!, credit: amount, projectId: _projectId),
            ],
    );

    try {
      await _db.insertJournalEntry(entry);
      await _db.updateSmsDraftStatus(widget.draft.id!, kSmsDraftConfirmed);
      await _refreshNotificationBadge();
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
    await _refreshNotificationBadge();
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _refreshNotificationBadge() async {
    final pendingCount = await _db.countPendingSmsDrafts();
    await NotificationService.updatePendingDraftsNotification(pendingCount);
  }

  @override
  Widget build(BuildContext context) {
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
                const SizedBox(height: 16),
                PersianAmountField(controller: _amount, label: 'مبلغ (تومان)'),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _cashAccountId,
                  decoration: InputDecoration(
                      labelText: _type == 'دریافت' ? 'واریز به حساب' : 'پرداخت از حساب'),
                  items: _cashAccounts
                      .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _cashAccountId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _counterAccountId,
                  isExpanded: true,
                  decoration: InputDecoration(
                      labelText: _type == 'دریافت' ? 'بابت درآمد' : 'بابت هزینه'),
                  items: _counterAccounts
                      .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                      .toList(),
                  onChanged: (v) => setState(() => _counterAccountId = v),
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
                        onPressed: _saving ? null : _confirm,
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
