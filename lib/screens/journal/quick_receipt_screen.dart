import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/counterparty.dart';
import '../../models/journal_entry.dart';
import '../../models/project.dart';
import '../../services/project_workflow_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/persian_words.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/metric_strip.dart';
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
///
/// چیدمان (طرح تأییدشده): انتخاب پروژه در بالا، مبلغ درشت و وسط‌چین با
/// خوانش حروفی، زمینه مالی پروژه (دریافتی تاکنون / مانده پس از این دریافت)،
/// حساب مقصد به‌شکل دکمه‌های انتخابی، تاریخ و توضیح، و دکمه ثبت چسبیده به
/// پایین صفحه.
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
  final _workflow = ProjectWorkflowService(DatabaseHelper.instance);

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

  @override
  void dispose() {
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final asset = await _db.getCashAccounts();
    final incomeAll = await _db.getPostableAccounts(type: kAccountIncome);
    // حساب «حساب‌های دریافتنی» نباید در لیست «بابت درآمد» انتخاب شود
    final arAccount = await _db.getReceivableAccount();
    final income = incomeAll.where((a) => a.id != arAccount?.id).toList();
    final projects = await _db.getProjects();
    final counterparties = await _db.getCounterparties();
    if (!mounted) return;

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
    final id = _projectId;
    if (id == null) {
      if (mounted) setState(() => _projectSummary = null);
      return;
    }
    final summary = await _db.projectFinancialSummary(id);
    // اگر کاربر در این فاصله پروژه دیگری انتخاب کرده، نتیجه قدیمی کنار می‌رود.
    if (mounted && _projectId == id) setState(() => _projectSummary = summary);
  }

  void _onProjectChanged(int? projectId) {
    setState(() {
      _projectId = projectId;
      _projectSummary = null;
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

  Future<void> _pickProject() async {
    // -1 یعنی «بدون پروژه»؛ null یعنی انصراف.
    final picked = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        builder: (ctx, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          children: [
            const Text('انتخاب پروژه', style: AppTextStyles.blockHeading),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('بدون پروژه (دریافت نقدی عمومی)'),
              trailing: _projectId == null ? const Icon(Icons.check, color: AppColors.brass) : null,
              onTap: () => Navigator.pop(ctx, -1),
            ),
            const Divider(height: 1),
            for (final p in _projects) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(_projectSubtitle(p),
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                trailing: p.id == _projectId ? const Icon(Icons.check, color: AppColors.brass) : null,
                onTap: () => Navigator.pop(ctx, p.id),
              ),
              const Divider(height: 1),
            ],
          ],
        ),
      ),
    );
    if (picked == null) return;
    _onProjectChanged(picked == -1 ? null : picked);
  }

  String _projectSubtitle(ProjectModel p) {
    final name = _counterparties.where((c) => c.id == p.counterpartyId).map((c) => c.name).firstOrNull;
    final status = p.isFinalized ? 'نهایی‌شده' : p.status;
    return name == null ? status : '$name · $status';
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
        await _workflow.receiveProjectPayment(
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
          JournalLineModel(accountId: _incomeAccountId!, credit: amount, counterpartyId: _counterpartyId),
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
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.background,
        centerTitle: false,
        leading: IconButton(
          tooltip: 'بستن',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('دریافت وجه', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: BlueprintGridBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Form(
                key: _formKey,
                child: Column(
                  children: [
                    Expanded(child: _buildFields()),
                    _buildSaveBar(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildFields() {
    final isProjectLinked = _projectId != null;
    final amountValue = parsePersianAmount(_amount.text) ?? 0;
    final words = amountToPersianWords(amountValue);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      children: [
        _ProjectSelectorCard(
          title: _selectedProject?.title,
          subtitle: _selectedProject == null ? null : _projectSubtitle(_selectedProject!),
          onTap: _pickProject,
        ),
        const SizedBox(height: 8),
        // فقط یک جمله کوتاه: این دریافت قرار است چه اثری روی حساب‌ها بگذارد.
        Text(
          !isProjectLinked
              ? 'دریافت نقدی عمومی؛ برای ثبت طلب بدون دریافت وجه از «سند حسابداری دستی» استفاده کنید.'
              : (_selectedProject?.isFinalized ?? false)
                  ? 'پروژه نهایی شده؛ این دریافت به‌عنوان تسویه طلب ثبت می‌شود.'
                  : 'پروژه هنوز نهایی نشده؛ این دریافت به‌عنوان پیش‌دریافت ثبت می‌شود (نه درآمد).',
          style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 18),
        _buildAmountBlock(words),
        if (isProjectLinked && _projectSummary != null && _selectedProject != null) ...[
          const SizedBox(height: 14),
          _buildContext(amountValue),
        ],
        const SizedBox(height: 18),
        _buildAccountButtons(),
        if (!isProjectLinked) ...[
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            initialValue: _incomeAccountId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'بابت درآمد'),
            items: _incomeAccounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
            onChanged: (v) => setState(() => _incomeAccountId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: _counterpartyId,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'طرف حساب (اختیاری)'),
            items: [
              const DropdownMenuItem(value: null, child: Text('—')),
              ..._counterparties.map(
                  (c) => DropdownMenuItem(value: c.id, child: Text('${c.name} (${c.roles.join('، ')})'))),
            ],
            onChanged: (v) => setState(() => _counterpartyId = v),
          ),
        ],
        const SizedBox(height: 14),
        _buildDateAndNote(),
      ],
    );
  }

  Widget _buildAmountBlock(String words) {
    final remaining = (_selectedProject != null && _projectSummary != null)
        ? computeProjectRemaining(_selectedProject!, _projectSummary!)
        : null;
    final remainingValue = remaining?.value;
    return Column(
      children: [
        const Text('مبلغ دریافتی (تومان)', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        TextFormField(
          controller: _amount,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [PersianAmountInputFormatter()],
          style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w800),
          decoration: const InputDecoration(
            hintText: '۰',
            filled: false,
            border: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.brass, width: 2)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.brass, width: 2)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: AppColors.brassLight, width: 2)),
            floatingLabelBehavior: FloatingLabelBehavior.never,
          ),
          onChanged: (_) => setState(() {}),
          validator: (v) {
            final parsed = v == null ? null : parsePersianAmount(v);
            return (parsed == null || parsed <= 0) ? 'مبلغ معتبر وارد کنید' : null;
          },
        ),
        const SizedBox(height: 6),
        // جای این خط همیشه رزرو است تا با تایپ، چیدمان صفحه نپرد.
        SizedBox(
          height: 20,
          child: Text(words, style: const TextStyle(fontSize: 13, color: AppColors.brassLight)),
        ),
        if (remainingValue != null && remainingValue > 0) ...[
          const SizedBox(height: 6),
          ActionChip(
            label: Text('کل ${remaining!.label}: ${formatMoney(remainingValue, withSuffix: false)}'),
            labelStyle: const TextStyle(fontSize: 12),
            visualDensity: VisualDensity.standard,
            materialTapTargetSize: MaterialTapTargetSize.padded,
            shape: const StadiumBorder(side: BorderSide(color: AppColors.gridLine)),
            backgroundColor: AppColors.surfaceAlt,
            onPressed: () {
              final text = formatMoney(remainingValue, withSuffix: false);
              setState(() => _amount.value =
                  TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)));
            },
          ),
        ],
      ],
    );
  }

  Widget _buildContext(double amountValue) {
    final project = _selectedProject!;
    final summary = _projectSummary!;
    final received = (summary['totalReceived'] as double?) ?? 0;
    final info = computeProjectRemaining(project, summary);
    final remaining = info.value;
    final after = remaining == null ? null : remaining - amountValue;
    final settles = project.isFinalized && after != null && after <= 0 && amountValue > 0;
    return SurfaceBox(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: MetricStrip(
        framed: false,
        items: [
          MetricItem(label: 'دریافتی تاکنون', value: formatMoney(received, withSuffix: false), valueSize: 14),
          MetricItem(
            label: '${info.label} پس از این دریافت',
            value: after == null ? '—' : formatMoney(after < 0 ? 0 : after, withSuffix: false),
            valueSize: 14,
            footer: settles
                ? const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 14, color: AppColors.positive),
                      SizedBox(width: 3),
                      Flexible(
                        child: Text('تسویه می‌شود',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.positive)),
                      ),
                    ],
                  )
                : (after != null && after < 0 && amountValue > 0
                    ? const Text('بیشتر از مانده',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary))
                    : null),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('واریز به', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final a in _cashAccounts)
              _AccountChoice(
                label: a.name,
                selected: a.id == _cashAccountId,
                onTap: () => setState(() => _cashAccountId = a.id),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildDateAndNote() {
    return SurfaceBox(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: () async {
              final picked = await pickJalaliDate(context, _date);
              if (picked != null && mounted) setState(() => _date = picked);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    const Text('تاریخ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(width: 12),
                    // با فونت بزرگ سیستم، تاریخ کوچک می‌شود به‌جای بیرون‌زدن.
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          _date == todayJalaliString()
                              ? 'امروز · ${formatJalaliLong(_date)}'
                              : formatJalaliLong(_date),
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Icon(Icons.notes_outlined, size: 18, color: AppColors.textSecondary),
                  const SizedBox(width: 12),
                  const Text('توضیح', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _description,
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'اختیاری',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        floatingLabelBehavior: FloatingLabelBehavior.never,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.gridLine)),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          child: _saving
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ثبت دریافت'),
        ),
      ),
    );
  }
}

class _ProjectSelectorCard extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final VoidCallback onTap;
  const _ProjectSelectorCard({required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.gridLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 60),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('پروژه', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      const SizedBox(height: 2),
                      Text(title ?? 'بدون پروژه',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      if (subtitle != null)
                        Text(subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
                const Icon(Icons.unfold_more, size: 20, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountChoice extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _AccountChoice({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.brass.withValues(alpha: 0.14) : AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? AppColors.brass : AppColors.gridLine, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 96),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? AppColors.brassLight : AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
