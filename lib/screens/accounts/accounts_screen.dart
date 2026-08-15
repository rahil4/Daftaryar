import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../theme/app_theme.dart';
import 'account_form_screen.dart';
import 'ledger_screen.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

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

  int _depthOf(AccountModel a) {
    int depth = 0;
    int? parentId = a.parentId;
    while (parentId != null) {
      final matches = _accounts.where((x) => x.id == parentId);
      if (matches.isEmpty) break;
      final parent = matches.first;
      depth++;
      parentId = parent.parentId;
    }
    return depth;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('چارت حساب‌ها')),
      body: BlueprintGridBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final type in kAccountTypes) ...[
                    if (_accounts.any((a) => a.type == type)) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
                        child: Text(type,
                            style: const TextStyle(
                                color: AppColors.brass, fontWeight: FontWeight.bold)),
                      ),
                      ..._accounts.where((a) => a.type == type).map((a) {
                        final depth = _depthOf(a);
                        return Card(
                          child: ListTile(
                            contentPadding: EdgeInsets.only(right: 16 + depth * 20, left: 8),
                            leading: Icon(
                              a.isSystem ? Icons.lock_outline : Icons.account_tree_outlined,
                              color: AppColors.brass,
                              size: 20,
                            ),
                            title: Text(a.name),
                            subtitle: a.code != null ? Text('کد: ${a.code}') : null,
                            trailing: PopupMenuButton<String>(
                              onSelected: (v) async {
                                if (v == 'ledger') {
                                  Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => LedgerScreen(account: a)));
                                } else if (v == 'edit') {
                                  final result = await Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => AccountFormScreen(existing: a)));
                                  if (result == true) _load();
                                } else if (v == 'delete') {
                                  _delete(a);
                                }
                              },
                              itemBuilder: (ctx) => [
                                const PopupMenuItem(value: 'ledger', child: Text('مشاهده دفتر حساب')),
                                const PopupMenuItem(value: 'edit', child: Text('ویرایش')),
                                const PopupMenuItem(value: 'delete', child: Text('حذف')),
                              ],
                            ),
                            onTap: () => Navigator.push(
                                context, MaterialPageRoute(builder: (_) => LedgerScreen(account: a))),
                          ),
                        );
                      }),
                    ],
                  ],
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AccountFormScreen()));
          if (result == true) _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
