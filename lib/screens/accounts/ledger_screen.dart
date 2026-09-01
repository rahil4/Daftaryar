import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

class LedgerScreen extends StatefulWidget {
  final AccountModel account;
  const LedgerScreen({super.key, required this.account});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  final _db = DatabaseHelper.instance;
  List<Map<String, dynamic>> _lines = [];
  Map<int, String> _projectTitles = {};
  double _debit = 0;
  double _credit = 0;
  double _balance = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final lines = await _db.getLedgerLines(widget.account.id!);
    final bal = await _db.accountBalance(widget.account.id!);
    final projects = await _db.getProjects();
    setState(() {
      _lines = lines;
      _debit = bal['debit']!;
      _credit = bal['credit']!;
      _balance = bal['balance']!;
      _projectTitles = {for (final p in projects) p.id!: p.title};
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final debitNormal = isDebitNormal(widget.account.type);
    return Scaffold(
      appBar: AppBar(title: Text('دفتر: ${widget.account.name}')),
      body: BlueprintGridBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      color: AppColors.surfaceAlt,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('جمع بدهکار'),
                                Text(formatMoney(_debit)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('جمع بستانکار'),
                                Text(formatMoney(_credit)),
                              ],
                            ),
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('مانده (${debitNormal ? "بدهکار" : "بستانکار"} طبیعی)'),
                                Text(
                                  formatMoney(_balance.abs()),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: _balance >= 0 ? AppColors.positive : AppColors.negative,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_lines.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 30),
                        child: Center(
                            child: Text('تاکنون سندی برای این حساب ثبت نشده',
                                style: TextStyle(color: AppColors.textSecondary))),
                      )
                    else
                      ..._lines.map((l) {
                        final debit = (l['debit'] as num).toDouble();
                        final credit = (l['credit'] as num).toDouble();
                        final projectId = l['projectId'] as int?;
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              debit > 0 ? Icons.arrow_downward : Icons.arrow_upward,
                              color: debit > 0 ? AppColors.positive : AppColors.negative,
                            ),
                            title: Text(
                                (l['lineDescription'] as String?) ??
                                    (l['entryDescription'] as String?) ??
                                    'سند شماره ${l['entryId']}'),
                            subtitle: Text(
                              '${formatJalaliLong(l['date'] as String)}'
                              '${projectId != null && _projectTitles[projectId] != null ? ' · پروژه: ${_projectTitles[projectId]}' : ''}',
                            ),
                            trailing: Text(
                              debit > 0 ? formatMoney(debit) : formatMoney(credit),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: debit > 0 ? AppColors.positive : AppColors.negative,
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
      ),
    );
  }
}
