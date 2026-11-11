import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/reloadable.dart';
import '../../widgets/metric_strip.dart';
import 'ledger_screen.dart';

class AccountsScreen extends StatefulWidget {
  final bool embedded;
  const AccountsScreen({super.key, this.embedded = false});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> with Reloadable<AccountsScreen> {
  final _db = DatabaseHelper.instance;
  List<AccountModel> _accounts = [];
  Map<int, ({double debit, double credit})> _totals = {};
  double _ledgerDebit = 0;
  double _ledgerCredit = 0;
  bool _loading = true;
  // دسته‌های بسته‌شده (جمع‌شده) - پیش‌فرض همه باز.
  final Set<String> _collapsed = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  Future<void> reload() => _load();

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getAccounts();
    final totals = await _db.accountTotalsById();
    final ledger = await _db.ledgerTotals();
    if (!mounted) return;
    setState(() {
      _accounts = list;
      _totals = totals;
      _ledgerDebit = ledger['debit']!;
      _ledgerCredit = ledger['credit']!;
      _loading = false;
    });
  }

  /// حساب‌های یک دسته را به ترتیب درختی (والد بلافاصله قبل از فرزندانش) می‌چیند
  /// تا زیرحساب‌ها همیشه زیر حساب اصلی خودشان قرار بگیرند.
  List<MapEntry<AccountModel, int>> _hierarchicalList(String type) {
    final typeAccounts = _accounts.where((a) => a.type == type).toList();
    final result = <MapEntry<AccountModel, int>>[];
    final visited = <int>{}; // محافظ در برابر حلقه احتمالی در داده‌ها

    void addChildren(int? parentId, int depth) {
      final children = typeAccounts.where((a) => a.parentId == parentId).toList()
        ..sort((a, b) => (a.code ?? '').compareTo(b.code ?? ''));
      for (final child in children) {
        if (child.id == null || !visited.add(child.id!)) continue;
        result.add(MapEntry(child, depth));
        addChildren(child.id, depth + 1);
      }
    }

    addChildren(null, 0);
    return result;
  }

  /// مانده طبیعی یک حساب به‌علاوه همه زیرحساب‌هایش (رول‌آپ). با جمع بدهکار و
  /// بستانکار هر حساب از همان کوئری دسته‌ای محاسبه می‌شود، نه یک کوئری به
  /// ازای هر حساب. [guard] از حلقه احتمالی در داده‌ها محافظت می‌کند.
  double _rolledUpBalance(AccountModel account, [Set<int>? guard]) {
    final seen = guard ?? <int>{};
    if (account.id == null || !seen.add(account.id!)) return 0;
    final t = _totals[account.id!];
    var balance = t == null ? 0.0 : (isDebitNormal(account.type) ? t.debit - t.credit : t.credit - t.debit);
    for (final child in _accounts.where((a) => a.parentId == account.id && a.type == account.type)) {
      balance += _rolledUpBalance(child, seen);
    }
    return balance;
  }

  double _groupTotal(String type) {
    final roots = _accounts.where((a) => a.type == type && a.parentId == null);
    return roots.fold<double>(0, (s, a) => s + _rolledUpBalance(a));
  }

  Future<void> _openLedger(AccountModel a) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => LedgerScreen(account: a)));
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final balanced = (_ledgerDebit - _ledgerCredit).abs() < 0.5;
    final body = (_loading && _accounts.isEmpty)
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                SurfaceBox(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    children: [
                      Icon(balanced ? Icons.check_circle_outline : Icons.error_outline,
                          size: 20, color: balanced ? AppColors.positive : AppColors.negative),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(balanced ? 'دفتر متوازن است' : 'دفتر نامتوازن است',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: balanced ? AppColors.textPrimary : AppColors.negative)),
                            Text(
                              balanced
                                  ? 'جمع بدهکار و بستانکار همه اسناد برابر است'
                                  : 'اختلاف جمع بدهکار و بستانکار: ${formatMoney((_ledgerDebit - _ledgerCredit).abs(), withSuffix: false)}',
                              style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                for (final type in kAccountTypes)
                  if (_accounts.any((a) => a.type == type)) ...[
                    _buildGroup(type),
                    const SizedBox(height: 10),
                  ],
              ],
            ),
          );
    if (widget.embedded) return body;
    return Scaffold(
      appBar: AppBar(title: const Text('چارت حساب‌ها')),
      body: BlueprintGridBackground(child: body),
    );
  }

  Widget _buildGroup(String type) {
    final expanded = !_collapsed.contains(type);
    final rows = _hierarchicalList(type);
    return SurfaceBox(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Semantics(
            button: true,
            expanded: expanded,
            child: InkWell(
              onTap: () => setState(() => expanded ? _collapsed.add(type) : _collapsed.remove(type)),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                color: AppColors.surfaceAlt,
                child: Row(
                  children: [
                    Icon(expanded ? Icons.expand_less : Icons.expand_more,
                        size: 20, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(child: Text(type, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800))),
                    Text(formatMoney(_groupTotal(type), withSuffix: false),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.brassLight)),
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            for (final entry in rows)
              _AccountRow(
                account: entry.key,
                depth: entry.value,
                balance: _rolledUpBalance(entry.key),
                onTap: () => _openLedger(entry.key),
              ),
        ],
      ),
    );
  }
}

/// ردیف یک حساب: کد، نام، مانده. زیرحساب‌ها با خط عمودی و تورفتگی از حساب
/// اصلی (بالای سرشان) جدا می‌شوند.
class _AccountRow extends StatelessWidget {
  final AccountModel account;
  final int depth; // ۰ یعنی حساب اصلی همان دسته، بیشتر یعنی زیرحساب
  final double balance;
  final VoidCallback onTap;

  const _AccountRow({required this.account, required this.depth, required this.balance, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSub = depth > 0;
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(minHeight: isSub ? 44 : 48),
        padding: EdgeInsetsDirectional.only(start: 14.0 + 12.0 * (depth > 0 ? depth - 1 : 0), end: 14),
        decoration: BoxDecoration(
          border: isSub ? null : const Border(top: BorderSide(color: AppColors.gridLine)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              child: isSub
                  ? Container(
                      height: 30,
                      margin: const EdgeInsetsDirectional.only(end: 12),
                      decoration: const BoxDecoration(
                          border: Border(left: BorderSide(color: AppColors.lineStrong))),
                    )
                  : Text(account.code == null ? '' : pn(account.code!),
                      style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                account.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: isSub ? 12.5 : 13,
                  color: isSub ? const Color(0xFFC7CDD6) : AppColors.textPrimary,
                  fontWeight: isSub ? FontWeight.w400 : FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(formatMoney(balance, withSuffix: false),
                style: TextStyle(fontSize: isSub ? 12.5 : 13, color: isSub ? const Color(0xFFC7CDD6) : null)),
          ],
        ),
      ),
    );
  }
}
