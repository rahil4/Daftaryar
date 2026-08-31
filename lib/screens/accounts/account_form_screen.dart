import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../utils/formatters.dart';

class AccountFormScreen extends StatefulWidget {
  final AccountModel? existing;
  const AccountFormScreen({super.key, this.existing});

  @override
  State<AccountFormScreen> createState() => _AccountFormScreenState();
}

class _AccountFormScreenState extends State<AccountFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _code = TextEditingController(text: widget.existing?.code ?? '');
  late String _type = widget.existing?.type ?? kAccountTypes.first;
  int? _parentId;
  List<AccountModel> _allAccounts = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _parentId = widget.existing?.parentId;
    _load();
  }

  Future<void> _load() async {
    final list = await _db.getAccounts();
    setState(() {
      _allAccounts = list;
      _loading = false;
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final model = AccountModel(
      id: widget.existing?.id,
      code: _code.text.trim().isEmpty ? null : _code.text.trim(),
      name: _name.text.trim(),
      type: _type,
      parentId: _parentId,
      isSystem: widget.existing?.isSystem ?? false,
      systemKey: widget.existing?.systemKey,
      createdAt: widget.existing?.createdAt ?? todayJalaliString(),
    );
    if (widget.existing == null) {
      await _db.insertAccount(model);
    } else {
      await _db.updateAccount(model);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final isSystem = widget.existing?.isSystem ?? false;

    // تمام نوادگان حساب فعلی را هم از گزینه‌های والد حذف می‌کنیم؛ در غیر این
    // صورت می‌شد یک زیرحساب را به‌عنوان والدِ همان حساب انتخاب کرد و یک حلقه
    // بی‌پایان در سلسله‌مراتب ساخت که هنگام نمایش چارت حساب‌ها کرش می‌کرد.
    final descendantIds = <int>{};
    if (widget.existing?.id != null) {
      void collectDescendants(int parentId) {
        for (final a in _allAccounts) {
          if (a.parentId == parentId && a.id != null && descendantIds.add(a.id!)) {
            collectDescendants(a.id!);
          }
        }
      }

      collectDescendants(widget.existing!.id!);
    }

    final possibleParents = _allAccounts
        .where((a) =>
            a.type == _type &&
            a.id != widget.existing?.id &&
            !descendantIds.contains(a.id) &&
            (!a.isSystem || a.allowChildren))
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'ویرایش حساب' : 'حساب جدید')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (isSystem)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('این یک حساب پیش‌فرض سیستم است.',
                          style: TextStyle(fontSize: 12)),
                    ),
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'نام حساب *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'الزامی است' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _code,
                    decoration: const InputDecoration(labelText: 'کد حساب (اختیاری)'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _type,
                    decoration: const InputDecoration(labelText: 'نوع حساب'),
                    items: kAccountTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: isSystem
                        ? null
                        : (v) => setState(() {
                              _type = v!;
                              _parentId = null;
                            }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    value: _parentId,
                    decoration: const InputDecoration(labelText: 'حساب والد (اختیاری)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('بدون والد (حساب کل)')),
                      ...possibleParents
                          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))),
                    ],
                    onChanged: isSystem ? null : (v) => setState(() => _parentId = v),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('ذخیره'),
                  ),
                ],
              ),
            ),
    );
  }
}
