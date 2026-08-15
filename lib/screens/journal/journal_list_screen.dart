import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/journal_entry.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'journal_entry_detail_screen.dart';
import 'journal_form_screen.dart';
import 'quick_receipt_screen.dart';
import 'quick_expense_screen.dart';

class JournalListScreen extends StatefulWidget {
  const JournalListScreen({super.key});

  @override
  State<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends State<JournalListScreen> {
  final _db = DatabaseHelper.instance;
  List<JournalEntryModel> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getJournalEntries();
    setState(() {
      _entries = list;
      _loading = false;
    });
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.south_west_rounded, color: AppColors.positive),
              title: const Text('ثبت دریافت وجه'),
              subtitle: const Text('دریافت از کارفرما یا سایر منابع'),
              onTap: () async {
                Navigator.pop(ctx);
                final result = await Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const QuickReceiptScreen()));
                if (result == true) _load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.north_east_rounded, color: AppColors.negative),
              title: const Text('ثبت هزینه / پرداخت'),
              subtitle: const Text('هزینه عمومی دفتر یا هزینه پروژه'),
              onTap: () async {
                Navigator.pop(ctx);
                final result = await Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const QuickExpenseScreen()));
                if (result == true) _load();
              },
            ),
            ListTile(
              leading: const Icon(Icons.receipt_long_outlined, color: AppColors.brass),
              title: const Text('سند حسابداری دستی'),
              subtitle: const Text('برای ثبت‌های چندسطری یا خاص'),
              onTap: () async {
                Navigator.pop(ctx);
                final result = await Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const JournalFormScreen()));
                if (result == true) _load();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اسناد حسابداری')),
      body: BlueprintGridBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
                  ? ListView(
                      children: const [
                        Padding(
                          padding: EdgeInsets.only(top: 60),
                          child: Center(
                              child: Text('هنوز سندی ثبت نشده است',
                                  style: TextStyle(color: AppColors.textSecondary))),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: _entries.length,
                      itemBuilder: (ctx, i) {
                        final e = _entries[i];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.receipt_long_outlined, color: AppColors.brass),
                            title: Text(e.description ?? 'سند شماره ${e.id}'),
                            subtitle: Text(
                                '${formatJalaliLong(e.date)} · ${e.lines.length} سطر · ${formatMoney(e.totalDebit)}'),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => JournalEntryDetailScreen(entryId: e.id!)),
                              );
                              _load();
                            },
                          ),
                        );
                      },
                    ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        child: const Icon(Icons.add),
      ),
    );
  }
}
