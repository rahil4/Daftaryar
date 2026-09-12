import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/financial_reports.dart';
import '../../services/financial_reporting_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/stat_card.dart';
import '../counterparties/counterparty_detail_screen.dart';

/// صفحه مستقل «طلب‌ها» - فهرست مشتریانی که از آن‌ها طلبکاریم، به تفکیک
/// مشتری. دو نوع طلب با هم دیده می‌شوند - همان دو مفهومی که کارت «طلب و
/// پیش‌دریافت» داشبورد و هشدار «مطالبات باز» به آن اشاره می‌کنند:
/// - مانده طلب رسمی (AR روی پروژه‌های نهایی‌شده) - قطعی، از Ledger.
/// - مانده تخمینی (پروژه‌های هنوز نهایی‌نشده) - غیررسمی، صرفاً برآورد
///   جاری منهای دریافتی تاکنون.
/// فهرست همیشه بر مبنای «فوریت پیگیری» (مجموع این دو) مرتب می‌شود. این
/// صفحه جایگزین صفحه قدیمی‌تر «طلب‌های باز» است که قبلاً حذف و داخل تب
/// «سود مشتریان» ادغام شده بود؛ اینجا دوباره یک مقصد مستقل و صریح برایش
/// ساخته می‌شود تا هشدار «مطالبات باز» داشبورد بتواند مستقیماً به آن
/// لینک شود.
class ReceivablesScreen extends StatefulWidget {
  const ReceivablesScreen({super.key});

  @override
  State<ReceivablesScreen> createState() => _ReceivablesScreenState();
}

class _ReceivablesScreenState extends State<ReceivablesScreen> {
  final _db = DatabaseHelper.instance;
  final _reporting = FinancialReportingService();
  List<CustomerFinancialReport> _reports = [];
  Map<int, String> _names = {};
  Map<int, double> _estimatedByCustomer = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final reports = await _reporting.getAllCustomerReports();
    final counterparties = await _db.getCounterparties(includeInactive: true);
    final estimatedByProject = await _db.estimatedRemainingForOpenProjects();
    final projects = await _db.getProjects();
    final estimatedByCustomer = <int, double>{};
    for (final p in projects) {
      final estimated = estimatedByProject[p.id];
      if (estimated != null && estimated > 0) {
        estimatedByCustomer[p.counterpartyId] = (estimatedByCustomer[p.counterpartyId] ?? 0) + estimated;
      }
    }
    final filtered = reports.where((r) {
      final estimated = estimatedByCustomer[r.counterpartyId] ?? 0;
      return r.receivableBalance > 0 || estimated > 0;
    }).toList()
      ..sort((a, b) {
        final ua = a.receivableBalance + (estimatedByCustomer[a.counterpartyId] ?? 0);
        final ub = b.receivableBalance + (estimatedByCustomer[b.counterpartyId] ?? 0);
        return ub.compareTo(ua);
      });
    if (!mounted) return;
    setState(() {
      _reports = filtered;
      _names = {for (final c in counterparties) if (c.id != null) c.id!: c.name};
      _estimatedByCustomer = estimatedByCustomer;
      _loading = false;
    });
  }

  Future<void> _openCustomer(int counterpartyId) async {
    final counterparty = await _db.getCounterparty(counterpartyId);
    if (counterparty == null || !mounted) return;
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => CounterpartyDetailScreen(counterparty: counterparty)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final totalReceivable = _reports.fold<double>(0, (s, r) => s + r.receivableBalance);
    final totalEstimated = _estimatedByCustomer.values.fold<double>(0, (s, v) => s + v);
    return Scaffold(
      appBar: AppBar(title: const Text('طلب‌ها')),
      body: BlueprintGridBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: StatCard(
                            title: 'مطالبات',
                            value: formatMoneyCompact(totalReceivable),
                            icon: Icons.receipt_long_outlined,
                            color: AppColors.negative,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: StatCard(
                            title: 'مانده تخمینی',
                            value: formatMoneyCompact(totalEstimated),
                            icon: Icons.hourglass_bottom_outlined,
                            color: AppColors.brass,
                          ),
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'مطالبات: مانده طلب قطعی روی پروژه‌های نهایی‌شده.'
                        ' مانده تخمینی: برآورد غیررسمی پروژه‌های هنوز در جریان.'
                        ' فهرست بر مبنای فوریت پیگیری (مجموع این دو) مرتب شده.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                    ),
                    if (_reports.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('در حال حاضر هیچ طلب بازی وجود ندارد.',
                            textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                      )
                    else
                      ..._reports.map((r) {
                        final name = _names[r.counterpartyId] ?? 'نامشخص';
                        final estimated = _estimatedByCustomer[r.counterpartyId] ?? 0;
                        final lines = <String>[
                          if (r.receivableBalance > 0)
                            'مانده طلب: ${formatMoney(r.receivableBalance, withSuffix: false)}',
                          if (estimated > 0)
                            'در انتظار (تخمینی): ${formatMoney(estimated, withSuffix: false)}',
                        ];
                        return Card(
                          child: ListTile(
                            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text(lines.join('  ·  ')),
                            trailing: const Icon(Icons.chevron_left),
                            onTap: () => _openCustomer(r.counterpartyId),
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
