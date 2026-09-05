import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/financial_reports.dart';
import '../../models/project.dart';
import '../../services/financial_reporting_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../counterparties/counterparty_detail_screen.dart';
import '../projects/project_detail_screen.dart';

enum _ReceivablesView { byProject, byCounterparty, estimated, pendingProjects }

/// لیست کامل (نه فقط چند مورد اول) پروژه‌ها و طرف‌حساب‌هایی که مانده طلب
/// یا مانده تخمینی دارند - مرتب‌شده نزولی بر اساس مبلغ. «مانده طلب» (دو
/// نمای اول) از FinancialReportingService.getProjectReports() می‌آید و
/// فقط به پروژه‌های Finalize‌شده تعلق دارد؛ «مانده تخمینی» (نمای سوم) از
/// «مانده تخمینی» (نمای سوم) از estimatedRemainingForOpenProjects می‌آید
/// (همان تعریفی که در فرم‌های دریافت وجه دیده می‌شود، فقط به‌شکل دسته‌ای و
/// بهینه) و مخصوص پروژه‌های Finalize‌نشده است - این دو مفهوم عمداً
/// در دو نمای جدا نگه داشته شده‌اند تا هرگز با هم قاطی نشوند (یکی مانده
/// واقعی حساب دریافتنی است، دیگری فقط یک برآورد پیش از قطعی‌شدن مبلغ).
/// هیچ محاسبهٔ مالی جدیدی در این صفحه انجام نمی‌شود.
class OutstandingReceivablesScreen extends StatefulWidget {
  /// اگر true باشد، صفحه مستقیماً روی نمای «پروژه‌های معلق» باز می‌شود
  /// (برای کلیک روی کارت پیش‌دریافت داشبورد).
  final bool openPendingProjects;
  const OutstandingReceivablesScreen({super.key, this.openPendingProjects = false});

  @override
  State<OutstandingReceivablesScreen> createState() => _OutstandingReceivablesScreenState();
}

class _OutstandingReceivablesScreenState extends State<OutstandingReceivablesScreen> {
  final _reporting = FinancialReportingService();
  final _db = DatabaseHelper.instance;
  late _ReceivablesView _view =
      widget.openPendingProjects ? _ReceivablesView.pendingProjects : _ReceivablesView.byProject;
  bool _loading = true;
  String? _error;
  List<ProjectFinancialReport> _outstandingProjects = [];
  List<_EstimatedOutstanding> _estimatedProjects = [];
  List<_PendingProject> _pendingProjects = [];
  Map<int, String> _counterpartyNames = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _loadData();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadData() async {
    final reports = await _reporting.getProjectReports();
    final counterparties = await _db.getCounterparties(includeInactive: true);
    final counterpartyNames = {for (final c in counterparties) c.id!: c.name};
    final outstanding = reports.where((p) => p.receivableBalance > 0).toList()
      ..sort((a, b) => b.receivableBalance.compareTo(a.receivableBalance));

    // مانده تخمینی: فقط پروژه‌های Finalize‌نشده - محاسبهٔ دسته‌ای بهینه
    // (تعداد ثابتی کوئری، نه یک projectFinancialSummary سنگین به‌ازای هر
    // پروژه)، با دقیقاً همان تعریفی که در فرم‌های دریافت وجه دیده می‌شود.
    final allProjects = await _db.getProjects();
    final estimatedMap = await _db.estimatedRemainingForOpenProjects();
    final estimatedList = <_EstimatedOutstanding>[];
    for (final project in allProjects.where((p) => !p.isFinalized)) {
      final remaining = estimatedMap[project.id];
      if (remaining != null && remaining > 0) {
        estimatedList.add(_EstimatedOutstanding(
          project: project,
          estimatedRemaining: remaining,
          counterpartyName: counterpartyNames[project.counterpartyId] ?? '—',
        ));
      }
    }
    estimatedList.sort((a, b) => b.estimatedRemaining.compareTo(a.estimatedRemaining));

    // پروژه‌های معلق: همه پروژه‌های Finalize‌نشده (حتی بدون پیش‌دریافت،
    // چون درآمدشان هم معلق است). مرتب‌سازی طبق اولویت مدیریتی: ابتدا
    // بیشترین پیش‌دریافت (تعهد مالی سنگین‌تر)، سپس در تساوی، قدیمی‌ترین
    // پروژه اول (کاری که مدت بیشتری معلق مانده فوری‌تر است). پروژه‌های
    // بدون هیچ پیش‌دریافتی به انتهای فهرست می‌روند - همچنان دیده می‌شوند
    // ولی فوریت مالی کمتری دارند.
    final advanceMap = await _db.advanceBalanceForOpenProjects();
    final pending = allProjects
        .where((p) => !p.isFinalized)
        .map((p) => _PendingProject(
              project: p,
              advance: advanceMap[p.id] ?? 0,
              counterpartyName: counterpartyNames[p.counterpartyId] ?? '—',
            ))
        .toList()
      ..sort((a, b) {
        final aHas = a.advance > 0;
        final bHas = b.advance > 0;
        if (aHas != bHas) return aHas ? -1 : 1; // بدون پیش‌دریافت، انتهای فهرست
        final byAdvance = b.advance.compareTo(a.advance);
        if (byAdvance != 0) return byAdvance;
        return a.project.startDate.compareTo(b.project.startDate); // قدیمی‌تر جلوتر
      });

    setState(() {
      _outstandingProjects = outstanding;
      _estimatedProjects = estimatedList;
      _pendingProjects = pending;
      _counterpartyNames = counterpartyNames;
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
    final isEstimatedView = _view == _ReceivablesView.estimated;
    final isPendingView = _view == _ReceivablesView.pendingProjects;
    final double grandTotal;
    final bool isEmpty;
    final String totalLabel;
    if (isPendingView) {
      grandTotal = _pendingProjects.fold<double>(0, (s, p) => s + p.advance);
      isEmpty = _pendingProjects.isEmpty;
      totalLabel = 'جمع کل پیش‌دریافت‌ها';
    } else if (isEstimatedView) {
      grandTotal = _estimatedProjects.fold<double>(0, (s, p) => s + p.estimatedRemaining);
      isEmpty = _estimatedProjects.isEmpty;
      totalLabel = 'جمع کل مانده تخمینی';
    } else {
      grandTotal = _outstandingProjects.fold<double>(0, (s, p) => s + p.receivableBalance);
      isEmpty = _outstandingProjects.isEmpty;
      totalLabel = 'جمع کل طلب‌های باز';
    }

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
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline, color: AppColors.negative, size: 36),
                          const SizedBox(height: 12),
                          Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: AppColors.negative, fontSize: 13)),
                          const SizedBox(height: 16),
                          OutlinedButton(onPressed: _load, child: const Text('تلاش دوباره')),
                        ],
                      ),
                    ),
                  )
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
                          Text(totalLabel,
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                          Text(formatMoney(grandTotal),
                              style: const TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.brass)),
                        ],
                      ),
                    ),
                    if (isEstimatedView) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'این مبالغ برآوردی‌اند (پیش از نهایی‌سازی پروژه)، نه طلب قطعی.',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                    if (isPendingView) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'پیش‌دریافت یک تعهد است، نه درآمد. با نهایی‌سازی پروژه پس از تحویل کار،'
                        ' درآمدش شناسایی می‌شود.',
                        style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                    ],
                    const SizedBox(height: 16),
                    if (isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                              isPendingView
                                  ? 'همه پروژه‌ها نهایی شده‌اند.'
                                  : (isEstimatedView
                                      ? 'هیچ مانده تخمینی‌ای وجود ندارد.'
                                      : 'هیچ طلب بازی وجود ندارد.'),
                              style: const TextStyle(color: AppColors.textSecondary)),
                        ),
                      )
                    else if (_view == _ReceivablesView.byProject)
                      ..._outstandingProjects.map((p) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.description_outlined, color: AppColors.brass),
                              title: Text(p.projectName),
                              subtitle: Text(_counterpartyNames[p.counterpartyId] ?? '—'),
                              trailing: Text(formatMoneyCompact(p.receivableBalance),
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
                    else if (_view == _ReceivablesView.byCounterparty)
                      ..._byCounterparty.map((c) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.person_outline, color: AppColors.brass),
                              title: Text(c.name),
                              subtitle: Text('${pn(c.projectCount)} پروژه دارای مانده'),
                              trailing: Text(formatMoneyCompact(c.totalReceivable),
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
                          ))
                    else if (_view == _ReceivablesView.estimated)
                      ..._estimatedProjects.map((e) => Card(
                            child: ListTile(
                              leading: const Icon(Icons.hourglass_empty, color: AppColors.brass),
                              title: Text(e.project.title),
                              subtitle: Text(e.counterpartyName),
                              trailing: Text(formatMoneyCompact(e.estimatedRemaining),
                                  style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brass)),
                              onTap: () async {
                                await Navigator.push(context,
                                    MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: e.project)));
                                _load();
                              },
                            ),
                          ))
                    else
                      ..._pendingProjects.map((p) {
                        final hasAdvance = p.advance > 0;
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              hasAdvance ? Icons.account_balance_wallet_outlined : Icons.pending_outlined,
                              color: hasAdvance ? AppColors.brass : AppColors.textSecondary,
                            ),
                            title: Text(p.project.title),
                            subtitle: Text(
                                '${p.counterpartyName} · از ${formatJalaliLong(p.project.startDate)}'),
                            trailing: Text(
                              hasAdvance ? formatMoneyCompact(p.advance) : 'بدون دریافت',
                              style: TextStyle(
                                fontSize: hasAdvance ? 14 : 11,
                                fontWeight: hasAdvance ? FontWeight.w800 : FontWeight.normal,
                                color: hasAdvance ? AppColors.brass : AppColors.textSecondary,
                              ),
                            ),
                            onTap: () async {
                              await Navigator.push(context,
                                  MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p.project)));
                              _load();
                            },
                          ),
                        );
                      }),
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

class _EstimatedOutstanding {
  final ProjectModel project;
  final double estimatedRemaining;
  final String counterpartyName;
  _EstimatedOutstanding(
      {required this.project, required this.estimatedRemaining, required this.counterpartyName});
}

class _PendingProject {
  final ProjectModel project;
  final double advance;
  final String counterpartyName;
  _PendingProject({required this.project, required this.advance, required this.counterpartyName});
}

/// سوییچ سه‌تایی به‌شکل Chip قابل‌کلیک با اسکرول افقی (نه Row+Expanded) تا
/// با برچسب‌های طولانی‌تر هم هرگز سرریز نشود.
class _ViewSwitcher extends StatelessWidget {
  final _ReceivablesView selected;
  final ValueChanged<_ReceivablesView> onChanged;
  const _ViewSwitcher({required this.selected, required this.onChanged});

  static const _labels = {
    _ReceivablesView.byProject: 'بر اساس پروژه',
    _ReceivablesView.byCounterparty: 'بر اساس طرف‌حساب',
    _ReceivablesView.estimated: 'مانده تخمینی',
    _ReceivablesView.pendingProjects: 'پروژه‌های معلق',
  };

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _ReceivablesView.values.map((v) {
          final active = v == selected;
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(17),
              onTap: () => onChanged(v),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.brass : AppColors.surface,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: active ? AppColors.brass : AppColors.gridLine),
                ),
                child: Text(
                  _labels[v]!,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: active ? const Color(0xFF15100A) : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
