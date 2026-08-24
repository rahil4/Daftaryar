import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/client.dart';
import '../../utils/formatters.dart';

class ClientFormScreen extends StatefulWidget {
  final ClientModel? existing;
  const ClientFormScreen({super.key, this.existing});

  @override
  State<ClientFormScreen> createState() => _ClientFormScreenState();
}

class _ClientFormScreenState extends State<ClientFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _phone = TextEditingController(text: widget.existing?.phone ?? '');
  late final _nationalId = TextEditingController(text: widget.existing?.nationalId ?? '');
  late final _address = TextEditingController(text: widget.existing?.address ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late String _relationType = widget.existing?.relationType ?? kRelationEmployer;

  bool _saving = false;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final model = ClientModel(
      id: widget.existing?.id,
      name: _name.text.trim(),
      phone: _phone.text.trim().isEmpty ? null : _phone.text.trim(),
      nationalId: _nationalId.text.trim().isEmpty ? null : _nationalId.text.trim(),
      address: _address.text.trim().isEmpty ? null : _address.text.trim(),
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      relationType: _relationType,
      createdAt: widget.existing?.createdAt ?? todayJalaliString(),
    );
    if (widget.existing == null) {
      await _db.insertClient(model);
    } else {
      await _db.updateClient(model);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'ویرایش شخص' : 'شخص جدید')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'نام و نام خانوادگی *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'نام الزامی است' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _relationType,
              decoration: const InputDecoration(labelText: 'نوع رابطه'),
              items: kRelationTypes
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _relationType = v!),
            ),
            const SizedBox(height: 12),
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
