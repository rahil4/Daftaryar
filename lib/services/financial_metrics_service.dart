import '../db/database_helper.dart';
import '../models/financial_metrics.dart';
import '../models/project.dart';
import '../models/project_price_event.dart';

/// لایه مستقل محاسبه شاخص‌های مالی (Financial Metrics Layer).
///
/// این سرویس هرگز Journal ایجاد یا حذف نمی‌کند و هیچ مقدار مالی مستقلی هم
/// ذخیره نمی‌کند؛ فقط از Ledger و جداول موجود (Project، ProjectPriceEvent،
/// JournalLine) می‌خواند و شاخص‌ها را در لحظه محاسبه می‌کند. برای مانده‌های
/// پایه (AR/Advance/CustomerCredit/...) همیشه از توابع موجود در
/// DatabaseHelper استفاده می‌کند، نه فرمول موازی.
/// نتیجه یک‌بار بارگذاری دسته‌ای شاخص‌های همه پروژه‌ها - بین همه
/// گزارش‌های یک بارگذاری (پروژه‌ها، مشتریان، تشخیص‌ها) به اشتراک گذاشته
/// می‌شود تا هر پروژه فقط یک‌بار محاسبه شود. هیچ‌چیز ذخیره/Cache ماندگار
/// نمی‌شود؛ عمر این شیء فقط همان یک بارگذاری است.
class ProjectMetricsSnapshot {
  final List<ProjectModel> projects; // همان ترتیب getProjects (جدیدترین اول)
  final Map<int, ProjectFinancialMetrics> metricsById;
  final Map<int, List<ProjectPriceEventModel>> eventsByProject;
  final Map<int, double> revenueLedgerByProject;

  const ProjectMetricsSnapshot({
    required this.projects,
    required this.metricsById,
    required this.eventsByProject,
    required this.revenueLedgerByProject,
  });
}

class FinancialMetricsService {
  final DatabaseHelper _db;
  FinancialMetricsService([DatabaseHelper? db]) : _db = db ?? DatabaseHelper.instance;

  // ================= Project Level =================

  Future<ProjectFinancialMetrics> getProjectMetrics(int projectId) async {
    final project = await _db.getProject(projectId);
    if (project == null) {
      throw Exception('پروژه یافت نشد.');
    }
    return _computeProjectMetrics(project);
  }

  Future<ProjectFinancialMetrics> _computeProjectMetrics(ProjectModel project) async {
    final projectId = project.id!;
    final events = await _db.getProjectPriceEvents(projectId);
    final cashFlow = await _db.projectFinancials(projectId); // received واقعی نقدی، نه Revenue
    return _buildProjectMetrics(
      project,
      events,
      totalReceived: cashFlow['received']!,
      advanceBalance: await _db.projectAdvanceBalance(projectId),
      receivableBalance: await _db.projectReceivableBalance(projectId),
      customerCredit: await _db.projectCustomerCreditBalance(projectId),
      directProjectCost: await _db.projectDirectCost(projectId),
    );
  }

  /// تنها محل فرمول شاخص‌های پروژه - بدون هیچ دسترسی به دیتابیس. هم مسیر
  /// تک‌پروژه‌ای (_computeProjectMetrics) و هم مسیر دسته‌ای (loadSnapshot)
  /// مقادیر پایه را به همین تابع می‌دهند، پس دو فرمول موازی وجود ندارد؛
  /// فقط شیوه خواندن مقادیر پایه از Ledger فرق می‌کند.
  ProjectFinancialMetrics _buildProjectMetrics(
    ProjectModel project,
    List<ProjectPriceEventModel> events, {
    required double totalReceived,
    required double advanceBalance,
    required double receivableBalance,
    required double customerCredit,
    required double directProjectCost,
  }) {
    final projectId = project.id!;

    final priceAdditions = events
        .where((e) => e.type == kPriceEventAddition)
        .fold<double>(0, (s, e) => s + e.amount);
    final priceReductions = events
        .where((e) => e.type == kPriceEventReduction)
        .fold<double>(0, (s, e) => s + e.amount.abs());
    final netPriceChanges = priceAdditions - priceReductions;

    final finalAdjustments = events
        .where((e) => e.type == kPriceEventFinalAdjustment)
        .fold<double>(0, (s, e) => s + e.amount);
    final discountAmount =
        events.where((e) => e.type == kPriceEventDiscount).fold<double>(0, (s, e) => s + e.amount.abs());

    final finalAmount = project.finalAmount; // اصلی، هرگز overwrite نمی‌شود
    final effectiveFinalAmount = finalAmount != null ? finalAmount + finalAdjustments : null;

    // اصل مهم: Revenue هرگز از Cash Received محاسبه نمی‌شود؛ فقط از
    // Finalization/Adjustment می‌آید.
    final grossRevenue = project.isFinalized ? effectiveFinalAmount : null;
    final netRevenue = grossRevenue != null ? grossRevenue - discountAmount : null;

    final projectContribution = netRevenue != null ? netRevenue - directProjectCost : null;
    final contributionMargin = (netRevenue != null && netRevenue != 0)
        ? (projectContribution! / netRevenue) * 100
        : null;
    final collectionRate =
        (netRevenue != null && netRevenue != 0) ? (totalReceived / netRevenue) * 100 : null;
    final outstandingRatio =
        (netRevenue != null && netRevenue != 0) ? (receivableBalance / netRevenue) * 100 : null;

    // نکته مهم متن: این شاخص از finalAmount (نه effectiveFinalAmount) استفاده
    // می‌کند، چون هدف مقایسه برآورد اولیه با Finalization اصلی است، نه
    // وضعیت مالی فعلی که ممکن است شامل اصلاحات بعدی هم باشد.
    final priceIncreaseAmount = finalAmount != null ? finalAmount - project.agreedAmount : null;
    final priceIncreaseRate = (finalAmount != null && project.agreedAmount != 0)
        ? ((finalAmount - project.agreedAmount) / project.agreedAmount) * 100
        : null;

    // همان تعریف DatabaseHelper.isProjectSettled: نهایی‌شده + بدون مانده
    // طلب/پیش‌دریافت.
    final isSettled = project.isFinalized && advanceBalance == 0 && receivableBalance == 0;

    return ProjectFinancialMetrics(
      projectId: projectId,
      initialEstimate: project.agreedAmount,
      priceAdditions: priceAdditions,
      priceReductions: priceReductions,
      netPriceChanges: netPriceChanges,
      finalAmount: finalAmount,
      finalAdjustments: finalAdjustments,
      effectiveFinalAmount: effectiveFinalAmount,
      grossRevenue: grossRevenue,
      discountAmount: discountAmount,
      netRevenue: netRevenue,
      totalReceived: totalReceived,
      advanceBalance: advanceBalance,
      receivableBalance: receivableBalance,
      customerCredit: customerCredit,
      directProjectCost: directProjectCost,
      projectContribution: projectContribution,
      contributionMargin: contributionMargin,
      collectionRate: collectionRate,
      outstandingRatio: outstandingRatio,
      priceIncreaseAmount: priceIncreaseAmount,
      priceIncreaseRate: priceIncreaseRate,
      isFinalized: project.isFinalized,
      isSettled: isSettled,
      status: project.status,
      finalizedDate: project.finalizedDate,
    );
  }

  /// شاخص‌های همه پروژه‌ها در تعداد ثابتی کوئری (مستقل از تعداد پروژه)،
  /// برای گزارش‌هایی که به کل پروژه‌ها نیاز دارند (داشبورد، عملکرد عملیاتی،
  /// سود مشتریان). مسیر تک‌پروژه‌ای برای هر پروژه چندین کوئری جدا می‌زند و
  /// وقتی برای همه پروژه‌ها (و چند بار در یک بارگذاری) تکرار می‌شد، زمان
  /// بارگذاری را با تعداد پروژه خطی بالا می‌برد. فرمول‌ها همان
  /// _buildProjectMetrics هستند.
  Future<ProjectMetricsSnapshot> loadSnapshot() async {
    final projects = await _db.getProjects();
    final aggregates = await _db.projectLedgerAggregates();
    final allEvents = await _db.getAllPriceEventsInRange();
    final eventsByProject = <int, List<ProjectPriceEventModel>>{};
    for (final e in allEvents) {
      (eventsByProject[e.projectId] ??= []).add(e);
    }

    final metricsById = <int, ProjectFinancialMetrics>{};
    for (final p in projects) {
      final id = p.id!;
      metricsById[id] = _buildProjectMetrics(
        p,
        eventsByProject[id] ?? const [],
        totalReceived: aggregates.received[id] ?? 0,
        advanceBalance: aggregates.advance[id] ?? 0,
        receivableBalance: aggregates.receivable[id] ?? 0,
        customerCredit: aggregates.customerCredit[id] ?? 0,
        directProjectCost: aggregates.directCost[id] ?? 0,
      );
    }
    return ProjectMetricsSnapshot(
      projects: projects,
      metricsById: metricsById,
      eventsByProject: eventsByProject,
      revenueLedgerByProject: aggregates.revenueLedger,
    );
  }

  /// بررسی داخلی تطبیق: مقدار Revenue محاسبه‌شده از جدول Project+PriceEvent
  /// را با مانده واقعی حساب درآمد در Ledger مقایسه می‌کند. برای AR/Advance/
  /// CustomerCredit نیازی به این بررسی نیست چون در این معماری فقط یک منبع
  /// (خودِ Ledger) برایشان وجود دارد؛ اما Revenue از دو مسیر مفهومی متفاوت
  /// (فیلد Project + جدول PriceEvent در برابر حساب Ledger) قابل استخراج است،
  /// پس ناسازگاری احتمالی (مثلاً یک سند دستی که این حساب را بدون عبور از
  /// recordFinalAdjustment دستکاری کرده) قابل کشف است.
  Future<ProjectReconciliation> reconcileProject(int projectId) async {
    final project = await _db.getProject(projectId);
    if (project == null) throw Exception('پروژه یافت نشد.');
    if (!project.isFinalized) {
      return ProjectReconciliation(
        projectId: projectId,
        calculatedGrossRevenue: 0,
        ledgerRevenueBalance: 0,
        revenueMatches: true,
        status: 'NOT_APPLICABLE',
        note: 'پروژه هنوز Finalize نشده؛ درآمدی برای تطبیق وجود ندارد.',
      );
    }
    final events = await _db.getProjectPriceEvents(projectId);
    final finalAdjustments = events
        .where((e) => e.type == kPriceEventFinalAdjustment)
        .fold<double>(0, (s, e) => s + e.amount);
    final discountAmount =
        events.where((e) => e.type == kPriceEventDiscount).fold<double>(0, (s, e) => s + e.amount.abs());
    final calculatedGrossRevenue = project.finalAmount! + finalAdjustments;
    final ledgerRevenueBalance = await _db.projectRevenueLedgerBalance(projectId);
    final matches = (calculatedGrossRevenue - ledgerRevenueBalance).abs() < 1;
    return ProjectReconciliation(
      projectId: projectId,
      calculatedGrossRevenue: calculatedGrossRevenue,
      ledgerRevenueBalance: ledgerRevenueBalance,
      revenueMatches: matches,
      status: matches ? 'OK' : 'MISMATCH',
      finalAmount: project.finalAmount,
      finalAdjustments: finalAdjustments,
      discountAmount: discountAmount,
      note: matches
          ? null
          : 'مانده واقعی حساب درآمد در Ledger با finalAmount+FINAL_ADJUSTMENTها یکسان نیست؛ احتمالاً سندی خارج از مسیر رسمی (finalizeProject/recordFinalAdjustment) این حساب را برای این پروژه دستکاری کرده.',
    );
  }

  // ================= Customer Level =================

  /// شاخص‌های مالی یک طرف حساب در نقش مشتری. طبق قرارداد این مرحله،
  /// projectCount = تعداد پروژه‌های Finalized (چون پروژه غیرنهایی هنوز
  /// Revenue قطعی ندارد). مقادیر مستقیماً از حساب‌های سطح-طرف‌حساب خوانده
  /// می‌شوند (نه با جمع‌زدن Metrics هر پروژه)، تا سطرهایی که به طرف حساب
  /// وصل‌اند ولی projectId ندارند هم به‌درستی لحاظ شوند.
  ///
  /// تصمیم صریح Time-Basis (مرحله Reporting Semantics، مورد ۵): پیش‌تر
  /// «directProjectCost» روی همه پروژه‌ها (حتی Finalize‌نشده) جمع می‌شد در
  /// حالی که Revenue فقط از پروژه‌های Finalized می‌آمد - یعنی صورت و مخرج
  /// Contribution/Margin از دو جمعیت متفاوت بودند. تصمیم گرفته شد:
  /// - directProjectCost (این فیلد) اکنون فقط پروژه‌های Finalized را شامل
  ///   می‌شود، دقیقاً هم‌جمعیت با Revenue - تا Contribution/Margin معنای
  ///   مالی درستی داشته باشند (سود واقعی همان کارِ درآمدزاشده).
  /// - directProjectCostAllProjects (فیلد جدید) هزینه واقعی صرف‌شده روی
  ///   تمام پروژه‌های این مشتری را - شامل پروژه‌های در جریان (WIP) - جداگانه
  ///   و با نام صریح گزارش می‌کند، تا این اطلاعات از بین نرود.
  ///
  /// [snapshot] اختیاری: اگر داده شود، شاخص‌های پروژه از همان نتیجه دسته‌ای
  /// خوانده می‌شوند (به‌جای محاسبه دوباره برای هر پروژه).
  Future<CustomerFinancialMetrics> getCustomerMetrics(int counterpartyId,
      {ProjectMetricsSnapshot? snapshot}) async {
    final allProjects = snapshot != null
        ? snapshot.projects.where((p) => p.counterpartyId == counterpartyId).toList()
        : await _db.getProjects(counterpartyId: counterpartyId);
    final finalizedProjects = allProjects.where((p) => p.isFinalized).toList();

    double grossRevenue = 0;
    double discountAmount = 0;
    double directProjectCost = 0;
    for (final p in finalizedProjects) {
      final m = snapshot?.metricsById[p.id!] ?? await _computeProjectMetrics(p);
      grossRevenue += m.grossRevenue ?? 0;
      discountAmount += m.discountAmount;
      directProjectCost += m.directProjectCost;
    }
    final netRevenue = grossRevenue - discountAmount;

    final cashFlow = await _db.counterpartyFinancials(counterpartyId);
    final totalReceived = cashFlow['received']!;
    final receivableBalance = await _db.receivableBalance(counterpartyId);
    final customerCredit = await _db.counterpartyCustomerCreditBalance(counterpartyId);

    double directProjectCostAllProjects = 0;
    for (final p in allProjects) {
      directProjectCostAllProjects +=
          snapshot?.metricsById[p.id!]?.directProjectCost ?? await _db.projectDirectCost(p.id!);
    }

    final projectContribution = netRevenue - directProjectCost;
    final contributionMargin = netRevenue != 0 ? (projectContribution / netRevenue) * 100 : null;
    final collectionRate = netRevenue != 0 ? (totalReceived / netRevenue) * 100 : null;
    final outstandingRatio = netRevenue != 0 ? (receivableBalance / netRevenue) * 100 : null;
    final averageProjectValue =
        finalizedProjects.isNotEmpty ? netRevenue / finalizedProjects.length : null;
    final averageDiscountRate = grossRevenue != 0 ? (discountAmount / grossRevenue) * 100 : null;

    return CustomerFinancialMetrics(
      counterpartyId: counterpartyId,
      projectCount: finalizedProjects.length,
      grossRevenue: grossRevenue,
      discountAmount: discountAmount,
      netRevenue: netRevenue,
      totalReceived: totalReceived,
      receivableBalance: receivableBalance,
      customerCredit: customerCredit,
      directProjectCost: directProjectCost,
      directProjectCostAllProjects: directProjectCostAllProjects,
      projectContribution: projectContribution,
      contributionMargin: contributionMargin,
      collectionRate: collectionRate,
      outstandingRatio: outstandingRatio,
      averageProjectValue: averageProjectValue,
      averageDiscountRate: averageDiscountRate,
    );
  }

  // ================= Office Level =================

  Future<OfficeFinancialMetrics> getOfficeMetrics({String? fromDate, String? toDate}) async {
    final grossRevenue = await _db.officeGrossRevenue(fromDate: fromDate, toDate: toDate);
    final discountAmount = await _db.officeDiscountTotal(fromDate: fromDate, toDate: toDate);
    final netRevenue = grossRevenue - discountAmount;
    final directProjectCost = await _db.officeDirectCostTotal(fromDate: fromDate, toDate: toDate);
    final projectContribution = netRevenue - directProjectCost;
    final projectOverhead = await _db.officeOverheadTotal(fromDate: fromDate, toDate: toDate);
    final officeExpense = await _db.officeExpenseTotal(fromDate: fromDate, toDate: toDate);
    final operatingResult = projectContribution - projectOverhead - officeExpense;
    final operatingMargin = netRevenue != 0 ? (operatingResult / netRevenue) * 100 : null;

    return OfficeFinancialMetrics(
      fromDate: fromDate,
      toDate: toDate,
      grossRevenue: grossRevenue,
      discountAmount: discountAmount,
      netRevenue: netRevenue,
      directProjectCost: directProjectCost,
      projectContribution: projectContribution,
      projectOverhead: projectOverhead,
      officeExpense: officeExpense,
      operatingResult: operatingResult,
      operatingMargin: operatingMargin,
    );
  }

  // ================= Cash Flow =================

  Future<CashFlowMetrics> getCashFlowMetrics({String? fromDate, String? toDate}) async {
    // اگر fromDate مشخص نباشد یعنی از ابتدای عمر سیستم؛ موجودی «پیش از آن»
    // طبیعتاً صفر است، نه موجودی فعلی.
    final opening = fromDate != null ? await _db.cashBalanceBefore(fromDate) : 0.0;
    final closing = await _db.cashBalanceThrough(throughDate: toDate);
    final buckets = await _db.classifyCashFlow(fromDate: fromDate, toDate: toDate);

    return CashFlowMetrics(
      fromDate: fromDate,
      toDate: toDate,
      openingCash: opening,
      customerReceipts: buckets['customerReceipts']!,
      otherCashInflows: buckets['otherCashInflows']!,
      projectPayments: buckets['projectPayments']!,
      projectOverheadPayments: buckets['projectOverheadPayments']!,
      officePayments: buckets['officePayments']!,
      otherCashOutflows: buckets['otherCashOutflows']!,
      closingCash: closing,
    );
  }
}
