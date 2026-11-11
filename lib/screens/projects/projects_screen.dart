import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/project.dart';
import '../../services/financial_metrics_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../utils/reloadable.dart';
import 'project_detail_screen.dart';
import '../counterparties/counterparties_screen.dart';

class ProjectsScreen extends StatefulWidget {
  /// اگر true باشد، فقط پروژه‌های مالی «در جریان» (نهایی‌نشده) نشان داده
  /// می‌شوند - این یک بعد کاملاً جدا از فیلتر وضعیت عملیاتی (kProjectStatuses)
  /// است؛ از داشبورد (کارت «پروژه در جریان») صدا زده می‌شود.
  final bool onlyOpenFinancially;
  const ProjectsScreen({super.key, this.onlyOpenFinancially = false});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> with Reloadable<ProjectsScreen> {
  final _db = DatabaseHelper.instance;
  final _metrics = FinancialMetricsService();
  List<ProjectModel> _projects = [];
  Map<int, String> _counterpartyNames = {};
  // مبلغ و مانده هر پروژه برای نمایش در فهرست (رجوع به _load).
  Map<int, ({double amount, double remaining})> _amounts = {};
  bool _loading = true;
  String _query = '';
  String? _statusFilter;
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

    // مبلغ/مانده هر پروژه - همه از محاسبات دسته‌ای موجود (تعداد ثابت کوئری)،
    // با همان تعریف‌هایی که بقیه برنامه استفاده می‌کند:
    // - پروژه در جریان: مبلغ مورد انتظار فعلی و مانده تخمینی (مثل فرم دریافت
    //   وجه و کارت «پروژه در جریان» داشبورد).
    // - پروژه نهایی‌شده: درآمد خالص و مانده طلب (مثل گزارش سود مشتریان).
    final expected = await _db.expectedAmountForOpenProjects();
    final estimatedRemaining = await _db.estimatedRemainingForOpenProjects();
    final snapshot = await _metrics.loadSnapshot();
    final amounts = <int, ({double amount, double remaining})>{};
    for (final p in projects) {
      final id = p.id!;
      final m = snapshot.metricsById[id];
      if (p.isFinalized && m != null) {
        amounts[id] = (amount: m.netRevenue ?? 0, remaining: m.receivableBalance);
      } else {
        amounts[id] = (
          amount: expected[id] ?? p.agreedAmount,
          remaining: estimatedRemaining[id] ?? p.agreedAmount,
        );
      }
    }

    if (!mounted || token != _loadToken) return;
    setState(() {
      var filtered = _statusFilter == null
          ? projects
          : projects.where((p) => p.status == _statusFilter).toList();
      if (widget.onlyOpenFinancially) {
        filtered = filtered.where((p) => !p.isFinalized).toList();
      }
      _projects = filtered;
      _counterpartyNames = names;
      _amounts = amounts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onlyOpenFinancially ? 'پروژه‌ها · در جریان' : 'پروژه‌ها'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'اشخاص',
            onPressed: () async {
              await Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const CounterpartiesScreen()));
              _load();
            },
          ),
        ],
      ),
      body: BlueprintGridBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'جستجوی عنوان پروژه یا نام مشتری...',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: _onQueryChanged,
              ),
            ),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: const Text('همه'),
                      selected: _statusFilter == null,
                      onSelected: (_) {
                        _statusFilter = null;
                        _load();
                      },
                    ),
                  ),
                  ...kProjectStatuses.map((s) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(s),
                          selected: _statusFilter == s,
                          onSelected: (_) {
                            _statusFilter = s;
                            _load();
                          },
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _projects.isEmpty
                      ? Center(
                          child: Text(
                              (_query.isNotEmpty ||
                                      _statusFilter != null ||
                                      widget.onlyOpenFinancially)
                                  ? 'نتیجه‌ای برای این جستجو/فیلتر یافت نشد'
                                  : 'هنوز پروژه‌ای ثبت نشده است',
                              style: const TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _projects.length,
                          itemBuilder: (ctx, i) {
                            final p = _projects[i];
                            final amounts = _amounts[p.id];
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.work_outline, color: AppColors.brass),
                                title: Text(p.title),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        '${_counterpartyNames[p.counterpartyId] ?? '—'} · ${p.projectTypes.join('، ')}'),
                                    if (amounts != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text(
                                          // پروژه لغوشده مانده‌ای برای پیگیری ندارد.
                                          p.status == kProjectStatusCancelled
                                              ? 'مبلغ ${formatMoney(amounts.amount, withSuffix: false)}'
                                              : 'مبلغ ${formatMoney(amounts.amount, withSuffix: false)}'
                                                  ' · ${p.isFinalized ? 'مانده طلب' : 'مانده تخمینی'} '
                                                  '${formatMoney(amounts.remaining, withSuffix: false)}',
                                          style: AppTextStyles.caption,
                                        ),
                                      ),
                                  ],
                                ),
                                isThreeLine: amounts != null,
                                trailing: _StatusBadge(status: p.status),
                                onTap: () async {
                                  await Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p)));
                                  _load();
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color _color() {
    switch (status) {
      case 'تکمیل شده':
        return AppColors.positive;
      case 'متوقف شده':
        return AppColors.negative;
      default:
        return AppColors.brass;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color().withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color()),
      ),
      child: Text(status, style: TextStyle(color: _color(), fontSize: 10)),
    );
  }
}
