import '../db/database_helper.dart';
import '../models/financial_metrics.dart';
import '../models/financial_reports.dart';
import '../models/project.dart';
import '../models/project_price_event.dart';
import '../services/financial_metrics_service.dart';

/// لایه گزارش‌دهی مدیریتی - مصرف‌کننده FinancialMetricsService است، نه
/// جایگزین آن. هرگز Journal نمی‌سازد/حذف نمی‌کند و هیچ نتیجه‌ای را در
/// دیتابیس ذخیره نمی‌کند (NO REPORT SUMMARY TABLE).
class FinancialReportingService {
  final DatabaseHelper _db;
  final FinancialMetricsService _metrics;

  FinancialReportingService({DatabaseHelper? db, FinancialMetricsService? metrics})
      : _db = db ?? DatabaseHelper.instance,
        _metrics = metrics ?? FinancialMetricsService(db);

  // ================= Project Reports =================

  Future<ProjectFinancialReport> getProjectReport(int projectId) async {
    final project = await _db.getProject(projectId);
    if (project == null) throw Exception('پروژه یافت نشد.');
    final m = await _metrics.getProjectMetrics(projectId);
    return _buildProjectReport(project, m);
  }

  ProjectFinancialReport _buildProjectReport(ProjectModel project, ProjectFinancialMetrics m) {
    final revenueStatus = !m.isFinalized
        ? RevenueStatus.notFinalized
        : (m.finalAdjustments != 0 ? RevenueStatus.adjusted : RevenueStatus.finalized);
    final settlementStatus = m.isSettled ? SettlementStatus.settled : SettlementStatus.unsettled;
    final creditStatus = m.customerCredit != null && m.customerCredit! > 0
        ? CreditStatus.hasCredit
        : CreditStatus.noCredit;
    final profitability =
        ProfitabilityThresholds.classify(m.projectContribution, m.contributionMargin);

    final estimateToEffectiveVariance =
        m.effectiveFinalAmount != null ? m.effectiveFinalAmount! - m.initialEstimate : null;
    final directCostRatio =
        (m.netRevenue != null && m.netRevenue != 0) ? (m.directProjectCost / m.netRevenue!) * 100 : null;
    final discountRate =
        (m.grossRevenue != null && m.grossRevenue != 0) ? (m.discountAmount / m.grossRevenue!) * 100 : null;

    return ProjectFinancialReport(
      projectId: project.id!,
      projectName: project.title,
      counterpartyId: project.counterpartyId,
      initialEstimate: m.initialEstimate,
      finalAmount: m.finalAmount,
      effectiveFinalAmount: m.effectiveFinalAmount,
      grossRevenue: m.grossRevenue,
      discountAmount: m.discountAmount,
      netRevenue: m.netRevenue,
      totalReceived: m.totalReceived,
      advanceBalance: m.advanceBalance,
      receivableBalance: m.receivableBalance,
      customerCredit: m.customerCredit ?? 0,
      directProjectCost: m.directProjectCost,
      projectContribution: m.projectContribution,
      contributionMargin: m.contributionMargin,
      priceIncreaseAmount: m.priceIncreaseAmount,
      priceIncreaseRate: m.priceIncreaseRate,
      finalAdjustments: m.finalAdjustments,
      estimateToEffectiveVariance: estimateToEffectiveVariance,
      collectionRate: m.collectionRate,
      outstandingRatio: m.outstandingRatio,
      directCostRatio: directCostRatio,
      discountRate: discountRate,
      isFinalized: m.isFinalized,
      isSettled: m.isSettled,
      revenueStatus: revenueStatus,
      settlementStatus: settlementStatus,
      creditStatus: creditStatus,
      profitabilityStatus: profitability,
    );
  }

  /// گزارش چند پروژه با فیلترهای پشتیبانی‌شده توسط داده فعلی. فیلترهایی که
  /// داده فعلی امکان آن را نمی‌دهد (مثلاً فیلتر بر مبنای تاریخ فعالیت
  /// Ledger برای یک پروژه خاص) در این تابع اضافه نشدند تا حدس زده نشوند.
  Future<List<ProjectFinancialReport>> getProjectReports({
    int? counterpartyId,
    String? projectStatus,
    bool? finalizedOnly,
    bool? settledOnly,
  }) async {
    final projects = await _db.getProjects(counterpartyId: counterpartyId);
    final filteredByStatus =
        projectStatus == null ? projects : projects.where((p) => p.status == projectStatus).toList();

    final reports = <ProjectFinancialReport>[];
    for (final p in filteredByStatus) {
      final m = await _metrics.getProjectMetrics(p.id!);
      if (finalizedOnly == true && !m.isFinalized) continue;
      if (settledOnly == true && !m.isSettled) continue;
      reports.add(_buildProjectReport(p, m));
    }
    return reports;
  }

  List<ProjectFinancialReport> sortProjectReports(
    List<ProjectFinancialReport> reports,
    ProjectReportSort sortBy, {
    bool descending = true,
  }) {
    double keyOf(ProjectFinancialReport r) {
      switch (sortBy) {
        case ProjectReportSort.contribution:
          return r.projectContribution ?? double.negativeInfinity;
        case ProjectReportSort.contributionMargin:
          return r.contributionMargin ?? double.negativeInfinity;
        case ProjectReportSort.netRevenue:
          return r.netRevenue ?? double.negativeInfinity;
        case ProjectReportSort.directCost:
          return r.directProjectCost;
        case ProjectReportSort.priceIncreaseRate:
          return r.priceIncreaseRate ?? double.negativeInfinity;
        case ProjectReportSort.discountRate:
          return r.discountRate ?? double.negativeInfinity;
      }
    }

    final sorted = [...reports]..sort((a, b) => keyOf(a).compareTo(keyOf(b)));
    return descending ? sorted.reversed.toList() : sorted;
  }

  /// بدترین پروژه‌ها طبق یک معیار مشخص (کمترین مقدار آن معیار)
  List<ProjectFinancialReport> getWorstProjects(
    List<ProjectFinancialReport> reports,
    ProjectReportSort by, {
    int limit = 5,
  }) {
    final ascending = sortProjectReports(reports, by, descending: false);
    return ascending.take(limit).toList();
  }

  /// بهترین پروژه‌ها طبق یک معیار مشخص
  List<ProjectFinancialReport> getBestProjects(
    List<ProjectFinancialReport> reports,
    ProjectReportSort by, {
    int limit = 5,
  }) {
    final descending = sortProjectReports(reports, by, descending: true);
    return descending.take(limit).toList();
  }

  /// تحلیل اصلاحات پس از Finalization برای یک پروژه (Discount در این سه
  /// مقدار وارد نمی‌شود)
  Future<Map<String, double>> getAdjustmentAnalysis(int projectId) async {
    final events = await _db.getProjectPriceEvents(projectId);
    final adjustments = events.where((e) => e.type == kPriceEventFinalAdjustment);
    final positive = adjustments.where((e) => e.amount > 0).fold<double>(0, (s, e) => s + e.amount);
    final negative =
        adjustments.where((e) => e.amount < 0).fold<double>(0, (s, e) => s + e.amount.abs());
    return {
      'totalPositiveAdjustments': positive,
      'totalNegativeAdjustments': negative,
      'netAdjustments': positive - negative,
    };
  }

  // ================= Customer Reports =================

  Future<CustomerFinancialReport> getCustomerReport(int counterpartyId, {double? officeNetRevenue}) async {
    final cm = await _metrics.getCustomerMetrics(counterpartyId);
    final allProjects = await _db.getProjects(counterpartyId: counterpartyId);
    int settledCount = 0, profitableCount = 0, lossCount = 0;
    for (final p in allProjects) {
      final pm = await _metrics.getProjectMetrics(p.id!);
      if (pm.isSettled) settledCount++;
      final status = ProfitabilityThresholds.classify(pm.projectContribution, pm.contributionMargin);
      if (status == ProjectProfitabilityStatus.loss) {
        lossCount++;
      } else if (status == ProjectProfitabilityStatus.lowMargin ||
          status == ProjectProfitabilityStatus.normalMargin ||
          status == ProjectProfitabilityStatus.highMargin) {
        profitableCount++;
      }
    }

    return CustomerFinancialReport(
      counterpartyId: counterpartyId,
      projectCount: allProjects.length,
      finalizedProjectCount: cm.projectCount,
      settledProjectCount: settledCount,
      profitableProjectCount: profitableCount,
      lossProjectCount: lossCount,
      grossRevenue: cm.grossRevenue,
      discountAmount: cm.discountAmount,
      netRevenue: cm.netRevenue,
      totalReceived: cm.totalReceived,
      receivableBalance: cm.receivableBalance,
      customerCredit: cm.customerCredit,
      directProjectCost: cm.directProjectCost,
      projectContribution: cm.projectContribution,
      contributionMargin: cm.contributionMargin,
      collectionRate: cm.collectionRate,
      outstandingRatio: cm.outstandingRatio,
      averageProjectValue: cm.averageProjectValue,
      averageDiscountRate: cm.averageDiscountRate,
      revenueShareOfOffice:
          (officeNetRevenue != null && officeNetRevenue != 0) ? (cm.netRevenue / officeNetRevenue) * 100 : null,
    );
  }

  /// گزارش همه مشتریان (طرف‌حساب‌هایی که حداقل یک پروژه دارند)، با سهم هرکدام
  /// از درآمد خالص دفتر، به‌همراه امکان مرتب‌سازی طبق [CustomerReportSort].
  Future<List<CustomerFinancialReport>> getAllCustomerReports({CustomerReportSort? sortBy}) async {
    final allProjects = await _db.getProjects();
    final counterpartyIds = allProjects.map((p) => p.counterpartyId).toSet();
    final office = await _metrics.getOfficeMetrics();

    final reports = <CustomerFinancialReport>[];
    for (final cid in counterpartyIds) {
      reports.add(await getCustomerReport(cid, officeNetRevenue: office.netRevenue));
    }

    if (sortBy == null) return reports;
    double keyOf(CustomerFinancialReport r) {
      switch (sortBy) {
        case CustomerReportSort.netRevenue:
          return r.netRevenue;
        case CustomerReportSort.contribution:
          return r.projectContribution ?? double.negativeInfinity;
        case CustomerReportSort.contributionMargin:
          return r.contributionMargin ?? double.negativeInfinity;
        case CustomerReportSort.received:
          return r.totalReceived;
        case CustomerReportSort.outstandingAR:
          return r.receivableBalance;
        case CustomerReportSort.projectCount:
          return r.projectCount.toDouble();
      }
    }

    reports.sort((a, b) => keyOf(b).compareTo(keyOf(a))); // نزولی پیش‌فرض
    return reports;
  }

  /// سهم Top-N مشتری از درآمد خالص کل دفتر (تمرکز مشتری)
  Future<double?> getTopCustomersRevenueShare(int topN) async {
    final reports = await getAllCustomerReports(sortBy: CustomerReportSort.netRevenue);
    if (reports.isEmpty) return null;
    final office = await _metrics.getOfficeMetrics();
    if (office.netRevenue == 0) return null;
    final topRevenue =
        reports.take(topN).fold<double>(0, (s, r) => s + r.netRevenue);
    return (topRevenue / office.netRevenue) * 100;
  }

  /// سهم Top-N پروژه از درآمد خالص کل دفتر (تمرکز پروژه)
  Future<double?> getTopProjectsRevenueShare(int topN) async {
    final allProjects = await _db.getProjects();
    final office = await _metrics.getOfficeMetrics();
    if (office.netRevenue == 0) return null;
    final revenues = <double>[];
    for (final p in allProjects) {
      final m = await _metrics.getProjectMetrics(p.id!);
      if (m.netRevenue != null) revenues.add(m.netRevenue!);
    }
    revenues.sort((a, b) => b.compareTo(a));
    final topRevenue = revenues.take(topN).fold<double>(0, (s, v) => s + v);
    return (topRevenue / office.netRevenue) * 100;
  }

  // ================= Period Reports =================

  Future<PeriodFinancialReport> getPeriodReport({String? fromDate, String? toDate}) async {
    final office = await _metrics.getOfficeMetrics(fromDate: fromDate, toDate: toDate);
    final cash = await _metrics.getCashFlowMetrics(fromDate: fromDate, toDate: toDate);

    return PeriodFinancialReport(
      fromDate: fromDate,
      toDate: toDate,
      grossRevenue: office.grossRevenue,
      discountAmount: office.discountAmount,
      netRevenue: office.netRevenue,
      directProjectCost: office.directProjectCost,
      projectContribution: office.projectContribution,
      projectOverhead: office.projectOverhead,
      officeExpense: office.officeExpense,
      operatingResult: office.operatingResult,
      operatingMargin: office.operatingMargin,
      customerReceipts: cash.customerReceipts,
      otherCashInflows: cash.otherCashInflows,
      projectPayments: cash.projectPayments,
      projectOverheadPayments: cash.projectOverheadPayments,
      officePayments: cash.officePayments,
      otherCashOutflows: cash.otherCashOutflows,
      openingCash: cash.openingCash,
      closingCash: cash.closingCash,
    );
  }

  // ================= Movement Reports =================
  // محدودیت مستند: newReceivables/collections/adjustments (و مشابه برای
  // Advance/Credit) بر مبنای شناسایی حساب طرف‌مقابل هر سطر به‌دست می‌آیند؛
  // فقط اسناد دقیقاً دوسطری (که همه مسیرهای خودکار برنامه چنین‌اند) به‌درستی
  // طبقه‌بندی می‌شوند. usedCredit برای Customer Credit اصلاً قابل تشخیص
  // نیست (چون این معماری مصرف بستانکاری را از طریق سند دستی و به تشخیص
  // کاربر انجام می‌دهد، نه یک عملیات سیستمی مشخص) - پس فقط تغییر خالص گزارش
  // می‌شود، نه تفکیک new/used.

  Future<Map<String, double>> getReceivableMovement({String? fromDate, String? toDate, int? projectId}) {
    return _db.arMovement(fromDate: fromDate, toDate: toDate, projectId: projectId);
  }

  Future<Map<String, double>> getAdvanceMovement({String? fromDate, String? toDate, int? projectId}) {
    return _db.advanceMovement(fromDate: fromDate, toDate: toDate, projectId: projectId);
  }

  Future<Map<String, double>> getCustomerCreditMovement(
      {String? fromDate, String? toDate, int? projectId}) {
    return _db.customerCreditMovement(fromDate: fromDate, toDate: toDate, projectId: projectId);
  }

  // ================= Management Summary & Comparison =================

  Future<ManagementFinancialSummary> getManagementSummary({
    String? fromDate,
    String? toDate,
    String? previousFromDate,
    String? previousToDate,
  }) async {
    final period = await getPeriodReport(fromDate: fromDate, toDate: toDate);
    final allProjects = await _db.getProjects();

    int finalizedCount = 0, settledCount = 0, profitableCount = 0, lossCount = 0;
    for (final p in allProjects) {
      final m = await _metrics.getProjectMetrics(p.id!);
      if (m.isFinalized) finalizedCount++;
      if (m.isSettled) settledCount++;
      final status = ProfitabilityThresholds.classify(m.projectContribution, m.contributionMargin);
      if (status == ProjectProfitabilityStatus.loss) {
        lossCount++;
      } else if (status != ProjectProfitabilityStatus.unknown) {
        profitableCount++;
      }
    }

    // مانده‌های کل دفتر (نه بازه‌ای) - جمع مانده تمام پروژه‌ها، چون AR/Advance
    // مانده‌های تجمعی‌اند نه رویدادهای دوره‌ای
    double totalReceivable = 0, totalAdvance = 0, totalCredit = 0;
    for (final p in allProjects) {
      totalReceivable += await _db.projectReceivableBalance(p.id!);
      totalAdvance += await _db.projectAdvanceBalance(p.id!);
      totalCredit += await _db.projectCustomerCreditBalance(p.id!);
    }

    List<FinancialPeriodComparison> comparisons = [];
    if (previousFromDate != null || previousToDate != null) {
      final previousPeriod =
          await getPeriodReport(fromDate: previousFromDate, toDate: previousToDate);
      comparisons = [
        FinancialPeriodComparison.compute(
            metricName: 'netRevenue', current: period.netRevenue, previous: previousPeriod.netRevenue),
        FinancialPeriodComparison.compute(
            metricName: 'projectContribution',
            current: period.projectContribution ?? 0,
            previous: previousPeriod.projectContribution),
        FinancialPeriodComparison.compute(
            metricName: 'operatingResult',
            current: period.operatingResult ?? 0,
            previous: previousPeriod.operatingResult),
        FinancialPeriodComparison.compute(
            metricName: 'customerReceipts',
            current: period.customerReceipts,
            previous: previousPeriod.customerReceipts),
      ];
    }

    return ManagementFinancialSummary(
      fromDate: fromDate,
      toDate: toDate,
      netRevenue: period.netRevenue,
      totalReceived: period.customerReceipts,
      directProjectCost: period.directProjectCost,
      projectContribution: period.projectContribution,
      projectOverhead: period.projectOverhead,
      officeExpense: period.officeExpense,
      operatingResult: period.operatingResult,
      operatingMargin: period.operatingMargin,
      receivableBalance: totalReceivable,
      advanceBalance: totalAdvance,
      customerCredit: totalCredit,
      projectCount: allProjects.length,
      finalizedProjectCount: finalizedCount,
      settledProjectCount: settledCount,
      profitableProjectCount: profitableCount,
      lossProjectCount: lossCount,
      comparisons: comparisons,
    );
  }

  // ================= Diagnostics =================

  /// بررسی جامع سلامت داده مالی - هیچ ناسازگاری‌ای پنهان نمی‌شود.
  Future<FinancialReportDiagnostics> getDiagnostics({String? fromDate, String? toDate}) async {
    final allProjects = await _db.getProjects();
    final mismatchIds = <int>[];
    final negativeArIds = <int>[];
    final negativeAdvanceIds = <int>[];
    final negativeCreditIds = <int>[];

    for (final p in allProjects) {
      final reconciliation = await _metrics.reconcileProject(p.id!);
      if (reconciliation.status == 'MISMATCH') mismatchIds.add(p.id!);

      final ar = await _db.projectReceivableBalance(p.id!);
      if (ar < 0) negativeArIds.add(p.id!);
      final advance = await _db.projectAdvanceBalance(p.id!);
      if (advance < 0) negativeAdvanceIds.add(p.id!);
      final credit = await _db.projectCustomerCreditBalance(p.id!);
      if (credit < 0) negativeCreditIds.add(p.id!);
    }

    final cashReport = await getPeriodReport(fromDate: fromDate, toDate: toDate);
    final cashErrors = cashReport.cashReconciles ? 0 : 1;

    return FinancialReportDiagnostics(
      revenueLedgerMismatchCount: mismatchIds.length,
      revenueLedgerMismatchProjectIds: mismatchIds,
      negativeARCount: negativeArIds.length,
      negativeARProjectIds: negativeArIds,
      negativeAdvanceCount: negativeAdvanceIds.length,
      negativeAdvanceProjectIds: negativeAdvanceIds,
      negativeCustomerCreditCount: negativeCreditIds.length,
      negativeCustomerCreditProjectIds: negativeCreditIds,
      cashReconciliationErrors: cashErrors,
    );
  }
}
