import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/office_expense.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'expense_form_screen.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  final _db = DatabaseHelper.instance;
  List<OfficeExpenseModel> _expenses = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getExpenses();
    setState(() {
      _expenses = list;
      _loading = false;
    });
  }

  Future<void> _delete(int id) async {
    await _db.deleteExpense(id);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final total = _expenses.fold<double>(0, (sum, e) => sum + e.amount);
    return Scaffold(
      appBar: AppBar(title: const Text('هزینه‌های عمومی دفتر')),
      body: BlueprintGridBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      color: AppColors.surfaceAlt,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('جمع کل هزینه‌ها'),
                            Text(formatMoney(total),
                                style: const TextStyle(
                                    color: AppColors.negative, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_expenses.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 30),
                        child: Center(
                            child: Text('هزینه‌ای ثبت نشده است',
                                style: TextStyle(color: AppColors.textSecondary))),
                      )
                    else
                      ..._expenses.map((e) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.receipt_long_outlined,
                                  color: AppColors.brass),
                              title: Text(e.title),
                              subtitle: Text('${e.category} · ${formatJalaliLong(e.date)}'),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(formatMoney(e.amount, withSuffix: false),
                                      style: const TextStyle(fontWeight: FontWeight.bold)),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size: 20),
                                    onPressed: () => _delete(e.id!),
                                  ),
                                ],
                              ),
                            ),
                          )),
                  ],
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ExpenseFormScreen()));
          if (result == true) _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
