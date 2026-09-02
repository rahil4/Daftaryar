import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/financial_reports.dart';
import '../../services/financial_reporting_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../counterparties/counterparty_detail_screen.dart';
import '../projects/project_detail_screen.dart';

enum _ReceivablesView { byProject, byCounterparty }

/// لیست کامل (نه فقط چند مورد اول) پروژه‌ها و طرف‌حساب‌هایی که مانده طلب
/// دارند - مرتب‌شده نزولی بر اساس مبلغ. تنها مصرف‌کنندهٔ
/// FinancialReportingService.getProjectReports() است؛ هیچ محاسبهٔ مالی
/// جدیدی اینجا انجام نمی‌شود - «مانده طلب» دقیقاً همان چیزی است که در
/// جزئیات هر پروژه/طرف‌حساب هم دیده می‌شود.
class OutstandingReceivablesScreen extends StatefulWidget {
  const OutstandingReceivablesScreen({super.key});

  @override
  State<OutstandingReceivablesScreen> createState() => _OutstandingReceivablesScreenState();
}

class _OutstandingReceivablesScreenState extends State<OutstandingReceivablesScreen> {
  final _reporting = FinancialReportingService();
  final _db = DatabaseHelper.instance;
  _ReceivablesView _view = _ReceivablesView.byProject;
  bool _loading = true;
  List<ProjectFinancialReport> _outstandingProjects = [];
  Map<int, String> _counterpartyNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final reports = await _reporting.getProjectReports();
    final counterparties = await _db.getCounterparties(includeInactive: true);
    final outstanding = reports.where((p) => p.receivableBalance > 0).toList()
      ..sort((a, b) => b.receivableBalance.compareTo(a.receivableBalance));
    setState(() {
      _outstandingProjects = outstanding;
      _counterpartyNames = {for (final c in counterparties) c.id!: c.name};
      _loading = false;
    });
  }

  /// جمع مانده طلب هر طرف‌حساب - صرفاً جمع‌زدن همان مانده‌های پروژه‌ای که
  /// از قبل محاسبه شده‌اند، نه یک محاسبهٔ مستقل موازی.
  List<_CounterpartyOutstanding> get _byCounterparty {
    final totals = <int, double>{};
    final projectCounts = <int, int>{};
    for (final p in _outstandingProjects) {
      totals[p.counterpartyId] = (totals[p.counterpartyId] ?? 0) + p.receivableBalance;
      projectCounts[p.counterpartyId] = (projectCounts[p.counterpartyId] ?? 0) + 1;
    }
    final list = totals.entries
        .map((e) => _CounterpartyOutstanding(
              counterpartyId: e.key,
              name: _counterpartyNames[e.key] ?? '—',
              totalReceivable: e.value,
              projectCount: projectCounts[e.key]!,
            ))
        .toList()
      ..sort((a, b) => b.totalReceivable.compareTo(a.totalReceivable));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final grandTotal = _outstandingProjects.fold<double>(0, (s, p) => s + p.receivableBalance);
    return Scaffold(
      appBar: AppBar(
        title: const Text('طلب‌های باز'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _ViewSwitcher(selected: _view, onChanged: (v) => setState(() => _view = v)),
          ),
        ),
      ),
      body: BlueprintGridBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.brass.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.brass),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('جمع کل طلب‌های باز',
                              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          Text(formatMoney(grandTotal),
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.brass)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_outstandingProjects.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text('هیچ طلب بازی وجود ندارد.',
                              style: TextStyle(color: AppColors.textSecondary)),
                        ),
                      )
                    else if (_view == _ReceivablesView.byProject)
                      ..._outstandingProjects.map((p) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.description_outlined, color: AppColors.brass),
                              title: Text(p.projectName),
                              subtitle: Text(_counterpartyNames[p.counterpartyId] ?? '—'),
                              trailing: Text(formatMoney(p.receivableBalance),
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brass)),
                              onTap: () async {
                                final project = await _db.getProject(p.projectId);
                                if (project == null || !context.mounted) return;
                                await Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: project)));
                                _load();
                              },
                            ),
                          ))
                    else
                      ..._byCounterparty.map((c) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.person_outline, color: AppColors.brass),
                              title: Text(c.name),
                              subtitle: Text('${pn(c.projectCount)} پروژه دارای مانده'),
                              trailing: Text(formatMoney(c.totalReceivable),
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brass)),
                              onTap: () async {
                                final counterparty = await _db.getCounterparty(c.counterpartyId);
                                if (counterparty == null || !context.mounted) return;
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => CounterpartyDetailScreen(counterparty: counterparty)));
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
}

class _CounterpartyOutstanding {
  final int counterpartyId;
  final String name;
  final double totalReceivable;
  final int projectCount;
  _CounterpartyOutstanding(
      {required this.counterpartyId,
      required this.name,
      required this.totalReceivable,
      required this.projectCount});
}

class _ViewSwitcher extends StatelessWidget {
  final _ReceivablesView selected;
  final ValueChanged<_ReceivablesView> onChanged;
  const _ViewSwitcher({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.gridLine),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(child: _segment(context, 'بر اساس پروژه', _ReceivablesView.byProject)),
          Expanded(child: _segment(context, 'بر اساس طرف‌حساب', _ReceivablesView.byCounterparty)),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String label, _ReceivablesView value) {
    final active = selected == value;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: active ? AppColors.brass : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: active ? const Color(0xFF15100A) : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}
