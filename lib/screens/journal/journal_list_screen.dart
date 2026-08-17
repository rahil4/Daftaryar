import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/journal_entry.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/quick_add_sheet.dart';
import 'journal_entry_detail_screen.dart';

enum _TypeFilter { all, receipt, payment, other }

class JournalListScreen extends StatefulWidget {
  const JournalListScreen({super.key});

  @override
  State<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends State<JournalListScreen> {
  final _db = DatabaseHelper.instance;

  List<JournalEntryModel> _entries = [];
  Map<int, AccountModel> _accountsById = {};
  List<ProjectModel> _projects = [];
  bool _loading = true;

  // فیلترها
  String _search = '';
  _TypeFilter _typeFilter = _TypeFilter.all;
  int? _projectFilter;
  String? _fromDate;
  String? _toDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await _db.getJournalEntries(
      projectId: _projectFilter,
      fromDate: _fromDate,
      toDate: _toDate,
    );
    final accounts = await _db.getAccounts();
    final projects = await _db.getProjects();
    setState(() {
      _entries = entries;
      _accountsById = {for (final a in accounts) a.id!: a};
      _projects = projects;
      _loading = false;
    });
  }

  /// نوع سند را بر اساس حساب‌های طرفین سطرها تشخیص می‌دهد
  _TypeFilter _entryType(JournalEntryModel e) {
    final hasIncomeCredit = e.lines
        .any((l) => l.credit > 0 && _accountsById[l.accountId]?.type == kAccountIncome);
    final hasExpenseDebit = e.lines
        .any((l) => l.debit > 0 && _accountsById[l.accountId]?.type == kAccountExpense);
    if (hasIncomeCredit && !hasExpenseDebit) return _TypeFilter.receipt;
    if (hasExpenseDebit && !hasIncomeCredit) return _TypeFilter.payment;
    return _TypeFilter.other;
  }

  List<JournalEntryModel> get _filtered {
    return _entries.where((e) {
      if (_typeFilter != _TypeFilter.all && _entryType(e) != _typeFilter) return false;
      if (_search.trim().isNotEmpty) {
        final q = _search.trim();
        final inEntryDesc = (e.description ?? '').contains(q);
        final inLineDesc = e.lines.any((l) => (l.description ?? '').contains(q));
        final inAccountName =
            e.lines.any((l) => (_accountsById[l.accountId]?.name ?? '').contains(q));
        if (!inEntryDesc && !inLineDesc && !inAccountName) return false;
      }
      return true;
    }).toList();
  }

  bool get _hasActiveFilters =>
      _typeFilter != _TypeFilter.all ||
      _projectFilter != null ||
      _fromDate != null ||
      _toDate != null;

  void _resetFilters() {
    setState(() {
      _typeFilter = _TypeFilter.all;
      _projectFilter = null;
      _fromDate = null;
      _toDate = null;
    });
    _load();
  }

  Future<void> _openDateFilterSheet() async {
    String from = _fromDate ?? todayJalaliString();
    String to = _toDate ?? todayJalaliString();
    final applied = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('فیلتر بازه تاریخ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: JalaliDateField(
                        label: 'از تاریخ',
                        value: from,
                        onChanged: (v) => setSheetState(() => from = v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: JalaliDateField(
                        label: 'تا تاریخ',
                        value: to,
                        onChanged: (v) => setSheetState(() => to = v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('پاک کردن بازه'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          _fromDate = from;
                          _toDate = to;
                          Navigator.pop(ctx, true);
                        },
                        child: const Text('اعمال'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == false) {
      setState(() {
        _fromDate = null;
        _toDate = null;
      });
      _load();
    } else if (applied == true) {
      _load();
    }
  }

  Future<void> _openProjectFilterSheet() async {
    final selected = await showModalBottomSheet<int?>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              title: const Text('همه پروژه‌ها'),
              trailing: _projectFilter == null ? const Icon(Icons.check, color: AppColors.brass) : null,
              onTap: () => Navigator.pop(ctx, -1),
            ),
            const Divider(color: AppColors.gridLine, height: 1),
            ..._projects.map((p) => ListTile(
                  title: Text(p.title),
                  trailing:
                      _projectFilter == p.id ? const Icon(Icons.check, color: AppColors.brass) : null,
                  onTap: () => Navigator.pop(ctx, p.id),
                )),
          ],
        ),
      ),
    );
    if (selected != null) {
      setState(() => _projectFilter = selected == -1 ? null : selected);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    return Scaffold(
      appBar: AppBar(title: const Text('اسناد حسابداری')),
      body: BlueprintGridBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'جستجو در شرح، حساب یا پروژه...',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: (v) => setState(() => _search = v),
              ),
            ),
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _filterChip('همه', _typeFilter == _TypeFilter.all, () {
                    setState(() => _typeFilter = _TypeFilter.all);
                  }),
                  _filterChip('دریافت', _typeFilter == _TypeFilter.receipt, () {
                    setState(() => _typeFilter = _TypeFilter.receipt);
                  }),
                  _filterChip('پرداخت', _typeFilter == _TypeFilter.payment, () {
                    setState(() => _typeFilter = _TypeFilter.payment);
                  }),
                  _filterChip(
                    _projectFilter == null
                        ? 'پروژه'
                        : (_projects.where((p) => p.id == _projectFilter).firstOrNull?.title ?? 'پروژه'),
                    _projectFilter != null,
                    _openProjectFilterSheet,
                    icon: Icons.work_outline,
                  ),
                  _filterChip(
                    _fromDate == null ? 'بازه تاریخ' : 'تاریخ: ${formatJalaliLong(_fromDate!)}—${formatJalaliLong(_toDate!)}',
                    _fromDate != null,
                    _openDateFilterSheet,
                    icon: Icons.date_range_outlined,
                  ),
                  if (_hasActiveFilters)
                    _filterChip('پاک کردن فیلترها', false, _resetFilters, icon: Icons.close),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? const Center(
                          child: Text('سندی با این فیلترها یافت نشد',
                              style: TextStyle(color: AppColors.textSecondary)))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            children: _buildGroupedRows(filtered),
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showQuickAddSheet(context, onDone: _load),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _filterChip(String label, bool active, VoidCallback onTap, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: active ? AppColors.brass.withOpacity(0.15) : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: active ? AppColors.brass : AppColors.gridLine),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 14, color: active ? AppColors.brass : AppColors.textSecondary),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: active ? AppColors.brass : AppColors.textSecondary,
                  fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// اسناد را زیر سرتیتر تاریخ گروه‌بندی می‌کند - مثل روزنامه حسابداری کاغذی
  List<Widget> _buildGroupedRows(List<JournalEntryModel> entries) {
    final widgets = <Widget>[];
    String? lastDate;
    for (final e in entries) {
      if (e.date != lastDate) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 6),
          child: Text(
            formatJalaliLong(e.date),
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.brass),
          ),
        ));
        lastDate = e.date;
      }
      widgets.add(_JournalRow(
        entry: e,
        type: _entryType(e),
        projectTitle: e.lines
            .map((l) => l.projectId)
            .whereType<int>()
            .map((id) => _projects.where((p) => p.id == id).firstOrNull?.title)
            .whereType<String>()
            .firstOrNull,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => JournalEntryDetailScreen(entryId: e.id!)),
          );
          _load();
        },
      ));
    }
    return widgets;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// ردیف یک سند در فهرست - سبک متنی سنتی، بدون کارت
class _JournalRow extends StatelessWidget {
  final JournalEntryModel entry;
  final _TypeFilter type;
  final String? projectTitle;
  final VoidCallback onTap;

  const _JournalRow({
    required this.entry,
    required this.type,
    required this.projectTitle,
    required this.onTap,
  });

  Color get _typeColor {
    switch (type) {
      case _TypeFilter.receipt:
        return AppColors.positive;
      case _TypeFilter.payment:
        return AppColors.negative;
      default:
        return AppColors.textPrimary;
    }
  }

  String get _typeLabel {
    switch (type) {
      case _TypeFilter.receipt:
        return 'دریافت';
      case _TypeFilter.payment:
        return 'پرداخت';
      default:
        return 'سند';
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.gridLine)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.description ?? 'سند شماره ${pn(entry.id!)}',
                    style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$_typeLabel${projectTitle != null ? ' · $projectTitle' : ''}',
                    style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatMoney(entry.totalDebit),
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _typeColor),
            ),
            const SizedBox(width: 4),
            const Text('‹', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
