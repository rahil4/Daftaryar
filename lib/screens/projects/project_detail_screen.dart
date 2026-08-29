import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/counterparty.dart';
import '../../models/project.dart';
import '../../models/journal_entry.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/quick_add_sheet.dart';
import '../journal/journal_entry_detail_screen.dart';
import 'project_form_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  final ProjectModel project;
  const ProjectDetailScreen({super.key, required this.project});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  final _db = DatabaseHelper.instance;
  late ProjectModel _project;
  CounterpartyModel? _counterparty;
  List<JournalEntryModel> _entries = [];
  double _received = 0;
  double _spent = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final client = await _db.getCounterparty(_project.counterpartyId);
    final entries = await _db.getJournalEntries(projectId: _project.id);
    final financials = await _db.projectFinancials(_project.id!);
    setState(() {
      _counterparty = client;
      _entries = entries;
      _received = financials['received']!;
      _spent = financials['spent']!;
      _loading = false;
    });
  }

  Future<void> _deleteProject() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف پروژه'),
        content: const Text('این پروژه حذف خواهد شد (اسناد حسابداری مرتبط حذف نمی‌شوند). ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: AppColors.negative))),
        ],
      ),
    );
    if (confirm == true) {
      await _db.deleteProject(_project.id!);
      if (mounted) Navigator.pop(context, true);
    }
  }

  void _showAddOptions() {
    showQuickAddSheet(context, presetProjectId: _project.id, onDone: _load);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _project.agreedAmount - _received;
    return Scaffold(
      appBar: AppBar(
        title: Text(_project.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final result = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ProjectFormScreen(existing: _project)));
              if (result == true) {
                final updated = await _db.getProject(_project.id!);
                if (updated != null) setState(() => _project = updated);
                _load();
              }
            },
          ),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteProject),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : BlueprintGridBackground(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.person_outline,
                                    size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 6),
                                Text(_counterparty?.name ?? '—'),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.category_outlined,
                                    size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 6),
                                Text('${_project.projectType} · ${_project.status}'),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.event_outlined,
                                    size: 16, color: AppColors.textSecondary),
                                const SizedBox(width: 6),
                                Text('شروع: ${formatJalaliLong(_project.startDate)}'),
                              ],
                            ),
                            if (_project.description != null) ...[
                              const SizedBox(height: 8),
                              Text(_project.description!,
                                  style: const TextStyle(color: AppColors.textSecondary)),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.6,
                      children: [
                        StatCard(
                          title: 'مبلغ قرارداد',
                          value: formatMoney(_project.agreedAmount),
                          icon: Icons.description_outlined,
                        ),
                        StatCard(
                          title: 'دریافتی',
                          value: formatMoney(_received),
                          icon: Icons.south_west_rounded,
                          valueColor: AppColors.positive,
                        ),
                        StatCard(
                          title: 'هزینه‌های پروژه',
                          value: formatMoney(_spent),
                          icon: Icons.north_east_rounded,
                          valueColor: AppColors.negative,
                        ),
                        StatCard(
                          title: remaining >= 0 ? 'باقی‌مانده طلب' : 'دریافت اضافی',
                          value: formatMoney(remaining.abs()),
                          icon: Icons.account_balance_wallet_outlined,
                          valueColor: remaining > 0 ? AppColors.brass : AppColors.positive,
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('اسناد این پروژه (${pn(_entries.length)})',
                            style: Theme.of(context).textTheme.titleMedium),
                        TextButton.icon(
                          onPressed: _showAddOptions,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('ثبت جدید'),
                        ),
                      ],
                    ),
                    if (_entries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text('هنوز سندی برای این پروژه ثبت نشده',
                            style: TextStyle(color: AppColors.textSecondary)),
                      )
                    else
                      ..._entries.map((e) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.receipt_long_outlined, color: AppColors.brass),
                              title: Text(e.description ?? 'سند شماره ${pn(e.id!)}'),
                              subtitle: Text(
                                  '${formatJalaliLong(e.date)} · ${formatMoney(e.totalDebit)}'),
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
                          )),
                  ],
                ),
              ),
            ),
    );
  }
}
