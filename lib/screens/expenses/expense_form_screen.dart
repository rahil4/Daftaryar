import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/office_expense.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key});

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  final _title = TextEditingController();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _category = kExpenseCategories.first;
  String _date = todayJalaliString();
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final expense = OfficeExpenseModel(
      title: _title.text.trim(),
      category: _category,
      amount: double.tryParse(_amount.text.trim()) ?? 0,
      date: _date,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
    );
    await _db.insertExpense(expense);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('هزینه جدید')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'عنوان هزینه *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'الزامی است' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'دسته‌بندی'),
              items: kExpenseCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _amount,
              decoration: const InputDecoration(labelText: 'مبلغ (تومان) *'),
              keyboardType: TextInputType.number,
              validator: (v) =>
                  (v == null || double.tryParse(v.trim()) == null) ? 'مبلغ معتبر وارد کنید' : null,
            ),
            const SizedBox(height: 12),
            JalaliDateField(
              label: 'تاریخ',
              value: _date,
              onChanged: (v) => setState(() => _date = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              decoration: const InputDecoration(labelText: 'توضیحات'),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('ثبت هزینه'),
            ),
          ],
        ),
      ),
    );
  }
}
