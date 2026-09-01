import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/counterparty.dart';
import '../../utils/formatters.dart';

class CounterpartyFormScreen extends StatefulWidget {
  final CounterpartyModel? existing;
  const CounterpartyFormScreen({super.key, this.existing});

  @override
  State<CounterpartyFormScreen> createState() => _CounterpartyFormScreenState();
}

class _CounterpartyFormScreenState extends State<CounterpartyFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _nationalId = TextEditingController(text: widget.existing?.nationalId ?? '');
  late final _address = TextEditingController(text: widget.existing?.address ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late final Set<String> _selectedRoles = {...(widget.existing?.roles ?? [kRoleCustomer])};
  late bool _isActive = widget.existing?.isActive ?? true;

  List<String> _availableRoles = kDefaultCounterpartyRoles;
  bool _loadingRoles = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    final roles = await _db.getAllRoles();
    setState(() {
      _availableRoles = roles.map((r) => r.name).toList();
      _loadingRoles = false;
    });
  }

  Future<void> _addCustomRole() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نقش جدید'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'نام نقش'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('انصراف')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('افزودن'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty && !_availableRoles.contains(result)) {
      setState(() {
        _availableRoles = [..._availableRoles, result];
        _selectedRoles.add(result);
      });
    }
  }

  Future<bool> _confirmIfDuplicate() async {
    final duplicate = await _db.findPossibleDuplicateCounterparty(
      name: _name.text,
      nationalId: _nationalId.text.trim().isEmpty ? null : _nationalId.text.trim(),
      excludeId: widget.existing?.id,
    );
    if (duplicate == null) return true;
    if (!mounted) return false;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('احتمال تکراری بودن'),
        content: Text(
            'طرف حسابی با نام یا کد ملی مشابه از قبل ثبت شده است: «${duplicate.name}».\nآیا مطمئنید می‌خواهید یک رکورد جدید بسازید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('بله، ادامه بده')),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedRoles.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('حداقل یک نقش را انتخاب کنید')));
      return;
    }

    if (widget.existing == null) {
      final canProceed = await _confirmIfDuplicate();
      if (!canProceed) return;
    }

    setState(() => _saving = true);
    final now = todayJalaliString();
    final model = CounterpartyModel(
      id: widget.existing?.id,
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      nationalId: _nationalId.text.trim().isEmpty ? null : _nationalId.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      isActive: _isActive,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
      roles: _selectedRoles.toList(),
    );
    if (widget.existing == null) {
      await _db.insertCounterparty(model);
    } else {
      await _db.updateCounterparty(model);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'ویرایش طرف حساب' : 'طرف حساب جدید')),
      body: _loadingRoles
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _name,
                    decoration: const InputDecoration(labelText: 'نام (شخص یا شرکت) *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'نام الزامی است' : null,
                  ),
                  const SizedBox(height: 16),
                  Text('نقش (می‌توانید بیش از یکی انتخاب کنید) *',
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ..._availableRoles.map((role) => FilterChip(
                            label: Text(role),
                            selected: _selectedRoles.contains(role),
                            onSelected: (sel) => setState(() {
                              if (sel) {
                                _selectedRoles.add(role);
                              } else {
                                _selectedRoles.remove(role);
                              }
                            }),
                          )),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 16),
                        label: const Text('نقش جدید'),
                        onPressed: _addCustomRole,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _phone,
                    decoration: const InputDecoration(labelText: 'شماره تماس'),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _nationalId,
                    decoration: const InputDecoration(labelText: 'کد ملی / شناسه'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _address,
                    decoration: const InputDecoration(labelText: 'آدرس'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notes,
                    decoration: const InputDecoration(labelText: 'یادداشت'),
                    maxLines: 3,
                  ),
                  if (isEdit) ...[
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('فعال'),
                      subtitle: const Text('طرف حساب غیرفعال در انتخاب‌های جدید پیشنهاد نمی‌شود'),
                      value: _isActive,
                      onChanged: (v) => setState(() => _isActive = v),
                    ),
                  ],
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('ذخیره'),
                  ),
                ],
              ),
            ),
    );
  }
}
