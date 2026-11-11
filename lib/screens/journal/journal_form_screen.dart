import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../models/counterparty.dart';
import '../../models/journal_entry.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/metric_strip.dart';
import '../../widgets/persian_amount_field.dart';

/// سند حسابداری دستی با چند سطر بدهکار/بستانکار دلخواه.
///
/// هر سطر یک حساب و یک مبلغ در ستون بدهکار یا بستانکار دارد (نه هر دو)؛
/// طرف حساب، پروژه و شرح سطر اختیاری‌اند و در برگه «ویرایش سطر» با لمس
/// حساب باز می‌شوند. ثبت فقط وقتی ممکن است که سند متوازن باشد، و دلیل
/// غیرفعال‌بودن دکمه همیشه کنار آن نوشته می‌شود.
class JournalFormScreen extends StatefulWidget {
  final int? presetProjectId;
  final int? presetCounterpartyId;
  const JournalFormScreen({super.key, this.presetProjectId, this.presetCounterpartyId});

  @override
  State<JournalFormScreen> createState() => _JournalFormScreenState();
}

class _JournalLineDraft {
  int? accountId;
  final debit = TextEditingController();
  final credit = TextEditingController();
  final description = TextEditingController();
  int? projectId;
  int? counterpartyId;

  int get debitValue => (parsePersianAmount(debit.text) ?? 0).round();
  int get creditValue => (parsePersianAmount(credit.text) ?? 0).round();
  bool get isEmpty => debitValue == 0 && creditValue == 0;

  void dispose() {
    debit.dispose();
    credit.dispose();
    description.dispose();
  }
}

class _JournalFormScreenState extends State<JournalFormScreen> {
  final _db = DatabaseHelper.instance;
  final _description = TextEditingController();
  String _date = todayJalaliString();
  List<AccountModel> _accounts = [];
  List<ProjectModel> _projects = [];
  List<CounterpartyModel> _counterparties = [];
  final List<_JournalLineDraft> _lines = [];
  bool _loading = true;
  bool _saving = false;

  _JournalLineDraft _newLine() => _JournalLineDraft()
    ..projectId = widget.presetProjectId
    ..counterpartyId = widget.presetCounterpartyId;

  @override
  void initState() {
    super.initState();
    _lines.addAll([_newLine(), _newLine()]);
    _load();
  }

  @override
  void dispose() {
    _description.dispose();
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final accounts = await _db.getPostableAccounts();
    final projects = await _db.getProjects();
    final clients = await _db.getCounterparties();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _projects = projects;
      _counterparties = clients;
      _loading = false;
    });
  }

  void _addLine() => setState(() => _lines.add(_newLine()));

  void _removeLine(int index) {
    setState(() => _lines.removeAt(index).dispose());
  }

  int get _totalDebit => _lines.fold<int>(0, (s, l) => s + l.debitValue);
  int get _totalCredit => _lines.fold<int>(0, (s, l) => s + l.creditValue);
  int get _difference => _totalDebit - _totalCredit;

  /// سطرهای معتبر: دارای حساب و مبلغ مثبت.
  List<_JournalLineDraft> get _validLines =>
      _lines.where((l) => l.accountId != null && (l.debitValue > 0 || l.creditValue > 0)).toList();

  /// دلیل غیرفعال‌بودن دکمه ثبت؛ null یعنی می‌توان ثبت کرد.
  String? get _blockReason {
    if (_validLines.length < 2) return 'حداقل دو سطر با حساب و مبلغ لازم است';
    if (_difference != 0) {
      return 'سند باید متوازن باشد؛ اختلاف ${formatMoney(_difference.abs().toDouble(), withSuffix: false)}';
    }
    return null;
  }

  /// آخرین سطرِ دارای حساب که هنوز مبلغی ندارد - کاندیدای «پر کردن با اختلاف».
  _JournalLineDraft? get _fillCandidate {
    if (_difference == 0) return null;
    for (final l in _lines.reversed) {
      if (l.accountId != null && l.isEmpty) return l;
    }
    return null;
  }

  void _fillWithDifference(_JournalLineDraft line) {
    final diff = _difference;
    if (diff == 0) return;
    final text = formatMoney(diff.abs().toDouble(), withSuffix: false);
    setState(() {
      // اگر بدهکار بیشتر است، سطر باید بستانکار شود و برعکس.
      (diff > 0 ? line.credit : line.debit).text = text;
    });
  }

  String _accountName(int? id) => _accounts.where((a) => a.id == id).map((a) => a.name).firstOrNull ?? '';

  Future<void> _save() async {
    final validLines = _validLines;
    if (validLines.length < 2) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('حداقل دو سطر معتبر لازم است')));
      return;
    }
    if (_difference != 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('سند متوازن نیست؛ جمع بدهکار باید با جمع بستانکار برابر باشد')));
      return;
    }

    setState(() => _saving = true);

    final entry = JournalEntryModel(
      date: _date,
      description: _description.text.trim().isEmpty ? null : _description.text.trim(),
      createdAt: todayJalaliString(),
      lines: validLines
          .map((l) => JournalLineModel(
                accountId: l.accountId!,
                // یک سطر یا بدهکار است یا بستانکار؛ اگر هر دو پر باشد، تفاضل.
                debit: l.debitValue > l.creditValue ? l.debitValue - l.creditValue : 0,
                credit: l.creditValue > l.debitValue ? l.creditValue - l.debitValue : 0,
                description: l.description.text.trim().isEmpty ? null : l.description.text.trim(),
                projectId: l.projectId,
                counterpartyId: l.counterpartyId,
              ))
          .toList(),
    );

    try {
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

  Future<void> _editLine(int index) async {
    final line = _lines[index];
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          child: StatefulBuilder(
            builder: (ctx, setSheet) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('سطر ${pn(index + 1)}', style: AppTextStyles.blockHeading),
                const SizedBox(height: 14),
                DropdownButtonFormField<int>(
                  initialValue: line.accountId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'حساب'),
                  items: _accounts
                      .map((a) => DropdownMenuItem(value: a.id, child: Text(a.name, overflow: TextOverflow.ellipsis)))
                      .toList(),
                  onChanged: (v) => setSheet(() => line.accountId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: line.counterpartyId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'طرف حساب (اختیاری)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    ..._counterparties.map(
                        (c) => DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setSheet(() => line.counterpartyId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int?>(
                  initialValue: line.projectId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'پروژه (اختیاری)'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('—')),
                    ..._projects.map(
                        (p) => DropdownMenuItem(value: p.id, child: Text(p.title, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setSheet(() => line.projectId = v),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: line.description,
                  decoration: const InputDecoration(labelText: 'شرح سطر (اختیاری)'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (_lines.length > 2) ...[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _removeLine(index);
                          },
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.negative,
                              side: const BorderSide(color: AppColors.negative)),
                          child: const Text('حذف سطر'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('تأیید')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) setState(() {});
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
        title: const Text('سند حسابداری', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
      ),
      body: BlueprintGridBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                      children: [
                        _buildHeaderCard(),
                        const SizedBox(height: 14),
                        _buildLinesTable(),
                      ],
                    ),
                  ),
                  _buildBottomBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildHeaderCard() {
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
              constraints: const BoxConstraints(minHeight: 50),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.textSecondary),
                    const SizedBox(width: 12),
                    const Text('تاریخ سند', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerEnd,
                        child: Text(
                          _date == todayJalaliString() ? 'امروز · ${formatJalaliLong(_date)}' : formatJalaliLong(_date),
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
            constraints: const BoxConstraints(minHeight: 50),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  const Text('شرح سند', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _description,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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

  Widget _buildLinesTable() {
    const headStyle = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary);
    final candidate = _fillCandidate;
    return SurfaceBox(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            color: AppColors.surfaceAlt,
            child: const Row(
              children: [
                Expanded(child: Text('حساب', style: headStyle)),
                SizedBox(width: 8),
                SizedBox(width: 92, child: Text('بدهکار', style: headStyle, textAlign: TextAlign.center)),
                SizedBox(width: 8),
                SizedBox(width: 92, child: Text('بستانکار', style: headStyle, textAlign: TextAlign.center)),
              ],
            ),
          ),
          for (var i = 0; i < _lines.length; i++) _buildLineRow(i, isFillCandidate: _lines[i] == candidate),
          if (candidate != null)
            InkWell(
              onTap: () => _fillWithDifference(candidate),
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.brass.withValues(alpha: 0.08),
                  border: const Border(top: BorderSide(color: AppColors.gridLine)),
                ),
                child: Text(
                  'پر کردن ${_difference > 0 ? 'بستانکار' : 'بدهکار'} «${_accountName(candidate.accountId)}» با اختلاف: '
                  '${formatMoney(_difference.abs().toDouble(), withSuffix: false)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brassLight),
                ),
              ),
            ),
          InkWell(
            onTap: _addLine,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.gridLine))),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 18, color: AppColors.textSecondary),
                  SizedBox(width: 6),
                  Text('افزودن سطر', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLineRow(int index, {required bool isFillCandidate}) {
    final line = _lines[index];
    final hasAccount = line.accountId != null;
    final projectTitle = _projects.where((p) => p.id == line.projectId).map((p) => p.title).firstOrNull;
    final counterpartyName = _counterparties.where((c) => c.id == line.counterpartyId).map((c) => c.name).firstOrNull;
    final subtitle = [
      if (projectTitle != null) 'پروژه: $projectTitle',
      if (counterpartyName != null) counterpartyName,
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.gridLine))),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _editLine(index),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasAccount ? _accountName(line.accountId) : 'انتخاب حساب',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: hasAccount ? AppColors.textPrimary : AppColors.brassLight),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle.isEmpty ? 'افزودن طرف حساب یا پروژه' : subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 11,
                          color: projectTitle != null ? AppColors.brassLight : AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: _amountCell(line, debit: true, fillHint: isFillCandidate && _difference < 0),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: _amountCell(line, debit: false, fillHint: isFillCandidate && _difference > 0),
          ),
        ],
      ),
    );
  }

  Widget _amountCell(_JournalLineDraft line, {required bool debit, required bool fillHint}) {
    final controller = debit ? line.debit : line.credit;
    final other = debit ? line.credit : line.debit;
    final filled = controller.text.isNotEmpty;
    if (fillHint) {
      return SizedBox(
        height: 44,
        child: OutlinedButton(
          onPressed: () => _fillWithDifference(line),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: AppColors.brass.withValues(alpha: 0.10),
            side: const BorderSide(color: AppColors.brass, width: 1.5),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: const Text('پر کن', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
        ),
      );
    }
    return SizedBox(
      height: 44,
      child: TextField(
        controller: controller,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        inputFormatters: [PersianAmountInputFormatter()],
        style: TextStyle(fontSize: 12.5, fontWeight: filled ? FontWeight.w600 : FontWeight.w400),
        decoration: InputDecoration(
          hintText: '—',
          isDense: true,
          filled: filled,
          fillColor: AppColors.surfaceAlt,
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          floatingLabelBehavior: FloatingLabelBehavior.never,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: AppColors.gridLine),
          ),
        ),
        onChanged: (v) {
          // یک سطر یا بدهکار است یا بستانکار: پرکردن یک ستون، ستون دیگر را خالی می‌کند.
          if (parsePersianAmount(v) != null && other.text.isNotEmpty) other.clear();
          setState(() {});
        },
      ),
    );
  }

  Widget _buildBottomBar() {
    final reason = _blockReason;
    final diff = _difference;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.gridLine)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MetricStrip(framed: false, items: [
            MetricItem(
                label: 'جمع بدهکار', value: formatMoney(_totalDebit.toDouble(), withSuffix: false), valueSize: 13),
            MetricItem(
                label: 'جمع بستانکار', value: formatMoney(_totalCredit.toDouble(), withSuffix: false), valueSize: 13),
            MetricItem(
              label: 'اختلاف',
              value: diff == 0 ? 'متوازن' : formatMoney(diff.abs().toDouble(), withSuffix: false),
              valueSize: 13,
              // وضعیت با متن («متوازن» / مقدار اختلاف) هم گفته می‌شود، نه فقط رنگ.
              valueColor: diff == 0 && _totalDebit > 0 ? AppColors.positive : (diff == 0 ? null : AppColors.negative),
            ),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: (_saving || reason != null) ? null : _save,
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              child: _saving
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('ثبت سند'),
            ),
          ),
          if (reason != null) ...[
            const SizedBox(height: 6),
            Text(reason,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          ],
        ],
      ),
    );
  }
}
