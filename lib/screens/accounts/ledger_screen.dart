import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../theme/app_theme.dart';
import '../../utils/dashboard_period.dart';
import '../../utils/formatters.dart';
import '../../widgets/metric_strip.dart';
import '../../widgets/period_segmented_control.dart';
import '../journal/journal_entry_detail_screen.dart';
import 'account_form_screen.dart';

/// دفتر یک حساب: مانده فعلی، گردش بازه انتخابی با مانده تجمعی بعد از هر
/// سطر، و «مانده از قبل» (مانده پیش از شروع بازه). برای حساب‌های دارای
/// زیرحساب، سطرهای همه زیرحساب‌ها هم در گردش و مانده می‌آیند (همان رول‌آپی
/// که چارت حساب‌ها نشان می‌دهد).
class LedgerScreen extends StatefulWidget {
  final AccountModel account;
  const LedgerScreen({super.key, required this.account});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

/// یک سطر دفتر با مانده تجمعی بعد از همان سطر.
class _LedgerRow {
  final Map<String, dynamic> line;
  final double debit;
  final double credit;
  final double running;
  _LedgerRow(this.line, this.debit, this.credit, this.running);
}

class _LedgerScreenState extends State<LedgerScreen> {
  final _db = DatabaseHelper.instance;
  late AccountModel _account = widget.account;

  DashboardPeriodPreset _preset = DashboardPeriodPreset.thisYear;
  String _customFrom = defaultCustomPeriodRange().from;
  String _customTo = defaultCustomPeriodRange().to;
  Map<String, int> _fiscal = const {'month': 1, 'day': 1};

  List<Map<String, dynamic>> _allLines = [];
  Map<int, String> _projectTitles = {};
  Map<int, String> _accountNames = {};
  Set<int> _accountIds = {};
  bool _loading = true;

  bool get _debitNormal => isDebitNormal(_account.type);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final fresh = await _db.getAccount(_account.id!);
    final accounts = await _db.getAccounts(type: _account.type);
    final projects = await _db.getProjects();
    final fiscal = await _db.getFiscalYearStart();

    // خود حساب + همه نوادگانش (با محافظ حلقه).
    final ids = <int>{_account.id!};
    var frontier = <int>{_account.id!};
    while (frontier.isNotEmpty) {
      final next = accounts
          .where((a) => a.parentId != null && frontier.contains(a.parentId) && ids.add(a.id!))
          .map((a) => a.id!)
          .toSet();
      frontier = next;
    }
    final lines = <Map<String, dynamic>>[];
    for (final id in ids) {
      lines.addAll(await _db.getLedgerLines(id));
    }
    lines.sort((a, b) {
      final byDate = (a['date'] as String).compareTo(b['date'] as String);
      if (byDate != 0) return byDate;
      final byEntry = (a['entryId'] as int).compareTo(b['entryId'] as int);
      return byEntry != 0 ? byEntry : (a['lineId'] as int).compareTo(b['lineId'] as int);
    });
    if (!mounted) return;
    setState(() {
      if (fresh != null) _account = fresh;
      _fiscal = fiscal;
      _allLines = lines;
      _accountIds = ids;
      _accountNames = {for (final a in accounts) a.id!: a.name};
      _projectTitles = {for (final p in projects) p.id!: p.title};
      _loading = false;
    });
  }

  DashboardPeriodRange get _period => DashboardPeriodResolver.resolve(
        _preset,
        customFrom: _customFrom,
        customTo: _customTo,
        fiscalYearStartMonth: _fiscal['month']!,
        fiscalYearStartDay: _fiscal['day']!,
      );

  double _signed(Map<String, dynamic> l) {
    final d = (l['debit'] as num).toDouble();
    final c = (l['credit'] as num).toDouble();
    return _debitNormal ? d - c : c - d;
  }

  Future<void> _edit() async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => AccountFormScreen(existing: _account)));
    if (result == true && mounted) _load();
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف حساب'),
        content: Text('حساب «${_account.name}» حذف شود؟ حساب دارای سند یا زیرحساب قابل حذف نیست.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: AppColors.negative))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _db.deleteAccount(_account.id!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'گزینه‌ها',
            icon: const Icon(Icons.more_vert),
            onSelected: (v) => v == 'edit' ? _edit() : _delete(),
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'edit', child: Text('ویرایش حساب')),
              if (!_account.isSystem)
                const PopupMenuItem(
                    value: 'delete', child: Text('حذف حساب', style: TextStyle(color: AppColors.negative))),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: BlueprintGridBackground(
        child: _loading && _allLines.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(onRefresh: _load, child: _buildContent()),
      ),
    );
  }

  Widget _buildContent() {
    final period = _period;
    var totalDebit = 0.0, totalCredit = 0.0;
    for (final l in _allLines) {
      totalDebit += (l['debit'] as num).toDouble();
      totalCredit += (l['credit'] as num).toDouble();
    }
    final currentBalance = _debitNormal ? totalDebit - totalCredit : totalCredit - totalDebit;

    // مانده از قبل = مانده پیش از شروع بازه؛ سپس مانده تجمعی بعد از هر سطر.
    var opening = 0.0;
    final rows = <_LedgerRow>[];
    var periodDebit = 0.0, periodCredit = 0.0;
    var running = 0.0;
    for (final l in _allLines) {
      final date = l['date'] as String;
      final d = (l['debit'] as num).toDouble();
      final c = (l['credit'] as num).toDouble();
      running += _signed(l);
      if (date.compareTo(period.fromDate) < 0) {
        opening = running;
      } else if (date.compareTo(period.toDate) <= 0) {
        rows.add(_LedgerRow(l, d, c, running));
        periodDebit += d;
        periodCredit += c;
      }
    }
    final closing = rows.isEmpty ? opening : rows.last.running;
    final hasChildren = _accountIds.length > 1;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_account.name,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.35)),
              const SizedBox(height: 4),
              Text(
                [
                  _account.type,
                  if (_account.code != null) 'کد ${pn(_account.code!)}',
                  if (hasChildren) 'همراه با زیرحساب‌ها',
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        SurfaceBox(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              HeroAmount(
                label: 'مانده فعلی · ${currentBalance >= 0 ? (_debitNormal ? 'بدهکار' : 'بستانکار') : (_debitNormal ? 'بستانکار' : 'بدهکار')}',
                amount: currentBalance.abs(),
                fontSize: 32,
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              MetricStrip(framed: false, items: [
                MetricItem(label: 'جمع بدهکار از ابتدا', value: formatMoney(totalDebit, withSuffix: false), valueSize: 13),
                MetricItem(label: 'جمع بستانکار از ابتدا', value: formatMoney(totalCredit, withSuffix: false), valueSize: 13),
              ]),
            ],
          ),
        ),
        const SizedBox(height: 12),
        PeriodSegmentedControl(
          selected: _preset,
          onChanged: (p) => setState(() => _preset = p),
          customFrom: _customFrom,
          customTo: _customTo,
          onCustomRangeChanged: (from, to) => setState(() {
            _customFrom = from;
            _customTo = to;
          }),
        ),
        const SizedBox(height: 12),
        SurfaceBox(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              _columnsHeader(),
              _openingRow(period, opening),
              if (rows.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('در این بازه گردشی برای این حساب ثبت نشده',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                )
              else
                for (final r in rows) _lineRow(r),
              _totalsRow(periodDebit, periodCredit, closing),
            ],
          ),
        ),
      ],
    );
  }

  Widget _columnsHeader() {
    const style = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      color: AppColors.surfaceAlt,
      child: const Row(
        children: [
          Expanded(child: Text('بدهکار', style: style)),
          Expanded(child: Text('بستانکار', style: style)),
          Expanded(child: Text('مانده', style: style, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _openingRow(DashboardPeriodRange period, double opening) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.gridLine))),
      child: Row(
        children: [
          Expanded(
            child: Text('مانده از قبل · تا ${formatJalaliLong(period.fromDate)}',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ),
          Text(formatMoney(opening, withSuffix: false),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _lineRow(_LedgerRow r) {
    final l = r.line;
    final projectId = l['projectId'] as int?;
    final title = (l['lineDescription'] as String?) ??
        (l['entryDescription'] as String?) ??
        'سند شماره ${pn(l['entryId'])}';
    final accountId = l['accountId'];
    final sub = <String>[
      if (projectId != null && _projectTitles[projectId] != null) 'پروژه: ${_projectTitles[projectId]}',
    ];
    return InkWell(
      onTap: () async {
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => JournalEntryDetailScreen(entryId: l['entryId'] as int)));
        if (mounted) _load();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.gridLine))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(title,
                      maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.rowTitle),
                ),
                const SizedBox(width: 10),
                Text(formatJalaliLong(l['date'] as String),
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ],
            ),
            if (sub.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(sub.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(child: _amountCell(r.debit)),
                Expanded(child: _amountCell(r.credit)),
                Expanded(
                  child: Text(formatMoney(r.running, withSuffix: false),
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (accountId is int && accountId != _account.id && _accountNames[accountId] != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('زیرحساب: ${_accountNames[accountId]}',
                    style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _amountCell(double v) => Text(
        v > 0 ? formatMoney(v, withSuffix: false) : '—',
        style: TextStyle(fontSize: 12.5, color: v > 0 ? AppColors.textPrimary : AppColors.textSecondary),
      );

  Widget _totalsRow(double debit, double credit, double closing) {
    const style = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.lineStrong)),
        color: AppColors.surfaceAlt,
      ),
      child: Row(
        children: [
          Expanded(child: Text(formatMoney(debit, withSuffix: false), style: style)),
          Expanded(child: Text(formatMoney(credit, withSuffix: false), style: style)),
          Expanded(
            child: Text(formatMoney(closing, withSuffix: false), textAlign: TextAlign.end, style: style),
          ),
        ],
      ),
    );
  }
}
