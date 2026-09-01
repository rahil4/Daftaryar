import 'package:flutter/material.dart';

import '../../models/financial_reports.dart';
import '../../models/project_economics.dart';
import '../../services/project_economics_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// نمایش ساده تحلیل اقتصادی یک پروژه - چرا سودده/زیان‌ده شده - و عوامل
/// قابل‌مشاهده مرتبط (بدون ادعای علّی قطعی).
class ProjectEconomicsScreen extends StatefulWidget {
  final int projectId;
  final bool embedded;
  const ProjectEconomicsScreen({super.key, required this.projectId, this.embedded = false});

  @override
  State<ProjectEconomicsScreen> createState() => _ProjectEconomicsScreenState();
}

class _ProjectEconomicsScreenState extends State<ProjectEconomicsScreen> {
  final _service = ProjectEconomicsService();
  ProjectEconomicAnalysis? _analysis;
  ProjectProfitabilityFactors? _factors;
  ProjectBenchmark? _benchmark;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final analysis = await _service.getProjectEconomicAnalysis(widget.projectId);
    final factors = await _service.getProjectProfitabilityFactors(widget.projectId);
    final benchmark = await _service.getBenchmark();
    setState(() {
      _analysis = analysis;
      _factors = factors;
      _benchmark = benchmark;
      _loading = false;
    });
  }

  String _fmt(double? v, {bool pct = false}) {
    if (v == null) return '—';
    return pct ? '${v.toStringAsFixed(1)}٪' : formatMoney(v);
  }

  String _statusLabel(ProjectProfitabilityStatus s) {
    switch (s) {
      case ProjectProfitabilityStatus.loss:
        return 'زیان‌ده';
      case ProjectProfitabilityStatus.lowMargin:
        return 'حاشیه پایین';
      case ProjectProfitabilityStatus.normalMargin:
        return 'حاشیه متعارف';
      case ProjectProfitabilityStatus.highMargin:
        return 'حاشیه بالا';
      case ProjectProfitabilityStatus.unknown:
        return 'نامشخص';
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = _analysis;
    final f = _factors;
    final b = _benchmark;
    final content = _loading || a == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.brass.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_statusLabel(a.profitabilityStatus),
                    style: const TextStyle(color: AppColors.brass, fontWeight: FontWeight.w800)),
              ),
              _section('بازبینی قیمت'),
              _row('برآورد اولیه', _fmt(a.initialEstimate)),
              _row('مبلغ نهایی', _fmt(a.finalAmount)),
              _row('واریانس قیمت (نسبت به برآورد)', _fmt(a.priceVarianceAmount)),
              _row('نرخ واریانس قیمت', _fmt(a.priceVarianceRate, pct: true)),
              _section('درآمد و هزینه'),
              _row('درآمد خالص', _fmt(a.netRevenue)),
              _row('نرخ تخفیف', _fmt(a.discountRate, pct: true)),
              _row('هزینه مستقیم', _fmt(a.directProjectCost)),
              _row('نسبت هزینه مستقیم به درآمد', _fmt(a.directCostRatio, pct: true)),
              _row('بازده هر واحد هزینه مستقیم', a.revenuePerCostUnit == null ? '—' : a.revenuePerCostUnit!.toStringAsFixed(2)),
              _section('سودآوری'),
              _row('سود ناخالص پروژه', _fmt(a.projectContribution)),
              _row('حاشیه سود', _fmt(a.contributionMargin, pct: true)),
              _section('وصول'),
              _row('نرخ وصول', _fmt(a.collectionRate, pct: true)),
              _row('شکاف وصول (درآمد - دریافتی)', _fmt(a.collectionGap)),
              _row('مانده طلب باقی‌مانده', _fmt(a.remainingReceivable)),
              if (f != null && f.notableFactors.isNotEmpty) ...[
                _section('عوامل قابل توجه (فقط گزارش شاخص، نه ادعای علّی)'),
                ...f.notableFactors.map((n) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 16, color: AppColors.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(child: Text(n, style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    )),
              ],
              if (b != null) ...[
                _section('مقایسه با میانگین پروژه‌های نهایی‌شده (${pn(b.finalizedProjectCount)} پروژه)'),
                _row('میانگین درآمد خالص', _fmt(b.averageNetRevenue)),
                _row('میانگین سود ناخالص', _fmt(b.averageContribution)),
                _row('میانگین حاشیه سود', _fmt(b.averageContributionMargin, pct: true)),
                _row('میانگین نرخ تخفیف', _fmt(b.averageDiscountRate, pct: true)),
              ],
            ],
          );

    if (widget.embedded) return content;

    return Scaffold(
      appBar: AppBar(title: const Text('تحلیل اقتصادی پروژه')),
      body: content,
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brass, fontSize: 13)),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }
}
