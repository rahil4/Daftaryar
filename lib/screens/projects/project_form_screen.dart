import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/client.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../clients/client_form_screen.dart';

class ProjectFormScreen extends StatefulWidget {
  final ProjectModel? existing;
  final ClientModel? presetClient;
  const ProjectFormScreen({super.key, this.existing, this.presetClient});

  @override
  State<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<ProjectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _amount =
      TextEditingController(text: widget.existing?.agreedAmount.toStringAsFixed(0) ?? '');
  late final _description = TextEditingController(text: widget.existing?.description ?? '');

  String _startDate = '';
  String _projectType = kProjectTypes.first;
  String _status = kProjectStatuses.first;

  List<ClientModel> _clients = [];
  int? _selectedClientId;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startDate = widget.existing?.startDate ?? todayJalaliString();
    _projectType = widget.existing?.projectType ?? kProjectTypes.first;
    _status = widget.existing?.status ?? kProjectStatuses.first;
    _selectedClientId = widget.existing?.clientId ?? widget.presetClient?.id;
    _loadClients();
  }

  Future<void> _loadClients() async {
    final list = await _db.getClients();
    setState(() {
      _clients = list;
      _loading = false;
    });
  }

  Future<void> _addNewClientInline() async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const ClientFormScreen()));
    if (result == true) {
      await _loadClients();
      if (_clients.isNotEmpty) {
        setState(() => _selectedClientId = _clients.first.id);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedClientId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('لطفاً کارفرما را انتخاب کنید')));
      return;
    }
    setState(() => _saving = true);
    final model = ProjectModel(
      id: widget.existing?.id,
      title: _title.text.trim(),
      clientId: _selectedClientId!,
      projectType: _projectType,
      status: _status,
      startDate: _startDate,
      agreedAmount: double.tryParse(_amount.text.trim()) ?? 0,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      createdAt: widget.existing?.createdAt ?? todayJalaliString(),
    );
    if (widget.existing == null) {
      await _db.insertProject(model);
    } else {
      await _db.updateProject(model);
    }
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'ویرایش پروژه' : 'پروژه جدید')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(labelText: 'عنوان پروژه *'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'الزامی است' : null,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          value: _selectedClientId,
                          decoration: const InputDecoration(labelText: 'کارفرما *'),
                          items: _clients
                              .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedClientId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _addNewClientInline,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        style: IconButton.styleFrom(backgroundColor: AppColors.surfaceAlt),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _projectType,
                    decoration: const InputDecoration(labelText: 'نوع پروژه'),
                    items: kProjectTypes
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _projectType = v!),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _status,
                    decoration: const InputDecoration(labelText: 'وضعیت'),
                    items: kProjectStatuses
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (v) => setState(() => _status = v!),
                  ),
                  const SizedBox(height: 12),
                  JalaliDateField(
                    label: 'تاریخ شروع',
                    value: _startDate,
                    onChanged: (v) => setState(() => _startDate = v),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _amount,
                    decoration: const InputDecoration(labelText: 'مبلغ کل قرارداد (تومان)'),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _description,
                    decoration: const InputDecoration(labelText: 'توضیحات'),
                    maxLines: 3,
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
