import 'package:flutter/material.dart';

import '../../../models/financial_reports.dart';
import '../../../models/management_dashboard_data.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/formatters.dart';
import 'kpi_card.dart';

String _fmt(double? v, {bool pct = false}) {
  if (v == null) return '—';
  return pct ? '${v.toStringAsFixed(1)}٪' : formatMoney(v);
}

Widget _sectionTitle(String title) {
  return Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 8),
    child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
  );
}

/// بخش خلاصه KPIهای اصلی
class KpiOverviewSection extends StatelessWidget {
  final ManagementDashboardData data;
  const KpiOverviewSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('سودآوری'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.7,
          children: [
            KpiCard(title: 'درآمد خالص', kpi: data.netRevenue),
            KpiCard(title: 'هزینه مستقیم پروژه', kpi: data.directProjectCost),
            KpiCard(title: 'سود ناخالص پروژه‌ها', kpi: data.projectContribution),
            KpiCard(title: 'سربار پروژه‌ها', kpi: data.projectOverhead),
            KpiCard(title: 'هزینه‌های دفتر', kpi: data.officeExpense),
            KpiCard(title: 'نتیجه عملیاتی', kpi: data.operatingResult),
            KpiCard(title: 'حاشیه عملیاتی', kpi: data.operatingMargin, isPercentage: true),
          ],
        ),
      ],
    );
  }
}

/// بخش وضعیت نقدینگی - کاملاً جدا از سودآوری
class CashPositionSection extends StatelessWidget {
  final ManagementDashboardData data;
  const CashPositionSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final netChange = data.closingCash - data.openingCash;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('نقدینگی'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _row('موجودی ابتدای دوره', _fmt(data.openingCash)),
                _row('دریافتی از مشتریان', _fmt(data.customerReceipts)),
                _row('سایر دریافتی‌ها', _fmt(data.otherCashInflows)),
                _row('پرداختی پروژه‌ها', '- ${_fmt(data.projectPayments)}'),
                _row('پرداختی سربار', '- ${_fmt(data.projectOverheadPayments)}'),
                _row('پرداختی دفتر', '- ${_fmt(data.officePayments)}'),
                _row('سایر پرداختی‌ها', '- ${_fmt(data.otherCashOutflows)}'),
                const Divider(),
                _row('خالص تغییر نقدینگی', _fmt(netChange), bold: true),
                _row('موجودی پایان دوره', _fmt(data.closingCash), bold: true),
                const SizedBox(height: 8),
                _reconciliationChip(data.cashReconciles),
              ],
            ),
          ),
        ),
        if (data.bankBalances.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('موجودی فعلی هر حساب (مستقل از بازه انتخابی)',
              style: const TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: Column(
                children: [
                  for (final b in data.bankBalances) _row(b.name, _fmt(b.balance)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// بخش مطالبات و پیش‌دریافت/بستانکاری - این سه مفهوم هرگز یکی نمی‌شوند
class ReceivablesSection extends StatelessWidget {
  final ManagementDashboardData data;
  const ReceivablesSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final m = data.receivableMovement;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('مطالبات و وصول'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.9,
          children: [
            _miniStat('مانده مطالبات (AR) - پایان بازه', _fmt(data.receivableBalance)),
            _miniStat('پیش‌دریافت مشتریان', _fmt(data.advanceBalance)),
            _miniStat('بستانکاری مشتری', _fmt(data.customerCreditBalance)),
            _miniStat('نسبت دریافت نقدی به درآمد دوره', _fmt(data.periodReceiptToRevenueRatio, pct: true)),
            _miniStat('نرخ وصول مطالبات این بازه', _fmt(data.periodArCollectionRate, pct: true)),
            _miniStat('نسبت مانده مطالبات به درآمد دوره', _fmt(data.closingReceivableToPeriodRevenueRatio, pct: true)),
          ],
        ),
        const SizedBox(height: 10),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('حرکت مطالبات این بازه', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                _row('مانده ابتدای دوره', _fmt(m['opening'])),
                _row('طلب جدید', _fmt(m['newReceivables'])),
                _row('وصولی', '- ${_fmt(m['collections'])}'),
                _row('اصلاحات (تخفیف/اصلاح)', '- ${_fmt(m['adjustments'])}'),
                if ((m['other'] ?? 0) != 0) _row('سایر', _fmt(m['other'])),
                const Divider(),
                _row('مانده پایان دوره', _fmt(m['closing']), bold: true),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// بخش وضعیت Finalization/Settlement
class SettlementSection extends StatelessWidget {
  final ManagementDashboardData data;
  const SettlementSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('وضعیت فعلی پروژه‌ها (مستقل از بازه انتخابی)',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: _miniStat('نهایی‌شده', pn(data.finalizedProjectsCount))),
            const SizedBox(width: 8),
            Expanded(child: _miniStat('تسویه‌شده', pn(data.settledProjectsCount))),
            const SizedBox(width: 8),
            Expanded(child: _miniStat('تسویه‌نشده', pn(data.unsettledProjectsCount))),
          ],
        ),
      ],
    );
  }
}

/// بخش عملکرد پروژه‌ها: بهترین/بدترین/پرریسک/زیان‌ده
class ProjectPerformanceSection extends StatelessWidget {
  final ManagementDashboardData data;
  const ProjectPerformanceSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('عملکرد پروژه‌ها'),
        if (data.allProjects.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('هیچ پروژه‌ای برای تحلیل موجود نیست.',
                style: TextStyle(color: AppColors.textSecondary)),
          )
        else ...[
          _projectGroup('بهترین پروژه‌ها', data.bestProjects, AppColors.positive),
          _projectGroup('بدترین پروژه‌ها', data.worstProjects, AppColors.negative),
          _projectGroup('پروژه‌های دارای مانده طلب', data.outstandingProjects, AppColors.brass,
              showAr: true),
          _projectGroup('پروژه‌های زیان‌ده', data.lossProjects, AppColors.negative),
        ],
      ],
    );
  }

  Widget _projectGroup(String title, List<ProjectFinancialReport> projects, Color color,
      {bool showAr = false}) {
    if (projects.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text('$title: موردی یافت نشد', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 4),
          ...projects.take(5).map((p) => Card(
                child: ListTile(
                  dense: true,
                  title: Text(p.projectName),
                  subtitle: Text(showAr
                      ? 'مانده طلب: ${_fmt(p.receivableBalance)}'
                      : 'سود ناخالص: ${_fmt(p.projectContribution)} · حاشیه: ${_fmt(p.contributionMargin, pct: true)}'),
                ),
              )),
        ],
      ),
    );
  }
}

/// بخش تحلیل مشتریان
class CustomerPerformanceSection extends StatelessWidget {
  final ManagementDashboardData data;
  const CustomerPerformanceSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('تحلیل مشتریان'),
        _miniStat('سهم ۵ مشتری برتر از درآمد دفتر', _fmt(data.top5CustomersRevenueShare, pct: true)),
        const SizedBox(height: 8),
        if (data.customers.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('هیچ مشتری‌ای یافت نشد.', style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ...data.customers.take(10).map((c) => Card(
                child: ListTile(
                  dense: true,
                  title: Text('طرف حساب #${c.counterpartyId}'),
                  subtitle: Text(
                      'درآمد خالص: ${_fmt(c.netRevenue)} · پروژه‌ها: ${pn(c.projectCount)} · طلب: ${_fmt(c.receivableBalance)}'),
                ),
              )),
      ],
    );
  }
}

/// بخش تحلیل قیمت‌گذاری
class PricingSection extends StatelessWidget {
  final ManagementDashboardData data;
  const PricingSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('تحلیل قیمت‌گذاری'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _row('مجموع برآورد اولیه', _fmt(data.totalInitialEstimates)),
                _row('مجموع مبلغ نهایی', _fmt(data.totalFinalAmounts)),
                _row('مجموع افزایش‌ها', _fmt(data.totalAdditions)),
                _row('مجموع کاهش‌ها', _fmt(data.totalReductions)),
                _row('میانگین نرخ افزایش قیمت', _fmt(data.averagePriceIncreaseRate, pct: true)),
              ],
            ),
          ),
        ),
        _sectionTitle('تخفیف'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _row('مجموع تخفیف', _fmt(data.totalDiscount)),
                _row('نسبت تخفیف به درآمد ناخالص', _fmt(data.discountToGrossRevenueRatio, pct: true)),
              ],
            ),
          ),
        ),
        _sectionTitle('اصلاحات پس از نهایی‌سازی'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _row('اصلاحات مثبت', _fmt(data.totalPositiveAdjustments)),
                _row('اصلاحات منفی', '- ${_fmt(data.totalNegativeAdjustments)}'),
                _row('خالص اصلاحات', _fmt(data.netAdjustments), bold: true),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// بخش هشدارهای مدیریتی
class AlertsSection extends StatelessWidget {
  final ManagementDashboardData data;
  const AlertsSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.alerts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('هشدارهای مدیریتی'),
        ...data.alerts.map((a) {
          final color = a.severity == ManagementAlertSeverity.error
              ? AppColors.negative
              : (a.severity == ManagementAlertSeverity.warning ? AppColors.brass : AppColors.textSecondary);
          return Card(
            child: ListTile(
              leading: Icon(Icons.warning_amber_rounded, color: color),
              title: Text(a.title, style: TextStyle(color: color, fontWeight: FontWeight.w700)),
              subtitle: Text(a.message),
            ),
          );
        }),
      ],
    );
  }
}

/// بخش تشخیص سلامت داده مالی - هیچ‌وقت هشدارها را پنهان نمی‌کند
class DiagnosticsSection extends StatelessWidget {
  final ManagementDashboardData data;
  const DiagnosticsSection({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data.diagnostics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('تشخیص سلامت داده مالی'),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _row('ناسازگاری تطبیق درآمد', pn(d.revenueLedgerMismatchCount)),
                _row('مانده منفی طلب', pn(d.negativeARCount)),
                _row('مانده منفی پیش‌دریافت', pn(d.negativeAdvanceCount)),
                _row('مانده منفی بستانکاری مشتری', pn(d.negativeCustomerCreditCount)),
                _row('خطای تطبیق نقدی', pn(d.cashReconciliationErrors)),
                const SizedBox(height: 8),
                if (!d.hasIssues)
                  const Text('هیچ ناسازگاری‌ای یافت نشد.',
                      style: TextStyle(color: AppColors.positive, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Widget _reconciliationChip(bool ok) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: (ok ? AppColors.positive : AppColors.negative).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: ok ? AppColors.positive : AppColors.negative),
    ),
    child: Text(
      ok ? 'تطبیق جریان نقدی: OK' : 'تطبیق جریان نقدی: خطا (ERROR)',
      style: TextStyle(
          color: ok ? AppColors.positive : AppColors.negative, fontWeight: FontWeight.w700, fontSize: 12),
    ),
  );
}

Widget _miniStat(String label, String value) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        ],
      ),
    ),
  );
}

Widget _row(String label, String value, {bool bold = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Text(value, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: 13)),
      ],
    ),
  );
}
