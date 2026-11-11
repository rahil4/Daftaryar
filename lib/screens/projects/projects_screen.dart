import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/project.dart';
import '../../services/financial_metrics_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/reloadable.dart';
import '../../widgets/page_header.dart';
import '../../widgets/progress_meter.dart';
import '../../widgets/stamp_chip.dart';
import '../counterparties/counterparties_screen.dart';
import 'project_detail_screen.dart';

/// مبلغ، دریافتی و مانده یک پروژه برای نمایش در فهرست.
typedef _ProjectAmounts = ({double amount, double received, double remaining});

enum _ProjectSort { newest, largestRemaining }

class ProjectsScreen extends StatefulWidget {
  /// اگر true باشد، فقط پروژه‌های مالی «در جریان» (نهایی‌نشده) نشان داده
  /// می‌شوند - این یک بعد کاملاً جدا از فیلتر وضعیت عملیاتی (kProjectStatuses)
  /// است؛ از داشبورد (ردیف «مانده تخمینی پروژه‌های در جریان») صدا زده می‌شود.
  final bool onlyOpenFinancially;
  const ProjectsScreen({super.key, this.onlyOpenFinancially = false});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> with Reloadable<ProjectsScreen> {
  final _db = DatabaseHelper.instance;
  final _metrics = FinancialMetricsService();
  List<ProjectModel> _projects = [];
  // تعداد پروژه‌ها به تفکیک وضعیت، پیش از اعمال فیلتر وضعیت (ولی پس از جستجو).
  Map<String, int> _statusCounts = {};
  int _totalCount = 0;
  Map<int, String> _counterpartyNames = {};
  Map<int, _ProjectAmounts> _amounts = {};
  bool _loading = true;
  String _query = '';
  String? _statusFilter;
  _ProjectSort _sort = _ProjectSort.newest;
  Timer? _searchDebounce;
  // نتیجه دیرتر-رسیده یک جستجوی قدیمی نباید روی نتیجه جستجوی جدید بنشیند.
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  Future<void> reload() => _load();

  /// جستجو با مکث کوتاه پس از آخرین حرف اجرا می‌شود، نه با هر حرف.
  void _onQueryChanged(String value) {
    _query = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() => _loading = true);
    final projects = await _db.getProjects(query: _query);
    final counterparties = await _db.getCounterparties(includeInactive: true);
    final names = {for (final c in counterparties) c.id!: c.name};

    // مبلغ/دریافتی/مانده هر پروژه - همه از محاسبات دسته‌ای موجود (تعداد ثابت
    // کوئری)، با همان تعریف‌هایی که بقیه برنامه استفاده می‌کند:
    // - پروژه در جریان: مبلغ مورد انتظار فعلی و مانده تخمینی (مثل فرم دریافت
    //   وجه و ردیف «پروژه‌های در جریان» داشبورد).
    // - پروژه نهایی‌شده: درآمد خالص و مانده طلب (مثل گزارش سود مشتریان).
    final expected = await _db.expectedAmountForOpenProjects();
    final estimatedRemaining = await _db.estimatedRemainingForOpenProjects();
    final snapshot = await _metrics.loadSnapshot();
    final amounts = <int, _ProjectAmounts>{};
    for (final p in projects) {
      final id = p.id!;
      final m = snapshot.metricsById[id];
      final received = m?.totalReceived ?? 0;
      if (p.isFinalized && m != null) {
        amounts[id] = (amount: m.netRevenue ?? 0, received: received, remaining: m.receivableBalance);
      } else {
        amounts[id] = (
          amount: expected[id] ?? p.agreedAmount,
          received: received,
          remaining: estimatedRemaining[id] ?? p.agreedAmount,
        );
      }
    }

    if (!mounted || token != _loadToken) return;
    final scope = widget.onlyOpenFinancially ? projects.where((p) => !p.isFinalized).toList() : projects;
    final counts = <String, int>{};
    for (final p in scope) {
      counts[p.status] = (counts[p.status] ?? 0) + 1;
    }
    setState(() {
      _totalCount = scope.length;
      _statusCounts = counts;
      _projects = _statusFilter == null ? scope : scope.where((p) => p.status == _statusFilter).toList();
      _counterpartyNames = names;
      _amounts = amounts;
      _loading = false;
    });
  }

  List<ProjectModel> get _sortedProjects {
    if (_sort == _ProjectSort.newest) return _projects;
    final sorted = [..._projects];
    // پروژه لغوشده مانده‌ای برای پیگیری ندارد؛ ته فهرست می‌رود.
    double remainingOf(ProjectModel p) =>
        p.status == kProjectStatusCancelled ? double.negativeInfinity : (_amounts[p.id]?.remaining ?? 0);
    sorted.sort((a, b) => remainingOf(b).compareTo(remainingOf(a)));
    return sorted;
  }

  void _setStatusFilter(String? status) {
    _statusFilter = status;
    _load();
  }

  Future<void> _openSortSheet() async {
    final picked = await showModalBottomSheet<_ProjectSort>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('مرتب‌سازی', style: AppTextStyles.blockHeading),
              ),
            ),
            for (final entry in const {
              _ProjectSort.newest: 'جدیدترین',
              _ProjectSort.largestRemaining: 'بیشترین مانده',
            }.entries)
              ListTile(
                title: Text(entry.value),
                trailing: entry.key == _sort ? const Icon(Icons.check, color: AppColors.brass) : null,
                onTap: () => Navigator.pop(ctx, entry.key),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  @override
  Widget build(BuildContext context) {
    final projects = _sortedProjects;
    return Scaffold(
      appBar: pageHeader(
        context,
        title: widget.onlyOpenFinancially ? 'پروژه‌ها · در جریان' : 'پروژه‌ها',
        showSettings: !widget.onlyOpenFinancially,
        actions: [
          HeaderIconButton(
            icon: Icons.people_alt_outlined,
            tooltip: 'طرف‌های حساب',
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const CounterpartiesScreen()));
              if (mounted) _load();
            },
          ),
        ],
      ),
      body: BlueprintGridBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'جستجوی عنوان پروژه یا نام مشتری',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: _onQueryChanged,
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                children: [
                  _FilterPill(
                    label: 'همه · ${pn(_totalCount)}',
                    selected: _statusFilter == null,
                    onTap: () => _setStatusFilter(null),
                  ),
                  for (final status in [
                    ...kProjectStatuses,
                    kProjectStatusFinalized,
                    kProjectStatusCancelled,
                  ])
                    if ((_statusCounts[status] ?? 0) > 0 || _statusFilter == status) ...[
                      const SizedBox(width: 8),
                      _FilterPill(
                        label: '$status · ${pn(_statusCounts[status] ?? 0)}',
                        selected: _statusFilter == status,
                        onTap: () => _setStatusFilter(status),
                      ),
                    ],
                ],
              ),
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 14),
                child: TextButton.icon(
                  onPressed: _openSortSheet,
                  icon: const Icon(Icons.swap_vert, size: 18, color: AppColors.textSecondary),
                  label: Text(
                    'مرتب‌سازی: ${_sort == _ProjectSort.newest ? 'جدیدترین' : 'بیشترین مانده'}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                ),
              ),
            ),
            SizedBox(
              height: 2,
              child: (_loading && projects.isNotEmpty) ? const LinearProgressIndicator(minHeight: 2) : null,
            ),
            Expanded(
              child: (_loading && projects.isEmpty)
                  ? const Center(child: CircularProgressIndicator())
                  : projects.isEmpty
                  ? Center(
                      child: Text(
                        (_query.isNotEmpty || _statusFilter != null || widget.onlyOpenFinancially)
                            ? 'نتیجه‌ای برای این جستجو/فیلتر یافت نشد'
                            : 'هنوز پروژه‌ای ثبت نشده است',
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                        itemCount: projects.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) {
                          final p = projects[i];
                          return _ProjectCard(
                            project: p,
                            counterpartyName: _counterpartyNames[p.counterpartyId],
                            amounts: _amounts[p.id],
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p)),
                              );
                              if (mounted) _load();
                            },
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterPill({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? AppColors.brass.withValues(alpha: 0.14) : AppColors.surface,
        shape: StadiumBorder(
          side: BorderSide(color: selected ? AppColors.brass : AppColors.gridLine, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
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

class _ProjectCard extends StatelessWidget {
  final ProjectModel project;
  final String? counterpartyName;
  final _ProjectAmounts? amounts;
  final VoidCallback onTap;

  const _ProjectCard({
    required this.project,
    required this.counterpartyName,
    required this.amounts,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = project;
    final a = amounts;
    final cancelled = p.status == kProjectStatusCancelled;
    final settled = p.isFinalized && a != null && a.remaining <= 0 && !cancelled;
    final progress = (a == null || a.amount <= 0) ? 0.0 : a.received / a.amount;
    final subtitle = [
      counterpartyName ?? '—',
      if (p.projectTypes.isNotEmpty) p.projectTypes.join('، '),
    ].join(' · ');

    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.gridLine),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          p.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  // وضعیت قطعی (نهایی‌شده) مُهر می‌خورد؛ وضعیت‌های عملیاتی
                  // برچسب خنثی می‌گیرند تا مهر معنای خودش را حفظ کند.
                  p.isFinalized ? const StampChip('نهایی‌شده', fontSize: 11) : StatusChip(p.status),
                ],
              ),
              if (a != null) ...[
                const SizedBox(height: 10),
                if (!cancelled)
                  ProgressMeter(
                    value: progress,
                    color: settled ? AppColors.positive : AppColors.brass,
                    semanticLabel: settled
                        ? 'کامل دریافت شده'
                        : '${pn((progress.clamp(0.0, 1.0) * 100).round())} درصد دریافت شده',
                  ),
                if (!cancelled) const SizedBox(height: 10),
                if (cancelled)
                  Text('مبلغ ${formatMoney(a.amount, withSuffix: false)}', style: AppTextStyles.caption)
                else
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    runSpacing: 4,
                    children: [
                      Text(
                        'دریافتی ${formatMoney(a.received, withSuffix: false)} از ${formatMoney(a.amount, withSuffix: false)}',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                      ),
                      if (settled)
                        const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline, size: 14, color: AppColors.positive),
                            SizedBox(width: 4),
                            Text(
                              'تسویه‌شده',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.positive,
                              ),
                            ),
                          ],
                        )
                      else
                        Text.rich(
                          TextSpan(
                            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                            children: [
                              TextSpan(text: '${p.isFinalized ? 'مانده طلب' : 'مانده تخمینی'} '),
                              TextSpan(
                                text: formatMoney(a.remaining, withSuffix: false),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
