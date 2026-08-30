import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/journal_entry.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

class JournalEntryDetailScreen extends StatefulWidget {
  final int entryId;
  const JournalEntryDetailScreen({super.key, required this.entryId});

  @override
  State<JournalEntryDetailScreen> createState() => _JournalEntryDetailScreenState();
}

class _JournalEntryDetailScreenState extends State<JournalEntryDetailScreen> {
  final _db = DatabaseHelper.instance;
  JournalEntryModel? _entry;
  Map<int, AccountModel> _accounts = {};
  Map<int, String> _projectTitles = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entry = await _db.getJournalEntry(widget.entryId);
    final accounts = await _db.getAccounts();
    final projects = await _db.getProjects();
    setState(() {
      _entry = entry;
      _accounts = {for (final a in accounts) a.id!: a};
      _projectTitles = {for (final p in projects) p.id!: p.title};
      _loading = false;
    });
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف سند'),
        content: const Text('این سند حسابداری برای همیشه حذف می‌شود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: AppColors.negative))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _db.deleteJournalEntry(widget.entryId);
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSystemGenerated = _entry?.isSystemGenerated ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text('سند شماره ${pn(widget.entryId)}'),
        actions: [
          if (!isSystemGenerated)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _delete),
        ],
      ),
      body: _loading || _entry == null
          ? const Center(child: CircularProgressIndicator())
          : BlueprintGridBackground(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (isSystemGenerated)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.brass.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'این سند توسط یک عملیات مالی سیستم (نهایی‌سازی/تخفیف/اصلاح/دریافت پروژه) ایجاد شده و برای حفظ یکپارچگی حساب‌ها قابل حذف نیست.',
                        style: TextStyle(fontSize: 12, color: AppColors.brass),
                      ),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('تاریخ: ${formatJalaliLong(_entry!.date)}'),
                          if (_entry!.description != null) ...[
                            const SizedBox(height: 6),
                            Text(_entry!.description!,
                                style: const TextStyle(color: AppColors.textSecondary)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('سطرها', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ..._entry!.lines.map((l) {
                    final account = _accounts[l.accountId];
                    final isDebit = l.debit > 0;
                    return Card(
                      child: ListTile(
                        leading: Icon(
                          isDebit ? Icons.arrow_downward : Icons.arrow_upward,
                          color: isDebit ? AppColors.positive : AppColors.negative,
                        ),
                        title: Text(account?.name ?? '—'),
                        subtitle: Text(
                          '${isDebit ? "بدهکار" : "بستانکار"}'
                          '${l.projectId != null && _projectTitles[l.projectId] != null ? ' · پروژه: ${_projectTitles[l.projectId]}' : ''}'
                          '${l.description != null ? '\n${l.description}' : ''}',
                        ),
                        isThreeLine: l.description != null,
                        trailing: Text(
                          formatMoney(isDebit ? l.debit : l.credit),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDebit ? AppColors.positive : AppColors.negative,
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Card(
                    color: AppColors.surfaceAlt,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('جمع بدهکار / بستانکار'),
                          Text('${formatMoney(_entry!.totalDebit)} / ${formatMoney(_entry!.totalCredit)}'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
