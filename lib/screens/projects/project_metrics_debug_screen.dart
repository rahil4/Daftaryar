import 'package:flutter/material.dart';

import '../../models/financial_metrics.dart';
import '../../services/financial_metrics_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// نمایش Debug/Verification ساده شاخص‌های مالی محاسبه‌شده توسط
/// FinancialMetricsService - فقط برای تأیید صحت محاسبات، نه یک Dashboard.
class ProjectMetricsDebugScreen extends StatefulWidget {
  final int projectId;
  const ProjectMetricsDebugScreen({super.key, required this.projectId});

  @override
  State<ProjectMetricsDebugScreen> createState() => _ProjectMetricsDebugScreenState();
}

class _ProjectMetricsDebugScreenState extends State<ProjectMetricsDebugScreen> {
  final _service = FinancialMetricsService();
  ProjectFinancialMetrics? _metrics;
  ProjectReconciliation? _reconciliation;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final metrics = await _service.getProjectMetrics(widget.projectId);
    final reconciliation = await _service.reconcileProject(widget.projectId);
    setState(() {
      _metrics = metrics;
      _reconciliation = reconciliation;
      _loading = false;
    });
  }

  String _fmt(double? v) => v == null ? '—' : formatMoney(v);
  String _fmtPct(double? v) => v == null ? '—' : '${v.toStringAsFixed(2)}٪';

  @override
  Widget build(BuildContext context) {
    final m = _metrics;
    final r = _reconciliation;
    return Scaffold(
      appBar: AppBar(title: const Text('Debug: شاخص‌های مالی (Metrics Layer)')),
      body: _loading || m == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _section('برآورد و تغییرات قیمت'),
                _row('برآورد اولیه', _fmt(m.initialEstimate)),
                _row('افزایش‌ها', _fmt(m.priceAdditions)),
                _row('کاهش‌ها', _fmt(m.priceReductions)),
                _row('خالص تغییرات', _fmt(m.netPriceChanges)),
                _section('Finalization'),
                _row('مبلغ نهایی اصلی', _fmt(m.finalAmount)),
                _row('اصلاحات پس از نهایی‌سازی', _fmt(m.finalAdjustments)),
                _row('مبلغ نهایی مؤثر', _fmt(m.effectiveFinalAmount)),
                _row('افزایش نسبت به برآورد', _fmt(m.priceIncreaseAmount)),
                _row('نرخ افزایش', _fmtPct(m.priceIncreaseRate)),
                _section('درآمد'),
                _row('درآمد ناخالص', _fmt(m.grossRevenue)),
                _row('تخفیف', _fmt(m.discountAmount)),
                _row('درآمد خالص', _fmt(m.netRevenue)),
                _section('نقد و مانده‌ها'),
                _row('مجموع دریافتی واقعی', _fmt(m.totalReceived)),
                _row('مانده پیش‌دریافت', _fmt(m.advanceBalance)),
                _row('مانده طلب', _fmt(m.receivableBalance)),
                _row('بستانکاری مشتری', _fmt(m.customerCredit)),
                _section('سودآوری'),
                _row('هزینه مستقیم', _fmt(m.directProjectCost)),
                _row('سود ناخالص پروژه', _fmt(m.projectContribution)),
                _row('حاشیه سود', _fmtPct(m.contributionMargin)),
                _row('نرخ وصول', _fmtPct(m.collectionRate)),
                _row('نسبت مانده به درآمد', _fmtPct(m.outstandingRatio)),
                _section('وضعیت'),
                _row('نهایی‌شده', m.isFinalized ? 'بله' : 'خیر'),
                _row('تسویه‌شده', m.isSettled ? 'بله' : 'خیر'),
                if (r != null) ...[
                  _section('Reconciliation (بررسی تطبیق)'),
                  _row('وضعیت', r.status),
                  _row('درآمد محاسبه‌شده', _fmt(r.calculatedGrossRevenue)),
                  _row('مانده واقعی Ledger', _fmt(r.ledgerRevenueBalance)),
                  if (r.note != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(r.note!,
                          style: const TextStyle(fontSize: 12, color: AppColors.negative)),
                    ),
                ],
              ],
            ),
    );
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.brass)),
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
