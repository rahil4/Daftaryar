import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/client.dart';
import '../../models/project.dart';
import '../../models/project_transaction.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/stat_card.dart';
import 'project_form_screen.dart';
import 'transaction_form_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  final ProjectModel project;
  const ProjectDetailScreen({super.key, required this.project});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  final _db = DatabaseHelper.instance;
  late ProjectModel _project;
  ClientModel? _client;
  List<ProjectTransactionModel> _transactions = [];
  double _received = 0;
  double _paid = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final client = await _db.getClient(_project.clientId);
    final txs = await _db.getTransactions(projectId: _project.id);
    final received = await _db.sumProjectTransactions(_project.id!, kTxReceipt);
    final paid = await _db.sumProjectTransactions(_project.id!, kTxPayment);
    setState(() {
      _client = client;
      _transactions = txs;
      _received = received;
      _paid = paid;
      _loading = false;
    });
  }

  Future<void> _deleteProject() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف پروژه'),
        content: const Text('این پروژه و تمام تراکنش‌های آن حذف خواهد شد. ادامه می‌دهید؟'),
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

  Future<void> _deleteTransaction(int id) async {
    await _db.deleteTransaction(id);
    _load();
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
                                Text(_client?.name ?? '—'),
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
                          title: 'پرداختی',
                          value: formatMoney(_paid),
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
                        Text('تراکنش‌ها (${_transactions.length})',
                            style: Theme.of(context).textTheme.titleMedium),
                        TextButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      TransactionFormScreen(projectId: _project.id!)),
                            );
                            if (result == true) _load();
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('تراکنش جدید'),
                        ),
                      ],
                    ),
                    if (_transactions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 16),
                        child: Text('هنوز تراکنشی ثبت نشده',
                            style: TextStyle(color: AppColors.textSecondary)),
                      )
                    else
                      ..._transactions.map((t) {
                        final isReceipt = t.type == kTxReceipt;
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              isReceipt ? Icons.south_west_rounded : Icons.north_east_rounded,
                              color: isReceipt ? AppColors.positive : AppColors.negative,
                            ),
                            title: Text(formatMoney(t.amount)),
                            subtitle: Text(
                                '${t.category} · ${formatJalaliLong(t.date)}${t.description != null ? '\n${t.description}' : ''}'),
                            isThreeLine: t.description != null,
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 20),
                              onPressed: () => _deleteTransaction(t.id!),
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
