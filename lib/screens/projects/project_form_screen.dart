import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/counterparty.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/persian_amount_field.dart';
import '../counterparties/counterparty_form_screen.dart';

class ProjectFormScreen extends StatefulWidget {
  final ProjectModel? existing;
  final CounterpartyModel? presetCounterparty;
  const ProjectFormScreen({super.key, this.existing, this.presetCounterparty});

  @override
  State<ProjectFormScreen> createState() => _ProjectFormScreenState();
}

class _ProjectFormScreenState extends State<ProjectFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _amount = TextEditingController(
      text: widget.existing != null
          ? formatMoney(widget.existing!.agreedAmount, withSuffix: false)
          : '');
  late final _description = TextEditingController(text: widget.existing?.description ?? '');

  String _startDate = '';
  String _projectType = kProjectTypes.first;
  String _status = kProjectStatuses.first;

  List<CounterpartyModel> _counterparties = [];
  int? _selectedCounterpartyId;
  bool _hasFinancialHistory = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _startDate = widget.existing?.startDate ?? todayJalaliString();
    _projectType = widget.existing?.projectType ?? kProjectTypes.first;
    _status = widget.existing?.status ?? kProjectStatuses.first;
    _selectedCounterpartyId = widget.existing?.counterpartyId ?? widget.presetCounterparty?.id;
    _loadCounterparties();
  }

  Future<void> _loadCounterparties() async {
    final list = await _db.getCounterparties();
    bool hasHistory = false;
    if (widget.existing?.id != null) {
      hasHistory = widget.existing!.isFinalized ||
          await _db.projectHasFinancialHistory(widget.existing!.id!);
    }
    setState(() {
      _counterparties = list;
      _hasFinancialHistory = hasHistory;
      _loading = false;
    });
  }

  Future<void> _addNewCounterpartyInline() async {
    final result = await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const CounterpartyFormScreen()));
    if (result == true) {
      await _loadCounterparties();
      if (_counterparties.isNotEmpty) {
        setState(() => _selectedCounterpartyId = _counterparties.first.id);
      }
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCounterpartyId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('لطفاً کارفرما را انتخاب کنید')));
      return;
    }
    setState(() => _saving = true);
    final model = ProjectModel(
      id: widget.existing?.id,
      title: _title.text.trim(),
      counterpartyId: _selectedCounterpartyId!,
      projectType: _projectType,
      status: _status,
      startDate: _startDate,
      agreedAmount: parsePersianAmount(_amount.text) ?? 0,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      createdAt: widget.existing?.createdAt ?? todayJalaliString(),
      finalAmount: widget.existing?.finalAmount,
      finalizedDate: widget.existing?.finalizedDate,
      finalizedNote: widget.existing?.finalizedNote,
    );
    try {
      if (widget.existing == null) {
        await _db.insertProject(model);
      } else {
        await _db.updateProject(model);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        setState(() => _saving = false);
      }
    }
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
                          value: _selectedCounterpartyId,
                          decoration: const InputDecoration(labelText: 'کارفرما *'),
                          items: _counterparties
                              .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                              .toList(),
                          onChanged: _hasFinancialHistory
                              ? null
                              : (v) => setState(() => _selectedCounterpartyId = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _hasFinancialHistory ? null : _addNewCounterpartyInline,
                        icon: const Icon(Icons.person_add_alt_1_outlined),
                        style: IconButton.styleFrom(backgroundColor: AppColors.surfaceAlt),
                      ),
                    ],
                  ),
                  if (_hasFinancialHistory)
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'این پروژه سابقه مالی دارد (سند حسابداری یا تغییر مبلغ ثبت‌شده)؛ کارفرمای آن قابل تغییر نیست.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
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
                  // Finalized/Cancelled عمداً از گزینه‌های این دراپ‌داون حذف
                  // شده‌اند: این دو وضعیت فقط باید از طریق Workflow اختصاصی
                  // خودشان (finalizeProject / لغو پروژه از صفحه جزئیات) ایجاد
                  // شوند، نه با یک انتخاب ساده در فرم عمومی ویرایش پروژه.
                  if (_status == kProjectStatusFinalized || _status == kProjectStatusCancelled)
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'وضعیت'),
                      child: Text(_status,
                          style: const TextStyle(color: AppColors.textSecondary)),
                    )
                  else
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
                  PersianAmountField(
                    controller: _amount,
                    label: 'مبلغ کل قرارداد (تومان)',
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
