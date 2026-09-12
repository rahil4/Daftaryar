import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/counterparty.dart';
import '../../models/project.dart';
import '../../models/journal_entry.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/persian_amount_field.dart';
import '../../widgets/project_receipt_context_box.dart';

/// ثبت دریافت/درآمد.
///
/// نکته مهم (Financial Data Integrity - مورد ۱۰): وقتی یک پروژه انتخاب شده
/// باشد، این فرم دیگر خودش تصمیم نمی‌گیرد کدام حساب بستانکار شود و کل
/// عملیات به receiveProjectPayment() واگذار می‌شود؛ آن تابع به‌صورت هوشمند
/// پیش از Finalization به «پیش‌دریافت مشتری» و پس از آن به تسویه «حساب‌های
/// دریافتنی» می‌رود - هرگز مستقیم Revenue شناسایی نمی‌کند برای پروژه‌ای که
/// هنوز Finalize نشده. بدون پروژه، این فرم فقط یک دریافت نقدی عمومی
/// (بدهکار صندوق/بانک، بستانکار یک حساب درآمد) ثبت می‌کند - نه چیز دیگری.
///
/// «ایجاد طلب» و «دریافت طلب» (بدون پروژه) عمداً از این فرم حذف شدند:
/// طلب یک اقلام حسابداری بدون رویداد نقدی همزمان است و باید با سند دستی
/// آزاد (JournalFormScreen) ثبت شود، نه با فرمی که برای «دریافت واقعی وجه»
/// طراحی شده - دقیقاً همین ترکیب باعث یک باگ واقعی گزارش‌شده توسط کاربر شد
/// (انتخاب پروژه، «ایجاد طلب» را بی‌سروصدا نادیده می‌گرفت و یک دریافت نقدی
/// واقعی برای پولی که دریافت نشده بود ثبت می‌کرد).
class QuickReceiptScreen extends StatefulWidget {
  final int? presetProjectId;
  final int? presetCounterpartyId;
  const QuickReceiptScreen({super.key, this.presetProjectId, this.presetCounterpartyId});

  @override
  State<QuickReceiptScreen> createState() => _QuickReceiptScreenState();
}

class _QuickReceiptScreenState extends State<QuickReceiptScreen> {
  final _formKey = GlobalKey<FormState>();
  final _db = DatabaseHelper.instance;

  final _amount = TextEditingController();
  final _description = TextEditingController();
  String _date = todayJalaliString();

  List<AccountModel> _cashAccounts = [];
  List<AccountModel> _incomeAccounts = [];
  List<ProjectModel> _projects = [];
  List<CounterpartyModel> _counterparties = [];
  int? _cashAccountId;
  int? _incomeAccountId;
  int? _projectId;
  int? _counterpartyId;
  Map<String, dynamic>? _projectSummary;
  ProjectModel? _selectedProject; // برای تشخیص isFinalized پروژه انتخاب‌شده
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _projectId = widget.presetProjectId;
    _counterpartyId = widget.presetCounterpartyId;
    _load();
  }

  Future<void> _load() async {
    final asset = await _db.getCashAccounts();
    final incomeAll = await _db.getPostableAccounts(type: kAccountIncome);
    // حساب «حساب‌های دریافتنی» نباید در لیست «بابت درآمد» انتخاب شود
    final arAccount = await _db.getReceivableAccount();
    final income = incomeAll.where((a) => a.id != arAccount?.id).toList();
    final projects = await _db.getProjects();
    final counterparties = await _db.getCounterparties();

    int? initialCounterpartyId = _counterpartyId;
    ProjectModel? selectedProject;
    if (_projectId != null) {
      final matches = projects.where((p) => p.id == _projectId);
      if (matches.isNotEmpty) {
        selectedProject = matches.first;
        initialCounterpartyId ??= selectedProject.counterpartyId;
      }
    }

    setState(() {
      _cashAccounts = asset;
      _incomeAccounts = income;
      _projects = projects;
      _counterparties = counterparties;
      _cashAccountId = asset.isNotEmpty ? asset.first.id : null;
      _incomeAccountId = income.isNotEmpty ? income.first.id : null;
      _counterpartyId = initialCounterpartyId;
      _selectedProject = selectedProject;
      _loading = false;
    });
    await _refreshProjectSummary();
  }

  Future<void> _refreshProjectSummary() async {
    if (_projectId == null) {
      if (mounted) setState(() => _projectSummary = null);
      return;
    }
    final summary = await _db.projectFinancialSummary(_projectId!);
    if (mounted) setState(() => _projectSummary = summary);
  }

  void _onProjectChanged(int? projectId) {
    setState(() {
      _projectId = projectId;
      if (projectId != null) {
        final matches = _projects.where((p) => p.id == projectId);
        if (matches.isNotEmpty) {
          _selectedProject = matches.first;
          _counterpartyId = matches.first.counterpartyId;
        }
      } else {
        _selectedProject = null;
      }
    });
    _refreshProjectSummary();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    final amount = (parsePersianAmount(_amount.text) ?? 0).round();

    try {
      if (_projectId != null) {
        // مسیر پروژه‌محور: کل منطق تشخیص پیش‌دریافت/تسویه طلب به
        // receiveProjectPayment سپرده می‌شود.
        if (_cashAccountId == null) {
          setState(() => _saving = false);
          return;
        }
        await _db.receiveProjectPayment(
          projectId: _projectId!,
          cashAccountId: _cashAccountId!,
          amount: amount.toDouble(),
          date: _date,
          description: _description.text.trim(),
        );
        if (mounted) Navigator.pop(context, true);
        return;
      }

      if (_cashAccountId == null || _incomeAccountId == null) {
        setState(() => _saving = false);
        return;
      }
      final entry = JournalEntryModel(
        date: _date,
        description: _description.text.trim().isEmpty ? 'دریافت وجه' : _description.text.trim(),
        createdAt: todayJalaliString(),
        lines: [
          JournalLineModel(accountId: _cashAccountId!, debit: amount, counterpartyId: _counterpartyId),
          JournalLineModel(
              accountId: _incomeAccountId!, credit: amount, counterpartyId: _counterpartyId),
        ],
      );
      await _db.createManualJournal(entry);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isProjectLinked = _projectId != null;

    return Scaffold(
      appBar: AppBar(title: const Text('ثبت دریافت / درآمد')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (isProjectLinked)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.brass.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        (_selectedProject?.isFinalized ?? false)
                            ? 'این پروژه نهایی شده؛ دریافت به‌عنوان تسویه طلب ثبت می‌شود.'
                            : 'این پروژه هنوز نهایی نشده؛ دریافت به‌عنوان پیش‌دریافت ثبت می‌شود (نه درآمد).',
                        style: const TextStyle(fontSize: 12, color: AppColors.brass),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.textSecondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'این فرم فقط برای دریافت نقدی واقعی است. برای ثبت طلب (بدون دریافت وجه)، از '
                        '«سند» در داشبورد استفاده کنید.',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                    ),
                  const SizedBox(height: 16),
                  PersianAmountField(
                    controller: _amount,
                    label: 'مبلغ (تومان) *',
                    onChanged: (_) => setState(() {}),
                    validator: (v) => (v == null || parsePersianAmount(v) == null)
                        ? 'مبلغ معتبر وارد کنید'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _cashAccountId,
                    decoration: const InputDecoration(labelText: 'واریز به حساب'),
                    items: _cashAccounts
                        .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                        .toList(),
                    onChanged: (v) => setState(() => _cashAccountId = v),
                  ),
                  if (!isProjectLinked) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _incomeAccountId,
                      decoration: const InputDecoration(labelText: 'بابت درآمد'),
                      items: _incomeAccounts
                          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _incomeAccountId = v),
                    ),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: _counterpartyId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'طرف حساب (اختیاری)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      ..._counterparties.map((c) => DropdownMenuItem(
                          value: c.id, child: Text('${c.name} (${c.roles.join('، ')})'))),
                    ],
                    // وقتی دریافت به پروژه وصل است، طرف حساب از خودِ پروژه
                    // مشخص می‌شود و قابل تغییر دستی نیست.
                    onChanged: isProjectLinked ? null : (v) => setState(() => _counterpartyId = v),
                  ),
                  if (isProjectLinked && _projectSummary != null && _selectedProject != null) ...[
                    const SizedBox(height: 10),
                    ProjectReceiptContextBox(project: _selectedProject!, summary: _projectSummary!),
                  ],
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int?>(
                    initialValue: _projectId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'پروژه (اختیاری)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      ..._projects.map((p) => DropdownMenuItem(value: p.id, child: Text(p.title))),
                    ],
                    onChanged: _onProjectChanged,
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
                    decoration: const InputDecoration(labelText: 'شرح (اختیاری)'),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('ثبت'),
                  ),
                ],
              ),
            ),
    );
  }
}
