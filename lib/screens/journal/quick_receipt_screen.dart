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

enum _ReceiptMode { cash, creditSale, settleReceivable }

/// ثبت دریافت/درآمد.
///
/// نکته مهم (Financial Data Integrity - مورد ۱۰): وقتی یک پروژه انتخاب شده
/// باشد، این فرم دیگر از حالت‌های نقدی/ایجاد طلب/دریافت طلب استفاده
/// نمی‌کند و کل عملیات به receiveProjectPayment() واگذار می‌شود؛ آن تابع
/// به‌صورت هوشمند پیش از Finalization به «پیش‌دریافت مشتری» و پس از آن به
/// تسویه «حساب‌های دریافتنی» می‌رود - هرگز مستقیم Revenue شناسایی نمی‌کند
/// برای پروژه‌ای که هنوز Finalize نشده. سه حالت قبلی فقط برای دریافت
/// بدون پروژه (یا دریافت عمومی) باقی می‌مانند، بدون هیچ تغییری.
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
  _ReceiptMode _mode = _ReceiptMode.cash;

  List<AccountModel> _cashAccounts = [];
  List<AccountModel> _incomeAccounts = [];
  List<ProjectModel> _projects = [];
  List<CounterpartyModel> _counterparties = [];
  int? _cashAccountId;
  int? _incomeAccountId;
  int? _projectId;
  int? _counterpartyId;
  double? _currentReceivable;
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
    await _refreshReceivableHint();
  }

  Future<void> _refreshReceivableHint() async {
    if (_projectId != null) {
      // برای دریافت مرتبط با پروژه، مانده مرتبط خودِ همان پروژه نمایش داده
      // می‌شود (نه مانده کلی طرف حساب)، چون مقصد سند بر همین اساس تعیین می‌شود.
      if (_selectedProject != null && _selectedProject!.isFinalized) {
        final bal = await _db.projectReceivableBalance(_projectId!);
        if (mounted) setState(() => _currentReceivable = bal);
      } else if (mounted) {
        setState(() => _currentReceivable = null);
      }
      // مجموع دریافتی تاکنون + مانده - مستقل از این‌که پروژه Finalize شده
      // یا نه (برخلاف مانده طلب بالا که فقط بعد از Finalization معنا دارد).
      final summary = await _db.projectFinancialSummary(_projectId!);
      if (mounted) setState(() => _projectSummary = summary);
      return;
    }
    if (mounted) setState(() => _projectSummary = null);
    if (_mode == _ReceiptMode.settleReceivable && _counterpartyId != null) {
      final bal = await _db.receivableBalance(_counterpartyId!);
      if (mounted) setState(() => _currentReceivable = bal);
    } else {
      setState(() => _currentReceivable = null);
    }
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
    _refreshReceivableHint();
  }

  bool get _requiresCounterparty => _projectId == null && _mode != _ReceiptMode.cash;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_requiresCounterparty && _counterpartyId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('برای ایجاد طلب یا دریافت طلب، انتخاب طرف حساب الزامی است')));
      return;
    }

    setState(() => _saving = true);
    final amount = (parsePersianAmount(_amount.text) ?? 0).round();

    try {
      if (_projectId != null) {
        // مسیر پروژه‌محور: کل منطق تشخیص پیش‌دریافت/تسویه طلب به
        // receiveProjectPayment سپرده می‌شود - این فرم دیگر خودش تصمیم
        // نمی‌گیرد کدام حساب بستانکار شود.
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

      JournalEntryModel entry;
      if (_mode == _ReceiptMode.cash) {
        if (_cashAccountId == null || _incomeAccountId == null) {
          setState(() => _saving = false);
          return;
        }
        entry = JournalEntryModel(
          date: _date,
          description: _description.text.trim().isEmpty ? 'دریافت وجه' : _description.text.trim(),
          createdAt: todayJalaliString(),
          lines: [
            JournalLineModel(
                accountId: _cashAccountId!, debit: amount, counterpartyId: _counterpartyId),
            JournalLineModel(
                accountId: _incomeAccountId!, credit: amount, counterpartyId: _counterpartyId),
          ],
        );
      } else if (_mode == _ReceiptMode.creditSale) {
        final arAccount = await _db.getReceivableAccount();
        if (arAccount == null || _incomeAccountId == null) {
          setState(() => _saving = false);
          return;
        }
        entry = JournalEntryModel(
          date: _date,
          description:
              _description.text.trim().isEmpty ? 'ایجاد طلب (فروش نسیه)' : _description.text.trim(),
          createdAt: todayJalaliString(),
          lines: [
            JournalLineModel(
                accountId: arAccount.id!, debit: amount, counterpartyId: _counterpartyId),
            JournalLineModel(
                accountId: _incomeAccountId!, credit: amount, counterpartyId: _counterpartyId),
          ],
        );
      } else {
        final arAccount = await _db.getReceivableAccount();
        if (arAccount == null || _cashAccountId == null) {
          setState(() => _saving = false);
          return;
        }
        entry = JournalEntryModel(
          date: _date,
          description: _description.text.trim().isEmpty ? 'دریافت طلب' : _description.text.trim(),
          createdAt: todayJalaliString(),
          lines: [
            JournalLineModel(
                accountId: _cashAccountId!, debit: amount, counterpartyId: _counterpartyId),
            JournalLineModel(
                accountId: arAccount.id!, credit: amount, counterpartyId: _counterpartyId),
          ],
        );
      }
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
    final amountValue = parsePersianAmount(_amount.text);
    final isProjectLinked = _projectId != null;
    final overLimit = !isProjectLinked &&
        _mode == _ReceiptMode.settleReceivable &&
        _currentReceivable != null &&
        amountValue != null &&
        amountValue > _currentReceivable!;

    return Scaffold(
      appBar: AppBar(title: const Text('ثبت دریافت / درآمد')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (!isProjectLinked)
                    SegmentedButton<_ReceiptMode>(
                      segments: const [
                        ButtonSegment(value: _ReceiptMode.cash, label: Text('نقدی')),
                        ButtonSegment(value: _ReceiptMode.creditSale, label: Text('ایجاد طلب')),
                        ButtonSegment(value: _ReceiptMode.settleReceivable, label: Text('دریافت طلب')),
                      ],
                      selected: {_mode},
                      onSelectionChanged: (s) {
                        setState(() {
                          _mode = s.first;
                          _amount.clear();
                        });
                        _refreshReceivableHint();
                      },
                    )
                  else
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
                  if (isProjectLinked || _mode != _ReceiptMode.creditSale) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: _cashAccountId,
                      decoration: const InputDecoration(labelText: 'واریز به حساب'),
                      items: _cashAccounts
                          .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name)))
                          .toList(),
                      onChanged: (v) => setState(() => _cashAccountId = v),
                    ),
                  ],
                  if (!isProjectLinked && _mode != _ReceiptMode.settleReceivable) ...[
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
                    decoration: InputDecoration(
                        labelText: _requiresCounterparty ? 'طرف حساب *' : 'طرف حساب (اختیاری)'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('—')),
                      ..._counterparties.map((c) => DropdownMenuItem(
                          value: c.id, child: Text('${c.name} (${c.roles.join('، ')})'))),
                    ],
                    // وقتی دریافت به پروژه وصل است، طرف حساب از خودِ پروژه
                    // مشخص می‌شود و قابل تغییر دستی نیست.
                    onChanged: isProjectLinked
                        ? null
                        : (v) {
                            setState(() => _counterpartyId = v);
                            _refreshReceivableHint();
                          },
                  ),
                  if (!isProjectLinked &&
                      _mode == _ReceiptMode.settleReceivable &&
                      _currentReceivable != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'مانده طلب فعلی این طرف حساب: ${formatMoney(_currentReceivable!)}',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    if (overLimit)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'مبلغ دریافت بیشتر از مانده طلب است و امکان ثبت این عملیات وجود ندارد.',
                          style: TextStyle(fontSize: 12, color: AppColors.negative, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
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
                    onPressed: (_saving || overLimit) ? null : _save,
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
