import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_title.dart';
import 'account_form_screen.dart';
import 'ledger_screen.dart';

class AccountsScreen extends StatefulWidget {
  final bool embedded;
  const AccountsScreen({super.key, this.embedded = false});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  final _db = DatabaseHelper.instance;
  List<AccountModel> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getAccounts();
    setState(() {
      _accounts = list;
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

  Future<void> _delete(AccountModel a) async {
    try {
      await _db.deleteAccount(a.id!);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    }
  }

  void _openMenu(AccountModel a) {
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
              title: const Text('مشاهده دفتر حساب'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => LedgerScreen(account: a)));
              },
            ),
            ListTile(
              title: const Text('ویرایش'),
              onTap: () async {
                Navigator.pop(ctx);
                final result = await Navigator.push(
                    context, MaterialPageRoute(builder: (_) => AccountFormScreen(existing: a)));
                if (result == true) _load();
              },
            ),
            if (!a.isSystem)
              ListTile(
                title: const Text('حذف', style: TextStyle(color: AppColors.negative)),
                onTap: () {
                  Navigator.pop(ctx);
                  _delete(a);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final listView = _loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                for (final type in kAccountTypes)
                  if (_accounts.any((a) => a.type == type)) ...[
                    SectionTitle(type),
                    const Divider(color: AppColors.gridLine, height: 1),
                    for (final entry in _hierarchicalList(type))
                      _AccountRow(
                        account: entry.key,
                        depth: entry.value,
                        onTap: () => _openMenu(entry.key),
                      ),
                    const SizedBox(height: 22),
                  ],
              ],
            ),
          );

    final fab = FloatingActionButton(
      heroTag: 'accounts_fab',
      onPressed: () async {
        final result =
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const AccountFormScreen()));
        if (result == true) _load();
      },
      child: const Icon(Icons.add),
    );

    if (widget.embedded) {
      return Stack(
        children: [
          listView,
          Positioned(bottom: 16, left: 16, child: fab),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('چارت حساب‌ها')),
      body: BlueprintGridBackground(child: listView),
      floatingActionButton: fab,
    );
  }
}

/// ردیف یک حساب — با تورفتگی و ظاهر ریزتر برای زیرحساب‌ها،
/// تا از دسته اصلی (بالای سر) به‌وضوح قابل تشخیص باشد
class _AccountRow extends StatelessWidget {
  final AccountModel account;
  final int depth; // ۰ یعنی حساب اصلی همان دسته، بیشتر یعنی زیرحساب
  final VoidCallback onTap;

  const _AccountRow({required this.account, required this.depth, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isSub = depth > 0;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.only(
          right: 16.0 * depth,
          top: isSub ? 9 : 12,
          bottom: isSub ? 9 : 12,
        ),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.gridLine)),
        ),
        child: Row(
          children: [
            if (isSub) ...[
              const Text('└ ', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            ],
            Expanded(
              child: Text(
                account.name,
                style: TextStyle(
                  fontSize: isSub ? 13 : 14.5,
                  color: isSub ? AppColors.textSecondary : AppColors.textPrimary,
                  fontWeight: isSub ? FontWeight.normal : FontWeight.w600,
                ),
              ),
            ),
            if (account.code != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  account.code!,
                  style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                ),
              ),
            const Text('‹', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}
