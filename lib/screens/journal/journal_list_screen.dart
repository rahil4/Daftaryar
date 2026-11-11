import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/journal_entry.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/reloadable.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/quick_add_sheet.dart';
import 'journal_entry_detail_screen.dart';

enum _TypeFilter { all, receipt, payment, other }

class JournalListScreen extends StatefulWidget {
  final bool embedded;
  const JournalListScreen({super.key, this.embedded = false});

  @override
  State<JournalListScreen> createState() => _JournalListScreenState();
}

class _JournalListScreenState extends State<JournalListScreen> with Reloadable<JournalListScreen> {
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

  @override
  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await _db.getJournalEntries(
      projectId: _projectFilter,
      fromDate: _fromDate,
      toDate: _toDate,
    );
    final accounts = await _db.getAccounts();
    final projects = await _db.getProjects();
    if (!mounted) return;
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
    if (applied == false && mounted) {
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

  /// برگه «فیلتر»: پروژه و بازه تاریخ - دو فیلتر کم‌استفاده‌تر که دیگر روی
  /// صفحه چیپ جدا نمی‌گیرند.
  Future<void> _openFilterSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('فیلتر اسناد', style: AppTextStyles.blockHeading),
              const SizedBox(height: 8),
              _filterRow(
                icon: Icons.work_outline,
                label: 'پروژه',
                value: _projectFilter == null
                    ? 'همه پروژه‌ها'
                    : (_projects.where((p) => p.id == _projectFilter).firstOrNull?.title ?? 'پروژه'),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _openProjectFilterSheet();
                },
              ),
              const Divider(height: 1),
              _filterRow(
                icon: Icons.date_range_outlined,
                label: 'بازه تاریخ',
                value: _fromDate == null
                    ? 'بدون محدودیت'
                    : '${formatJalaliLong(_fromDate!)} تا ${formatJalaliLong(_toDate!)}',
                onTap: () async {
                  Navigator.pop(ctx);
                  await _openDateFilterSheet();
                },
              ),
              if (_hasActiveFilters) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _resetFilters();
                  },
                  child: const Text('پاک کردن فیلترها'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterRow({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Row(
          children: [
            Icon(icon, size: 20, color: AppColors.textSecondary),
            const SizedBox(width: 12),
            Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_left, size: 18, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'جستجو در شرح، حساب یا پروژه',
                    prefixIcon: Icon(Icons.search, size: 20),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),
              const SizedBox(width: 8),
              Badge(
                isLabelVisible: _projectFilter != null || _fromDate != null,
                smallSize: 9,
                backgroundColor: AppColors.brass,
                child: Material(
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: const BorderSide(color: AppColors.gridLine),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _openFilterSheet,
                    child: const Tooltip(
                      message: 'فیلتر پروژه و بازه تاریخ',
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(Icons.tune, size: 20, color: AppColors.textSecondary),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
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
              _filterChip('سایر اسناد', _typeFilter == _TypeFilter.other, () {
                setState(() => _typeFilter = _TypeFilter.other);
              }),
              if (_hasActiveFilters && _typeFilter == _TypeFilter.all)
                _filterChip('پاک کردن فیلترها', false, _resetFilters, icon: Icons.close),
            ],
          ),
        ),
        SizedBox(
          height: 2,
          child: (_loading && _entries.isNotEmpty) ? const LinearProgressIndicator(minHeight: 2) : null,
        ),
        Expanded(
          child: (_loading && _entries.isEmpty)
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text(
                          (_hasActiveFilters || _search.trim().isNotEmpty)
                              ? 'سندی با این فیلترها یافت نشد'
                              : 'هنوز سندی ثبت نشده است',
                          style: const TextStyle(color: AppColors.textSecondary)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        children: _buildGroupedRows(filtered),
                      ),
                    ),
        ),
      ],
    );

    // داخل پوسته اصلی، ثبت جدید از دکمه «+» نوار پایین انجام می‌شود.
    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('اسناد حسابداری')),
      body: BlueprintGridBackground(child: content),
      floatingActionButton: FloatingActionButton(
        heroTag: 'journal_fab',
        onPressed: () => showQuickAddSheet(context, onDone: _load),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _filterChip(String label, bool active, VoidCallback onTap, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Semantics(
        button: true,
        selected: active,
        child: Material(
          color: active ? AppColors.brass.withValues(alpha: 0.14) : AppColors.surface,
          shape: StadiumBorder(
            side: BorderSide(color: active ? AppColors.brass : AppColors.gridLine, width: active ? 1.5 : 1),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: active ? AppColors.brassLight : AppColors.textPrimary,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// اسناد را زیر سرتیتر تاریخ گروه‌بندی می‌کند - مثل روزنامه حسابداری کاغذی
  List<Widget> _buildGroupedRows(List<JournalEntryModel> entries) {
    final widgets = <Widget>[];
    String? lastDate;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final isGroupStart = e.date != lastDate;
      if (isGroupStart) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 4),
          child: Text(
            formatJalaliLong(e.date),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brassLight),
          ),
        ));
        lastDate = e.date;
      }
      final isGroupEnd = i == entries.length - 1 || entries[i + 1].date != e.date;
      widgets.add(_JournalRow(
        entry: e,
        type: _entryType(e),
        accountSummary: _accountSummary(e),
        showDivider: !isGroupEnd,
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => JournalEntryDetailScreen(entryId: e.id!)),
          );
          if (mounted) _load();
        },
      ));
    }
    return widgets;
  }

  /// خلاصه «بد … · بس …» یک سند: نام اولین حساب هر طرف، و اگر بیشتر از یک
  /// حساب باشد، تعداد بقیه.
  String _accountSummary(JournalEntryModel e) {
    String side(bool debit) {
      final names = <String>[];
      for (final l in e.lines) {
        if ((debit ? l.debit : l.credit) <= 0) continue;
        final name = _accountsById[l.accountId]?.name;
        if (name != null && !names.contains(name)) names.add(name);
      }
      if (names.isEmpty) return '—';
      return names.length == 1 ? names.first : '${names.first} و ${pn(names.length - 1)} حساب دیگر';
    }

    return 'بد ${side(true)} · بس ${side(false)}';
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// ردیف یک سند در فهرست - سبک متنی سنتی، بدون کارت. جهت (دریافت/پرداخت)
/// با شکل پیکان هم گفته می‌شود، نه فقط رنگ.
class _JournalRow extends StatelessWidget {
  final JournalEntryModel entry;
  final _TypeFilter type;
  final String accountSummary;
  final bool showDivider;
  final VoidCallback onTap;

  const _JournalRow({
    required this.entry,
    required this.type,
    required this.accountSummary,
    required this.showDivider,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    final Color color;
    switch (type) {
      case _TypeFilter.receipt:
        icon = Icons.arrow_downward_rounded;
        color = AppColors.positive;
      case _TypeFilter.payment:
        icon = Icons.arrow_upward_rounded;
        color = AppColors.negative;
      default:
        icon = Icons.receipt_long_outlined;
        color = AppColors.textSecondary;
    }
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 62),
        decoration: BoxDecoration(
          border: showDivider ? const Border(bottom: BorderSide(color: AppColors.gridLine)) : null,
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.gridLine)),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            entry.description ?? 'سند شماره ${pn(entry.id!)}',
                            style: AppTextStyles.rowTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (entry.source == kJournalSourceManual) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.lineStrong),
                            ),
                            child: const Text('دستی',
                                style: TextStyle(
                                    fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      accountSummary,
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(formatMoney(entry.totalDebit, withSuffix: false), style: AppTextStyles.rowAmount),
          ],
        ),
      ),
    );
  }
}
