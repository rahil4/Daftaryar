import '../db/database_helper.dart';
import '../models/financial_reports.dart';
import '../models/project_economics.dart';
import 'financial_metrics_service.dart';
import 'financial_reporting_service.dart';

/// لایه تحلیل اقتصادی پروژه/مشتری - کاملاً READ-ONLY. هیچ Journal نمی‌سازد،
/// هیچ Cache یا KPI محاسبه‌شده‌ای در دیتابیس ذخیره نمی‌کند. فقط مصرف‌کننده
/// FinancialReportingService/FinancialMetricsService است؛ هیچ فرمول جدید
/// برای مانده‌های Ledger نمی‌سازد - فقط شاخص‌های تحلیلی روی مقادیر آماده.
class ProjectEconomicsService {
  final DatabaseHelper _db;
  final FinancialMetricsService _metrics;
  final FinancialReportingService _reporting;

  ProjectEconomicsService({DatabaseHelper? db, FinancialMetricsService? metrics, FinancialReportingService? reporting})
      : _db = db ?? DatabaseHelper.instance,
        _metrics = metrics ?? FinancialMetricsService(db),
        _reporting = reporting ?? FinancialReportingService(db: db, metrics: metrics);

  // ================= Part 1: Project Economic Analysis =================

  Future<ProjectEconomicAnalysis> getProjectEconomicAnalysis(int projectId) async {
    final report = await _reporting.getProjectReport(projectId);
    final counterparty = await _db.getCounterparty(report.counterpartyId);
    return _buildFullAnalysis(report, counterparty?.name ?? '—');
  }

  ProjectEconomicAnalysis _buildAnalysis(ProjectFinancialReport r, String counterpartyName) {
    // priceVarianceAmount/Rate عیناً از priceIncreaseAmount/Rate موجود
    // بازاستفاده می‌شود (فرمول یکسان: finalAmount - initialEstimate)؛
    // محاسبه مستقل جدیدی انجام نشد.
    final priceVarianceAmount = r.priceIncreaseAmount;
    final priceVarianceRate = r.priceIncreaseRate;

    final revenuePerCostUnit =
        (r.netRevenue != null && r.directProjectCost != 0) ? r.netRevenue! / r.directProjectCost : null;
    final collectionGap = r.netRevenue != null ? r.netRevenue! - r.totalReceived : null;

    return ProjectEconomicAnalysis(
      projectId: r.projectId,
      projectName: r.projectName,
      counterpartyId: r.counterpartyId,
      counterpartyName: counterpartyName,
      initialEstimate: r.initialEstimate,
      priceAdditions: 0, // در ادامه از Metrics پر می‌شود (نیاز به فراخوانی جدا)
      priceReductions: 0,
      netPriceChanges: 0,
      finalAmount: r.finalAmount,
      finalAdjustments: r.finalAdjustments,
      effectiveFinalAmount: r.effectiveFinalAmount,
      grossRevenue: r.grossRevenue,
      discountAmount: r.discountAmount,
      netRevenue: r.netRevenue,
      totalReceived: r.totalReceived,
      advanceBalance: r.advanceBalance,
      receivableBalance: r.receivableBalance,
      customerCredit: r.customerCredit,
      directProjectCost: r.directProjectCost,
      projectContribution: r.projectContribution,
      contributionMargin: r.contributionMargin,
      collectionRate: r.collectionRate,
      outstandingRatio: r.outstandingRatio,
      isFinalized: r.isFinalized,
      isSettled: r.isSettled,
      priceVarianceAmount: priceVarianceAmount,
      priceVarianceRate: priceVarianceRate,
      discountRate: r.discountRate,
      directCostRatio: r.directCostRatio,
      profitabilityStatus: r.profitabilityStatus,
      revenuePerCostUnit: revenuePerCostUnit,
      collectionGap: collectionGap,
    );
  }

  /// نسخه کامل با priceAdditions/priceReductions/netPriceChanges (نیازمند
  /// یک فراخوانی اضافه به Metrics Layer، چون ProjectFinancialReport این دو
  /// فیلد را ندارد - طبق همان قرارداد Reuse-first، نه فرمول موازی)
  Future<ProjectEconomicAnalysis> _buildFullAnalysis(
      ProjectFinancialReport r, String counterpartyName) async {
    final base = _buildAnalysis(r, counterpartyName);
    final m = await _metrics.getProjectMetrics(r.projectId);
    return ProjectEconomicAnalysis(
      projectId: base.projectId,
      projectName: base.projectName,
      counterpartyId: base.counterpartyId,
      counterpartyName: base.counterpartyName,
      initialEstimate: base.initialEstimate,
      priceAdditions: m.priceAdditions,
      priceReductions: m.priceReductions,
      netPriceChanges: m.netPriceChanges,
      finalAmount: base.finalAmount,
      finalAdjustments: base.finalAdjustments,
      effectiveFinalAmount: base.effectiveFinalAmount,
      grossRevenue: base.grossRevenue,
      discountAmount: base.discountAmount,
      netRevenue: base.netRevenue,
      totalReceived: base.totalReceived,
      advanceBalance: base.advanceBalance,
      receivableBalance: base.receivableBalance,
      customerCredit: base.customerCredit,
      directProjectCost: base.directProjectCost,
      projectContribution: base.projectContribution,
      contributionMargin: base.contributionMargin,
      collectionRate: base.collectionRate,
      outstandingRatio: base.outstandingRatio,
      isFinalized: base.isFinalized,
      isSettled: base.isSettled,
      priceVarianceAmount: base.priceVarianceAmount,
      priceVarianceRate: base.priceVarianceRate,
      discountRate: base.discountRate,
      directCostRatio: base.directCostRatio,
      profitabilityStatus: base.profitabilityStatus,
      revenuePerCostUnit: base.revenuePerCostUnit,
      collectionGap: base.collectionGap,
    );
  }

  Future<List<ProjectEconomicAnalysis>> getProjectEconomicAnalyses({
    int? counterpartyId,
    String? projectStatus,
    bool? finalizedOnly,
    bool? settledOnly,
  }) async {
    final reports = await _reporting.getProjectReports(
      counterpartyId: counterpartyId,
      projectStatus: projectStatus,
      finalizedOnly: finalizedOnly,
      settledOnly: settledOnly,
    );
    final results = <ProjectEconomicAnalysis>[];
    for (final r in reports) {
      final counterparty = await _db.getCounterparty(r.counterpartyId);
      results.add(await _buildFullAnalysis(r, counterparty?.name ?? '—'));
    }
    return results;
  }

  // ================= Part 2: Profitability Factors =================

  /// عوامل قابل‌مشاهده مرتبط با سودآوری - فقط گزارش شاخص، بدون ادعای علّی
  Future<ProjectProfitabilityFactors> getProjectProfitabilityFactors(int projectId) async {
    final a = await getProjectEconomicAnalysis(projectId);
    final notable = <String>[];
    if (a.directCostRatio != null && a.directCostRatio! > ProfitabilityFactorThresholds.highDirectCostRatio) {
      notable.add('نسبت هزینه مستقیم به درآمد بالاست (${a.directCostRatio!.toStringAsFixed(1)}٪)');
    }
    if (a.discountRate != null && a.discountRate! > ProfitabilityFactorThresholds.highDiscountRate) {
      notable.add('نرخ تخفیف نسبت به درآمد ناخالص بالاست (${a.discountRate!.toStringAsFixed(1)}٪)');
    }
    if (a.priceVarianceRate != null &&
        a.priceVarianceRate!.abs() > ProfitabilityFactorThresholds.significantPriceVarianceRate) {
      final direction = a.priceVarianceRate! > 0 ? 'افزایش' : 'کاهش';
      notable.add('$direction قابل‌توجه مبلغ نسبت به برآورد اولیه (${a.priceVarianceRate!.toStringAsFixed(1)}٪)');
    }
    if (a.outstandingRatio != null &&
        a.outstandingRatio! > ProfitabilityFactorThresholds.significantOutstandingRatio) {
      notable.add('نسبت مانده طلب به درآمد خالص قابل‌توجه است (${a.outstandingRatio!.toStringAsFixed(1)}٪)');
    }
    return ProjectProfitabilityFactors(
      projectId: projectId,
      directCostRatio: a.directCostRatio,
      discountRate: a.discountRate,
      priceVarianceRate: a.priceVarianceRate,
      outstandingReceivable: a.receivableBalance,
      outstandingRatio: a.outstandingRatio,
      notableFactors: notable,
    );
  }

  // ================= Part 3: Ranking =================
  // اصل مشترک همه Rankingها: پروژه‌ای که مقدار شاخص موردنظرش null است
  // (چون Finalize نشده یا مخرج صفر بوده)، اصلاً وارد فهرست نمی‌شود - هرگز
  // به‌عنوان 0 در مقایسه شرکت نمی‌کند.

  Future<List<ProjectEconomicAnalysis>> getMostProfitableProjects(int limit) async {
    final all = await getProjectEconomicAnalyses();
    final withContribution = all.where((a) => a.projectContribution != null).toList()
      ..sort((a, b) => b.projectContribution!.compareTo(a.projectContribution!));
    return withContribution.take(limit).toList();
  }

  Future<List<ProjectEconomicAnalysis>> getLeastProfitableProjects(int limit) async {
    final all = await getProjectEconomicAnalyses();
    final withContribution = all.where((a) => a.projectContribution != null).toList()
      ..sort((a, b) => a.projectContribution!.compareTo(b.projectContribution!));
    return withContribution.take(limit).toList();
  }

  Future<List<ProjectEconomicAnalysis>> getHighestCostProjects(int limit) async {
    final all = await getProjectEconomicAnalyses();
    // هزینه مستقیم حتی برای پروژه Finalize‌نشده هم معنا دارد (چون هزینه با
    // ثبت سند ایجاد می‌شود، نه با Finalization)؛ پس صفر واقعی هم قابل قبول است.
    final sorted = [...all]..sort((a, b) => b.directProjectCost.compareTo(a.directProjectCost));
    return sorted.take(limit).toList();
  }

  Future<List<ProjectEconomicAnalysis>> getHighestDiscountProjects(int limit) async {
    final all = await getProjectEconomicAnalyses();
    final withDiscount = all.where((a) => a.discountAmount > 0).toList()
      ..sort((a, b) => b.discountAmount.compareTo(a.discountAmount));
    return withDiscount.take(limit).toList();
  }

  Future<List<ProjectEconomicAnalysis>> getHighestPriceIncreaseProjects(int limit) async {
    final all = await getProjectEconomicAnalyses();
    final withVariance = all.where((a) => a.priceVarianceRate != null).toList()
      ..sort((a, b) => b.priceVarianceRate!.compareTo(a.priceVarianceRate!));
    return withVariance.take(limit).toList();
  }

  Future<List<ProjectEconomicAnalysis>> getHighestOutstandingProjects(int limit) async {
    final all = await getProjectEconomicAnalyses();
    final withOutstanding = all.where((a) => a.receivableBalance > 0).toList()
      ..sort((a, b) => b.receivableBalance.compareTo(a.receivableBalance));
    return withOutstanding.take(limit).toList();
  }

  // ================= Part 4: Benchmark =================

  /// میانگین‌های مرجع - فقط از پروژه‌های Finalized؛ هر شاخص جداگانه فقط از
  /// نمونه‌های معتبر (غیر-null) خودش میانگین می‌گیرد.
  Future<ProjectBenchmark> getBenchmark({int? counterpartyId}) async {
    final all = await getProjectEconomicAnalyses(counterpartyId: counterpartyId, finalizedOnly: true);

    double? avg(Iterable<double?> values) {
      final valid = values.whereType<double>().toList();
      if (valid.isEmpty) return null;
      return valid.reduce((a, b) => a + b) / valid.length;
    }

    return ProjectBenchmark(
      finalizedProjectCount: all.length,
      averageNetRevenue: avg(all.map((a) => a.netRevenue)),
      averageDirectCost: avg(all.map((a) => a.directProjectCost)),
      averageContribution: avg(all.map((a) => a.projectContribution)),
      averageContributionMargin: avg(all.map((a) => a.contributionMargin)),
      averageDiscountRate: avg(all.map((a) => a.discountRate)),
      averagePriceVarianceRate: avg(all.map((a) => a.priceVarianceRate)),
      averageCollectionRate: avg(all.map((a) => a.collectionRate)),
    );
  }

  // ================= Part 5: Customer Economic Analysis =================

  Future<CustomerEconomicAnalysis> getCustomerEconomicAnalysis(int counterpartyId) async {
    final counterparty = await _db.getCounterparty(counterpartyId);
    // مقادیر پایه از CustomerFinancialReport موجود بازاستفاده می‌شوند (که
    // خودش totalReceived/receivableBalance را مستقیم از Ledger سطح-
    // طرف‌حساب می‌خواند، نه با جمع پروژه‌ها بازسازی می‌کند).
    final cr = await _reporting.getCustomerReport(counterpartyId);
    final projects = await getProjectEconomicAnalyses(counterpartyId: counterpartyId);
    final finalizedWithContribution =
        projects.where((p) => p.isFinalized && p.projectContribution != null).toList();

    int? mostProfitableId, leastProfitableId;
    if (finalizedWithContribution.isNotEmpty) {
      final sorted = [...finalizedWithContribution]
        ..sort((a, b) => b.projectContribution!.compareTo(a.projectContribution!));
      mostProfitableId = sorted.first.projectId;
      leastProfitableId = sorted.last.projectId;
    }

    final averageContributionPerProject = (cr.projectContribution != null && cr.finalizedProjectCount > 0)
        ? cr.projectContribution! / cr.finalizedProjectCount
        : null;

    return CustomerEconomicAnalysis(
      counterpartyId: counterpartyId,
      counterpartyName: counterparty?.name ?? '—',
      projectCount: cr.projectCount,
      finalizedProjectCount: cr.finalizedProjectCount,
      totalNetRevenue: cr.netRevenue,
      totalDirectCost: cr.directProjectCost,
      totalContribution: cr.projectContribution,
      contributionMargin: cr.contributionMargin,
      totalDiscount: cr.discountAmount,
      discountRate: cr.grossRevenue != 0 ? (cr.discountAmount / cr.grossRevenue) * 100 : null,
      totalReceived: cr.totalReceived,
      receivableBalance: cr.receivableBalance,
      collectionRate: cr.collectionRate,
      averageProjectValue: cr.averageProjectValue,
      averageContributionPerProject: averageContributionPerProject,
      mostProfitableProjectId: mostProfitableId,
      leastProfitableProjectId: leastProfitableId,
    );
  }

  Future<List<CustomerEconomicAnalysis>> getAllCustomerEconomicAnalyses() async {
    final allProjects = await _db.getProjects();
    final counterpartyIds = allProjects.map((p) => p.counterpartyId).toSet();
    final results = <CustomerEconomicAnalysis>[];
    for (final id in counterpartyIds) {
      results.add(await getCustomerEconomicAnalysis(id));
    }
    return results;
  }
}
