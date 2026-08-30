import '../db/database_helper.dart';
import '../models/financial_reports.dart';
import '../models/management_dashboard_data.dart';
import '../models/operational_performance.dart';
import '../models/project.dart';
import '../models/project_price_event.dart';
import '../utils/dashboard_period.dart';
import 'financial_metrics_service.dart';
import 'financial_reporting_service.dart';
import 'project_economics_service.dart';

/// لایه تحلیل عملکرد عملیاتی - کاملاً READ-ONLY. هیچ Journal/PriceEvent
/// نمی‌سازد، هیچ Ledger Balance را بازسازی نمی‌کند، هیچ داده تحلیلی را
/// ذخیره نمی‌کند. تنها مصرف‌کننده FinancialMetricsService/
/// FinancialReportingService/ProjectEconomicsService و یک متد READ اضافه
/// (`getAllPriceEventsInRange`) در DatabaseHelper است.
class OperationalPerformanceService {
  final DatabaseHelper _db;
  final FinancialMetricsService _metrics;
  final FinancialReportingService _reporting;
  final ProjectEconomicsService _economics;

  OperationalPerformanceService({
    DatabaseHelper? db,
    FinancialMetricsService? metrics,
    FinancialReportingService? reporting,
    ProjectEconomicsService? economics,
  })  : _db = db ?? DatabaseHelper.instance,
        _metrics = metrics ?? FinancialMetricsService(db),
        _reporting = reporting ?? FinancialReportingService(db: db, metrics: metrics),
        _economics = economics ?? ProjectEconomicsService(db: db, metrics: metrics, reporting: reporting);

  bool _inRange(String? date, String fromDate, String toDate) {
    if (date == null) return false;
    return date.compareTo(fromDate) >= 0 && date.compareTo(toDate) <= 0;
  }

  Future<OperationalPerformanceData> buildOperationalPerformance({
    required DashboardPeriodRange period,
    bool includeComparison = true,
    bool includeTrend = true,
  }) async {
    final warnings = <String>[];
    final allProjects = await _db.getProjects();
    final allReports = await _reporting.getProjectReports();
    final reportById = {for (final r in allReports) r.projectId: r};

    // ---------- Activity Overview ----------
    final newInPeriod = allProjects.where((p) => _inRange(p.createdAt, period.fromDate, period.toDate)).toList();
    final finalizedInPeriod =
        allProjects.where((p) => _inRange(p.finalizedDate, period.fromDate, period.toDate)).toList();

    int settledCount = 0, openCount = 0, cancelledCount = 0;
    final countByStatus = <String, int>{};
    for (final p in allProjects) {
      countByStatus[p.status] = (countByStatus[p.status] ?? 0) + 1;
      if (p.status == kProjectStatusCancelled) cancelledCount++;
      final report = reportById[p.id];
      if (report != null) {
        if (report.isSettled) {
          settledCount++;
        } else {
          openCount++;
        }
      }
    }
    warnings.add(
        'تعداد پروژه‌های تسویه‌شده/باز، وضعیت فعلی (زمان تولید گزارش) را نشان می‌دهد، نه وضعیت دقیق در پایان بازه؛ چون سیستم تاریخ تسویه را ثبت نمی‌کند.');

    // ---------- Financial Performance (JournalEntry.date) ----------
    final periodReport = await _reporting.getPeriodReport(fromDate: period.fromDate, toDate: period.toDate);
    final finalizedContributionMargin = periodReport.netRevenue != 0
        ? ((periodReport.projectContribution ?? 0) / periodReport.netRevenue) * 100
        : null;

    // ---------- Volume vs Financial Volume ----------
    final revenuePerFinalizedProject =
        finalizedInPeriod.isNotEmpty ? periodReport.netRevenue / finalizedInPeriod.length : null;
    final contributionPerFinalizedProject = (finalizedInPeriod.isNotEmpty && periodReport.projectContribution != null)
        ? periodReport.projectContribution! / finalizedInPeriod.length
        : null;

    final finalizedInPeriodReports =
        finalizedInPeriod.map((p) => reportById[p.id]).whereType<ProjectFinancialReport>().toList();
    final marginsInPeriod = finalizedInPeriodReports
        .map((r) => r.contributionMargin)
        .whereType<double>()
        .toList();
    final averageProjectMargin =
        marginsInPeriod.isNotEmpty ? marginsInPeriod.reduce((a, b) => a + b) / marginsInPeriod.length : null;

    // ---------- Outcome Distribution (فقط Finalize‌شده در بازه) ----------
    int lossCount = 0, lowCount = 0, normalCount = 0, highCount = 0;
    for (final r in finalizedInPeriodReports) {
      switch (r.profitabilityStatus) {
        case ProjectProfitabilityStatus.loss:
          lossCount++;
          break;
        case ProjectProfitabilityStatus.lowMargin:
          lowCount++;
          break;
        case ProjectProfitabilityStatus.normalMargin:
          normalCount++;
          break;
        case ProjectProfitabilityStatus.highMargin:
          highCount++;
          break;
        case ProjectProfitabilityStatus.unknown:
          break;
      }
    }
    final lossRate =
        finalizedInPeriod.isNotEmpty ? (lossCount / finalizedInPeriod.length) * 100 : null;

    // ---------- Customer Concentration (Lifetime - محدودیت مستند) ----------
    final top1 = await _reporting.getTopCustomersRevenueShare(1);
    final top3 = await _reporting.getTopCustomersRevenueShare(3);
    final top5 = await _reporting.getTopCustomersRevenueShare(5);
    warnings.add('شاخص‌های تمرکز مشتری (Top1/Top3/Top5) بر مبنای کل عمر داده‌ها (Lifetime) محاسبه شده‌اند، نه محدود به بازه انتخابی.');

    // ---------- Pricing & Discount (ProjectPriceEvent.date) ----------
    final priceEventsInPeriod =
        await _db.getAllPriceEventsInRange(fromDate: period.fromDate, toDate: period.toDate);
    final totalAdditions = priceEventsInPeriod
        .where((e) => e.type == kPriceEventAddition)
        .fold<double>(0, (s, e) => s + e.amount);
    final totalReductions = priceEventsInPeriod
        .where((e) => e.type == kPriceEventReduction)
        .fold<double>(0, (s, e) => s + e.amount.abs());
    final totalDiscount = priceEventsInPeriod
        .where((e) => e.type == kPriceEventDiscount)
        .fold<double>(0, (s, e) => s + e.amount.abs());
    final discountRate = periodReport.grossRevenue != 0 ? (totalDiscount / periodReport.grossRevenue) * 100 : null;
    final discountPerFinalizedProject =
        finalizedInPeriod.isNotEmpty ? totalDiscount / finalizedInPeriod.length : null;

    // ---------- Collection Performance ----------
    final receivableMovement =
        await _reporting.getReceivableMovement(toDate: period.toDate);
    final creditMovement = await _reporting.getCustomerCreditMovement(toDate: period.toDate);
    final collectionRate =
        periodReport.netRevenue != 0 ? (periodReport.customerReceipts / periodReport.netRevenue) * 100 : null;
    final collectionGap = periodReport.netRevenue - periodReport.customerReceipts;

    // ---------- WIP (وضعیت فعلی) ----------
    final wipReports = allReports.where((r) => !r.isFinalized).toList();
    final wipInitialEstimate = wipReports.fold<double>(0, (s, r) => s + r.initialEstimate);
    final wipDirectCost = wipReports.fold<double>(0, (s, r) => s + r.directProjectCost);
    final wipReceived = wipReports.fold<double>(0, (s, r) => s + r.totalReceived);

    // ---------- Growth Decomposition (نسبت به دوره قبل هم‌طول) ----------
    List<FinancialPeriodComparison> comparisons = [];
    double? revenueGrowth, avgRevenueGrowth, contributionGrowth, volumeGrowth, marginChangePoints;
    if (includeComparison) {
      final previousRange = DashboardPeriodResolver.previousPeriodOf(period);
      final previousReport =
          await _reporting.getPeriodReport(fromDate: previousRange.fromDate, toDate: previousRange.toDate);
      final previousProjects = allProjects
          .where((p) => _inRange(p.finalizedDate, previousRange.fromDate, previousRange.toDate))
          .toList();

      revenueGrowth = previousReport.netRevenue != 0
          ? ((periodReport.netRevenue - previousReport.netRevenue) / previousReport.netRevenue) * 100
          : null;
      final previousAvgRevenue =
          previousProjects.isNotEmpty ? previousReport.netRevenue / previousProjects.length : null;
      avgRevenueGrowth = (previousAvgRevenue != null && previousAvgRevenue != 0 && revenuePerFinalizedProject != null)
          ? ((revenuePerFinalizedProject - previousAvgRevenue) / previousAvgRevenue) * 100
          : null;
      final previousContribution = previousReport.projectContribution;
      contributionGrowth = (previousContribution != null && previousContribution != 0 && periodReport.projectContribution != null)
          ? ((periodReport.projectContribution! - previousContribution) / previousContribution.abs()) * 100
          : null;
      volumeGrowth = previousProjects.isNotEmpty
          ? ((finalizedInPeriod.length - previousProjects.length) / previousProjects.length) * 100
          : null;
      final previousMargin = previousReport.netRevenue != 0
          ? ((previousReport.projectContribution ?? 0) / previousReport.netRevenue) * 100
          : null;
      marginChangePoints = (finalizedContributionMargin != null && previousMargin != null)
          ? finalizedContributionMargin - previousMargin
          : null;

      comparisons = [
        FinancialPeriodComparison.compute(
            metricName: 'revenue', current: periodReport.netRevenue, previous: previousReport.netRevenue),
        FinancialPeriodComparison.compute(
            metricName: 'contribution',
            current: periodReport.projectContribution ?? 0,
            previous: previousReport.projectContribution),
        FinancialPeriodComparison.compute(
            metricName: 'projectVolume',
            current: finalizedInPeriod.length.toDouble(),
            previous: previousProjects.length.toDouble()),
        FinancialPeriodComparison.compute(
            metricName: 'collectionRate', current: collectionRate ?? 0, previous: null),
        FinancialPeriodComparison.compute(
            metricName: 'receivable',
            current: receivableMovement['closing'] ?? 0,
            previous: null),
      ];
    }

    // ---------- Trend (فقط Observed - هرگز Forecast) ----------
    List<TrendPoint> revenueTrend = [], contributionTrend = [], volumeTrend = [], receivableTrend = [];
    if (includeTrend) {
      final buckets = DashboardPeriodResolver.monthlyBuckets(period.fromDate, period.toDate);
      for (final bucket in buckets) {
        final bucketReport = await _reporting.getPeriodReport(fromDate: bucket.fromDate, toDate: bucket.toDate);
        revenueTrend.add(TrendPoint(label: bucket.label, value: bucketReport.netRevenue));
        contributionTrend.add(TrendPoint(label: bucket.label, value: bucketReport.projectContribution));
        final bucketFinalizedCount =
            allProjects.where((p) => _inRange(p.finalizedDate, bucket.fromDate, bucket.toDate)).length;
        volumeTrend.add(TrendPoint(label: bucket.label, value: bucketFinalizedCount.toDouble()));
        final bucketReceivable = await _reporting.getReceivableMovement(toDate: bucket.toDate);
        receivableTrend.add(TrendPoint(label: bucket.label, value: bucketReceivable['closing']));
      }
    }

    // ---------- Diagnostics & Alerts ----------
    final diagnostics = await _reporting.getDiagnostics(fromDate: period.fromDate, toDate: period.toDate);
    final alerts = _buildAlerts(
      lossCount: lossCount,
      marginChangePoints: marginChangePoints,
      collectionRate: collectionRate,
      discountRate: discountRate,
      diagnostics: diagnostics,
    );

    return OperationalPerformanceData(
      periodStart: period.fromDate,
      periodEnd: period.toDate,
      periodLabel: period.label,
      projectCount: allProjects.length,
      newProjectCount: newInPeriod.length,
      finalizedProjectCount: finalizedInPeriod.length,
      settledProjectCount: settledCount,
      openProjectCount: openCount,
      cancelledProjectCount: cancelledCount,
      countByStatus: countByStatus,
      finalizedRevenue: periodReport.netRevenue,
      finalizedDirectCost: periodReport.directProjectCost,
      finalizedContribution: periodReport.projectContribution,
      finalizedContributionMargin: finalizedContributionMargin,
      revenuePerFinalizedProject: revenuePerFinalizedProject,
      contributionPerFinalizedProject: contributionPerFinalizedProject,
      averageProjectMargin: averageProjectMargin,
      revenueGrowthRate: revenueGrowth,
      averageRevenueGrowthRate: avgRevenueGrowth,
      contributionGrowthRate: contributionGrowth,
      projectVolumeGrowthRate: volumeGrowth,
      contributionMarginChangePoints: marginChangePoints,
      lossProjectCount: lossCount,
      lowMarginProjectCount: lowCount,
      normalMarginProjectCount: normalCount,
      highMarginProjectCount: highCount,
      lossProjectRate: lossRate,
      top1CustomerRevenueShare: top1,
      top3CustomerRevenueShare: top3,
      top5CustomerRevenueShare: top5,
      totalPriceAdditions: totalAdditions,
      totalPriceReductions: totalReductions,
      netPriceChange: totalAdditions - totalReductions,
      totalDiscount: totalDiscount,
      discountRate: discountRate,
      discountPerFinalizedProject: discountPerFinalizedProject,
      totalReceived: periodReport.customerReceipts,
      receivableBalance: receivableMovement['closing'] ?? 0,
      customerCredit: creditMovement['closing'] ?? 0,
      collectionRate: collectionRate,
      collectionGap: collectionGap,
      wipProjectCount: wipReports.length,
      wipInitialEstimate: wipInitialEstimate,
      wipDirectCost: wipDirectCost,
      wipReceived: wipReceived,
      comparisons: comparisons,
      revenueTrend: revenueTrend,
      contributionTrend: contributionTrend,
      projectVolumeTrend: volumeTrend,
      receivableTrend: receivableTrend,
      alerts: alerts,
      diagnostics: diagnostics,
      warnings: warnings,
    );
  }

  /// هشدارهای Rule-Based بدون Threshold مدیریتی جدید Hard-Code شده - فقط
  /// جهت تغییر را گزارش می‌کند («کاهش یافت»)، نه قضاوت کمی («بیش از حد
  /// کاهش یافت») مگر جایی که از Threshold از پیش موجود (مثل صفر) استفاده شود.
  List<ManagementAlert> _buildAlerts({
    required int lossCount,
    required double? marginChangePoints,
    required double? collectionRate,
    required double? discountRate,
    required FinancialReportDiagnostics diagnostics,
  }) {
    final alerts = <ManagementAlert>[];
    if (lossCount > 0) {
      alerts.add(ManagementAlert(
        title: 'پروژه‌های زیان‌ده',
        message: '$lossCount پروژه زیان‌ده در این بازه Finalize شده است',
        severity: ManagementAlertSeverity.warning,
      ));
    }
    if (marginChangePoints != null && marginChangePoints < 0) {
      alerts.add(ManagementAlert(
        title: 'کاهش حاشیه سود',
        message: 'حاشیه سود نسبت به دوره قبل ${marginChangePoints.abs().toStringAsFixed(1)} واحد درصد کاهش یافته',
        severity: ManagementAlertSeverity.warning,
      ));
    }
    if (diagnostics.revenueLedgerMismatchCount > 0) {
      alerts.add(ManagementAlert(
        title: 'ناسازگاری تطبیق درآمد',
        message: 'ناسازگاری بین درآمد محاسبه‌شده و Ledger شناسایی شد',
        severity: ManagementAlertSeverity.error,
      ));
    }
    if (diagnostics.negativeARCount > 0 || diagnostics.negativeAdvanceCount > 0) {
      alerts.add(ManagementAlert(
        title: 'مانده منفی نامعتبر',
        message: 'مانده منفی در AR یا پیش‌دریافت شناسایی شد',
        severity: ManagementAlertSeverity.error,
      ));
    }
    return alerts;
  }
}
