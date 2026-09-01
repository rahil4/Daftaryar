import '../db/database_helper.dart';
import '../models/financial_reports.dart';
import '../models/management_dashboard_data.dart';
import '../utils/dashboard_period.dart';
import 'financial_metrics_service.dart';
import 'financial_reporting_service.dart';

/// لایه Orchestration داشبورد مدیریتی. این سرویس هیچ محاسبه Ledger جدیدی
/// انجام نمی‌دهد و هیچ Journal نمی‌سازد؛ فقط داده‌های FinancialReportingService
/// و FinancialMetricsService موجود را برای نمایش مدیریتی ترکیب می‌کند.
///
/// زنجیره: ManagementDashboardService → FinancialReportingService →
/// FinancialMetricsService → DatabaseHelper/Ledger.
class ManagementDashboardService {
  final DatabaseHelper _db;
  final FinancialMetricsService _metrics;
  final FinancialReportingService _reporting;

  ManagementDashboardService({DatabaseHelper? db, FinancialMetricsService? metrics, FinancialReportingService? reporting})
      : _db = db ?? DatabaseHelper.instance,
        _metrics = metrics ?? FinancialMetricsService(db),
        _reporting = reporting ?? FinancialReportingService(db: db, metrics: metrics);

  Future<ManagementDashboardData> buildDashboard({
    required DashboardPeriodPreset preset,
    String? customFrom,
    String? customTo,
    bool includeComparison = true,
    bool includeTrend = true,
  }) async {
    final fy = await _db.getFiscalYearStart();
    final range = DashboardPeriodResolver.resolve(
      preset,
      customFrom: customFrom,
      customTo: customTo,
      fiscalYearStartMonth: fy['month']!,
      fiscalYearStartDay: fy['day']!,
    );
    final previousRange =
        includeComparison ? DashboardPeriodResolver.previousPeriodOf(range) : null;

    final period = await _reporting.getPeriodReport(fromDate: range.fromDate, toDate: range.toDate);
    final previousPeriod = previousRange != null
        ? await _reporting.getPeriodReport(fromDate: previousRange.fromDate, toDate: previousRange.toDate)
        : null;
    // موجودی فعلی هر حساب نقدی/بانکی - وضعیت فعلی (Current State)، مستقل
    // از بازه انتخابی، دقیقاً مثل closingCash کل.
    final bankBalanceRows = await _db.bankBalances();
    final bankBalances = bankBalanceRows
        .map((row) => BankBalanceEntry(name: row['name'] as String, balance: row['balance'] as double))
        .toList();

    KpiValue kpi(double current, double? previous) {
      final growth =
          (previous != null && previous != 0) ? ((current - previous) / previous) * 100 : null;
      return KpiValue(value: current, previousValue: previous, growthRate: growth);
    }

    KpiValue kpiNullable(double? current, double? previous) {
      if (current == null) return KpiValue(value: null);
      return kpi(current, previous);
    }

    // ---------- پروژه‌ها (Lifetime - مستقل از Period انتخاب‌شده) ----------
    final allProjectReports = await _reporting.getProjectReports();
    final worst = _reporting.getWorstProjects(allProjectReports, ProjectReportSort.contribution);
    final best = _reporting.getBestProjects(allProjectReports, ProjectReportSort.contribution);
    final outstanding = allProjectReports.where((p) => p.receivableBalance > 0).toList()
      ..sort((a, b) => b.receivableBalance.compareTo(a.receivableBalance));
    final lossProjects =
        allProjectReports.where((p) => p.profitabilityStatus == ProjectProfitabilityStatus.loss).toList();

    int finalizedCount = 0, settledCount = 0;
    for (final p in allProjectReports) {
      if (p.isFinalized) finalizedCount++;
      if (p.isSettled) settledCount++;
    }
    final unsettledCount = finalizedCount - settledCount;

    // ---------- مشتریان ----------
    final customers = await _reporting.getAllCustomerReports(sortBy: CustomerReportSort.netRevenue);
    final top5Share = await _reporting.getTopCustomersRevenueShare(5);

    // ---------- قیمت‌گذاری و اصلاحات (جمع روی پروژه‌های Finalized، Lifetime) ----------
    double totalInitial = 0, totalFinal = 0, totalAdditions = 0, totalReductions = 0;
    double totalPositiveAdj = 0, totalNegativeAdj = 0;
    final priceIncreaseRates = <double>[];
    for (final p in allProjectReports) {
      totalInitial += p.initialEstimate;
      if (p.isFinalized) {
        totalFinal += p.finalAmount ?? 0;
        if (p.priceIncreaseRate != null) priceIncreaseRates.add(p.priceIncreaseRate!);
      }
      final m = await _metrics.getProjectMetrics(p.projectId);
      totalAdditions += m.priceAdditions;
      totalReductions += m.priceReductions;

      final adj = await _reporting.getAdjustmentAnalysis(p.projectId);
      totalPositiveAdj += adj['totalPositiveAdjustments']!;
      totalNegativeAdj += adj['totalNegativeAdjustments']!;
    }
    final avgPriceIncreaseRate = priceIncreaseRates.isNotEmpty
        ? priceIncreaseRates.reduce((a, b) => a + b) / priceIncreaseRates.length
        : null;

    final totalDiscount = allProjectReports.fold<double>(0, (s, p) => s + p.discountAmount);
    final totalGrossRevenue =
        allProjectReports.fold<double>(0, (s, p) => s + (p.grossRevenue ?? 0));
    final discountRatio = totalGrossRevenue != 0 ? (totalDiscount / totalGrossRevenue) * 100 : null;

    // ---------- مطالبات (Period) ----------
    final receivableMovement =
        await _reporting.getReceivableMovement(fromDate: range.fromDate, toDate: range.toDate);
    double totalReceivable = 0, totalAdvance = 0, totalCredit = 0;
    for (final p in allProjectReports) {
      totalReceivable += p.receivableBalance;
      totalAdvance += p.advanceBalance;
      totalCredit += p.customerCredit;
    }

    // ---------- روند ماهانه (Period-Based، نه Lifetime) ----------
    List<TrendPoint> revenueTrend = [];
    List<TrendPoint> operatingResultTrend = [];
    List<TrendPoint> cashFlowTrend = [];
    List<TrendPoint> marginTrend = [];
    if (includeTrend) {
      final buckets = DashboardPeriodResolver.monthlyBuckets(range.fromDate, range.toDate);
      for (final bucket in buckets) {
        final bucketReport =
            await _reporting.getPeriodReport(fromDate: bucket.fromDate, toDate: bucket.toDate);
        revenueTrend.add(TrendPoint(label: bucket.label, value: bucketReport.netRevenue));
        operatingResultTrend.add(TrendPoint(label: bucket.label, value: bucketReport.operatingResult));
        cashFlowTrend.add(TrendPoint(label: bucket.label, value: bucketReport.netCashChange));
        final margin = bucketReport.netRevenue != 0
            ? ((bucketReport.projectContribution ?? 0) / bucketReport.netRevenue) * 100
            : null;
        marginTrend.add(TrendPoint(label: bucket.label, value: margin));
      }
    }

    // ---------- Diagnostics و هشدارها ----------
    final diagnostics = await _reporting.getDiagnostics(fromDate: range.fromDate, toDate: range.toDate);
    final alerts = _buildAlerts(
      lossProjectsCount: lossProjects.length,
      outstandingProjectsCount: outstanding.length,
      customerCreditTotal: totalCredit,
      diagnostics: diagnostics,
    );

    return ManagementDashboardData(
      fromDate: range.fromDate,
      toDate: range.toDate,
      periodLabel: range.label,
      netRevenue: kpi(period.netRevenue, previousPeriod?.netRevenue),
      directProjectCost: kpi(period.directProjectCost, previousPeriod?.directProjectCost),
      projectContribution: kpiNullable(period.projectContribution, previousPeriod?.projectContribution),
      officeExpense: kpi(period.officeExpense, previousPeriod?.officeExpense),
      projectOverhead: kpi(period.projectOverhead, previousPeriod?.projectOverhead),
      operatingResult: kpiNullable(period.operatingResult, previousPeriod?.operatingResult),
      operatingMargin: kpiNullable(period.operatingMargin, previousPeriod?.operatingMargin),
      openingCash: period.openingCash,
      customerReceipts: period.customerReceipts,
      otherCashInflows: period.otherCashInflows,
      projectPayments: period.projectPayments,
      projectOverheadPayments: period.projectOverheadPayments,
      officePayments: period.officePayments,
      otherCashOutflows: period.otherCashOutflows,
      closingCash: period.closingCash,
      cashReconciles: period.cashReconciles,
      bankBalances: bankBalances,
      receivableBalance: totalReceivable,
      customerCreditBalance: totalCredit,
      advanceBalance: totalAdvance,
      receivableMovement: receivableMovement,
      periodReceiptToRevenueRatio:
          period.netRevenue != 0 ? (period.customerReceipts / period.netRevenue) * 100 : null,
      closingReceivableToPeriodRevenueRatio:
          period.netRevenue != 0 ? (totalReceivable / period.netRevenue) * 100 : null,
      // مورد ۳: شاخص دقیق‌تر AR Collection - فقط چون Opening/NewReceivables/
      // Collections با اطمینان از Ledger (arMovement) قابل استخراجند این‌جا
      // اضافه شد؛ اگر مخرج (مانده ابتدای بازه + طلب جدید) صفر باشد یعنی
      // اصلاً چیزی برای وصول موجود نبوده، پس null معنادار است.
      periodArCollectionRate: (receivableMovement['opening']! + receivableMovement['newReceivables']!) != 0
          ? (receivableMovement['collections']! /
                  (receivableMovement['opening']! + receivableMovement['newReceivables']!)) *
              100
          : null,
      finalizedProjectsCount: finalizedCount,
      settledProjectsCount: settledCount,
      unsettledProjectsCount: unsettledCount,
      allProjects: allProjectReports,
      worstProjects: worst,
      bestProjects: best,
      outstandingProjects: outstanding,
      lossProjects: lossProjects,
      customers: customers,
      top5CustomersRevenueShare: top5Share,
      totalInitialEstimates: totalInitial,
      totalFinalAmounts: totalFinal,
      totalAdditions: totalAdditions,
      totalReductions: totalReductions,
      averagePriceIncreaseRate: avgPriceIncreaseRate,
      totalDiscount: totalDiscount,
      discountToGrossRevenueRatio: discountRatio,
      totalPositiveAdjustments: totalPositiveAdj,
      totalNegativeAdjustments: totalNegativeAdj,
      netAdjustments: totalPositiveAdj - totalNegativeAdj,
      revenueTrend: revenueTrend,
      operatingResultTrend: operatingResultTrend,
      cashFlowTrend: cashFlowTrend,
      contributionMarginTrend: marginTrend,
      alerts: alerts,
      diagnostics: diagnostics,
    );
  }

  /// هشدارهای Rule-Based (نه AI). طبق تصریح متن، آستانه هشدار «تخفیف بالا»
  /// چون در معماری فعلی تعریف نشده، فعلاً پیاده نمی‌شود (فقط به‌عنوان
  /// Future Configuration مستند می‌شود).
  List<ManagementAlert> _buildAlerts({
    required int lossProjectsCount,
    required int outstandingProjectsCount,
    required double customerCreditTotal,
    required FinancialReportDiagnostics diagnostics,
  }) {
    final alerts = <ManagementAlert>[];
    if (lossProjectsCount > 0) {
      alerts.add(ManagementAlert(
        title: 'پروژه‌های زیان‌ده',
        message: '$lossProjectsCount پروژه زیان‌ده وجود دارد',
        severity: ManagementAlertSeverity.warning,
      ));
    }
    if (outstandingProjectsCount > 0) {
      alerts.add(ManagementAlert(
        title: 'مطالبات باز',
        message: 'مطالباتی از مشتریان در انتظار وصول شناسایی شد',
        severity: ManagementAlertSeverity.info,
      ));
    }
    if (customerCreditTotal > 0) {
      alerts.add(ManagementAlert(
        title: 'بستانکاری مشتری',
        message: 'مانده بستانکاری مشتری (مازاد دریافتی) وجود دارد',
        severity: ManagementAlertSeverity.info,
      ));
    }
    if (diagnostics.revenueLedgerMismatchCount > 0) {
      alerts.add(ManagementAlert(
        title: 'ناسازگاری تطبیق درآمد',
        message: 'ناسازگاری بین درآمد محاسبه‌شده و Ledger شناسایی شد',
        severity: ManagementAlertSeverity.error,
      ));
    }
    if (diagnostics.cashReconciliationErrors > 0) {
      alerts.add(ManagementAlert(
        title: 'ناسازگاری تطبیق نقدی',
        message: 'خطای تطبیق جریان نقدی شناسایی شد',
        severity: ManagementAlertSeverity.error,
      ));
    }
    return alerts;
  }
}
