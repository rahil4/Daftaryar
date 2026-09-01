import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/counterparty.dart';
import '../../models/project.dart';
import '../../models/journal_entry.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/quick_add_sheet.dart';
import '../../services/pdf_export_service.dart';
import 'counterparty_form_screen.dart';
import '../projects/project_detail_screen.dart';
import '../projects/project_form_screen.dart';
import '../journal/journal_entry_detail_screen.dart';

class CounterpartyDetailScreen extends StatefulWidget {
  final CounterpartyModel counterparty;
  const CounterpartyDetailScreen({super.key, required this.counterparty});

  @override
  State<CounterpartyDetailScreen> createState() => _CounterpartyDetailScreenState();
}

class _CounterpartyDetailScreenState extends State<CounterpartyDetailScreen> {
  final _db = DatabaseHelper.instance;
  final _pdf = PdfExportService();
  List<ProjectModel> _projects = [];
  List<JournalEntryModel> _directEntries = [];
  double _received = 0;
  double _spent = 0;
  double _receivable = 0; // مانده مطالبات (AR) - همیشه از Ledger محاسبه می‌شود
  double _payable = 0; // مانده بدهی (AP) - همیشه از Ledger محاسبه می‌شود
  late CounterpartyModel _counterparty;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _counterparty = widget.counterparty;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final projects = await _db.getProjects(counterpartyId: _counterparty.id);
    final directEntries = await _db.getDirectCounterpartyEntries(_counterparty.id!);
    final fin = await _db.counterpartyFinancials(_counterparty.id!);
    final receivable = await _db.receivableBalance(_counterparty.id!);
    final payable = await _db.payableBalance(_counterparty.id!);
    setState(() {
      _projects = projects;
      _directEntries = directEntries;
      _received = fin['received']!;
      _spent = fin['spent']!;
      _receivable = receivable;
      _payable = payable;
      _loading = false;
    });
  }

  void _showAddOptions() {
    showQuickAddSheet(context, presetCounterpartyId: _counterparty.id, onDone: _load);
  }

  Future<void> _exportStatement() async {
    setState(() => _exporting = true);
    try {
      final projectRows = <Map<String, dynamic>>[];
      final transactions = <Map<String, dynamic>>[];

      for (final p in _projects) {
        final fin = await _db.projectFinancials(p.id!);
        final received = fin['received']!;
        projectRows.add({
          'title': p.title,
          'agreedAmount': p.agreedAmount,
          'received': received,
          'remaining': p.agreedAmount - received,
        });

        final entries = await _db.getJournalEntries(projectId: p.id);
        for (final e in entries) {
          for (final l in e.lines) {
            if (l.projectId != p.id) continue;
            if (l.debit == 0 && l.credit == 0) continue;
            transactions.add({
              'date': e.date,
              'description': e.description ?? p.title,
              'type': l.credit > 0 ? 'دریافت' : 'پرداخت',
              'amount': l.credit > 0 ? l.credit : l.debit,
            });
          }
        }
      }

      // تراکنش‌های مستقیم (بدون پروژه) هم به صورتحساب اضافه می‌شوند
      for (final e in _directEntries) {
        for (final l in e.lines) {
          if (l.counterpartyId != _counterparty.id) continue;
          if (l.debit == 0 && l.credit == 0) continue;
          transactions.add({
            'date': e.date,
            'description': e.description ?? 'تراکنش مستقیم',
            'type': l.credit > 0 ? 'دریافت' : 'پرداخت',
            'amount': l.credit > 0 ? l.credit : l.debit,
          });
        }
      }

      transactions.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      await _pdf.exportCounterpartyStatement(
        counterpartyName: _counterparty.name,
        counterpartyPhone: _counterparty.phone,
        projectRows: projectRows,
        transactions: transactions,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _toggleActive() async {
    await _db.setCounterpartyActive(_counterparty.id!, !_counterparty.isActive);
    final updated = await _db.getCounterparty(_counterparty.id!);
    if (updated != null && mounted) setState(() => _counterparty = updated);
  }

  Future<void> _deleteCounterparty() async {
    final hasHistory = _projects.isNotEmpty || _directEntries.isNotEmpty;
    if (hasHistory) {
      final goDeactivate = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('حذف ممکن نیست'),
          content: const Text(
              'این طرف حساب پروژه یا سند مالی ثبت‌شده دارد و برای حفظ سوابق حسابداری، قابل حذف فیزیکی نیست. به‌جای آن می‌توانید غیرفعالش کنید.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('بستن')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('غیرفعال کردن')),
          ],
        ),
      );
      if (goDeactivate == true) await _toggleActive();
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف طرف حساب'),
        content: Text('«${_counterparty.name}» برای همیشه حذف می‌شود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: AppColors.negative))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _db.deleteCounterparty(_counterparty.id!);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final net = _received - _spent;
    return Scaffold(
      appBar: AppBar(
        title: Text(_counterparty.name),
        actions: [
          IconButton(
            icon: Icon(_counterparty.isActive
                ? Icons.toggle_on_outlined
                : Icons.toggle_off_outlined),
            tooltip: _counterparty.isActive ? 'غیرفعال کردن' : 'فعال کردن',
            onPressed: _toggleActive,
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final result = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => CounterpartyFormScreen(existing: _counterparty)));
              if (result == true) {
                final updated = await _db.getCounterparty(_counterparty.id!);
                if (updated != null) setState(() => _counterparty = updated);
              }
            },
          ),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteCounterparty),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _exporting ? null : _exportStatement,
        icon: _exporting
            ? const SizedBox(
                height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('خروجی صورتحساب'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : BlueprintGridBackground(
              child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (!_counterparty.isActive)
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.textSecondary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text('این طرف حساب غیرفعال است',
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                      ),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _infoRow(Icons.badge_outlined, _counterparty.roles.join('، ')),
                            if (_counterparty.phone != null)
                              _infoRow(Icons.phone_outlined, _counterparty.phone!),
                            if (_counterparty.nationalId != null)
                              _infoRow(Icons.perm_identity_outlined, _counterparty.nationalId!),
                            if (_counterparty.address != null)
                              _infoRow(Icons.location_on_outlined, _counterparty.address!),
                            if (_counterparty.notes != null)
                              _infoRow(Icons.notes_outlined, _counterparty.notes!),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.6,
                      children: [
                        StatCard(
                          title: 'مجموع دریافتی',
                          value: formatMoney(_received),
                          icon: Icons.south_west_rounded,
                          color: AppColors.positive,
                        ),
                        StatCard(
                          title: 'مجموع پرداختی',
                          value: formatMoney(_spent),
                          icon: Icons.north_east_rounded,
                          color: AppColors.negative,
                        ),
                        StatCard(
                          title: net >= 0 ? 'مانده به نفع طرف حساب' : 'مانده بدهکار طرف حساب',
                          value: formatMoney(net.abs()),
                          icon: Icons.account_balance_wallet_outlined,
                          color: net >= 0 ? AppColors.positive : AppColors.negative,
                        ),
                        if (_receivable != 0)
                          StatCard(
                            title: 'مانده مطالبات (طلب از او)',
                            value: formatMoney(_receivable),
                            icon: Icons.request_quote_outlined,
                            color: AppColors.positive,
                          ),
                        if (_payable != 0)
                          StatCard(
                            title: 'مانده بدهی (بدهکاری به او)',
                            value: formatMoney(_payable),
                            icon: Icons.payments_outlined,
                            color: AppColors.negative,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton.icon(
                        onPressed: _showAddOptions,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('ثبت دریافت/پرداخت برای این طرف حساب'),
                      ),
                    ),

                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('پروژه‌های این طرف حساب (${pn(_projects.length)})',
                            style: Theme.of(context).textTheme.titleMedium),
                        TextButton.icon(
                          onPressed: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => ProjectFormScreen(presetCounterparty: _counterparty)),
                            );
                            if (result == true) _load();
                          },
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('پروژه جدید'),
                        ),
                      ],
                    ),
                    if (_projects.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4, bottom: 8),
                        child: Text('پروژه‌ای برای این طرف حساب ثبت نشده',
                            style: TextStyle(color: AppColors.textSecondary)),
                      )
                    else
                      ..._projects.map((p) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.work_outline, color: AppColors.brass),
                              title: Text(p.title),
                              subtitle: Text('${p.projectType} · ${p.status}'),
                              trailing: const Icon(Icons.chevron_left),
                              onTap: () async {
                                await Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p)));
                                _load();
                              },
                            ),
                          )),

                    const SizedBox(height: 20),
                    Text('تراکنش‌های مستقیم (بدون پروژه) (${pn(_directEntries.length)})',
                        style: Theme.of(context).textTheme.titleMedium),
                    if (_directEntries.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('تراکنش مستقیمی برای این طرف حساب ثبت نشده',
                            style: TextStyle(color: AppColors.textSecondary)),
                      )
                    else
                      ..._directEntries.map((e) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.receipt_long_outlined, color: AppColors.brass),
                              title: Text(e.description ?? 'سند شماره ${pn(e.id!)}'),
                              subtitle: Text(
                                  '${formatJalaliLong(e.date)} · ${formatMoney(e.totalDebit)}'),
                              trailing: const Icon(Icons.chevron_left),
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => JournalEntryDetailScreen(entryId: e.id!)),
                                );
                                _load();
                              },
                            ),
                          )),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
