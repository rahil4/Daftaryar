import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/project_transaction.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';

class TransactionFormScreen extends StatefulWidget {
  final int projectId;
  const TransactionFormScreen({super.key, required this.projectId});

  @override
  State<TransactionFormScreen> createState() => _TransactionFormScreenState();
}

class _TransactionFormScreenState extends State<TransactionFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _type = kTxReceipt;
  String _category = kTxCategories.first;
  String _date = todayJalaliString();
  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final tx = ProjectTransactionModel(
      projectId: widget.projectId,
      type: _type,
      amount: double.tryParse(_amount.text.trim()) ?? 0,
      date: _date,
      category: _category,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
    );
    await _db.insertTransaction(tx);
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('تراکنش جدید')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: kTxReceipt, label: Text('دریافت')),
                ButtonSegment(value: kTxPayment, label: Text('پرداخت')),
              ],
              selected: {_type},
              onSelectionChanged: (s) => setState(() => _type = s.first),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _amount,
              decoration: const InputDecoration(labelText: 'مبلغ (تومان) *'),
              keyboardType: TextInputType.number,
              validator: (v) =>
                  (v == null || double.tryParse(v.trim()) == null) ? 'مبلغ معتبر وارد کنید' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(labelText: 'دسته‌بندی'),
              items:
                  kTxCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setState(() => _category = v!),
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
                  : const Text('ثبت تراکنش'),
            ),
          ],
        ),
      ),
    );
  }
}
