/// مدل‌های لایه گزارش‌دهی مدیریتی (Financial Reporting Layer).
/// همگی DTO محاسباتی‌اند، هیچ‌کدام جدول دیتابیس نیستند.
library financial_reports;

// ================= Enums =================

/// طبقه‌بندی سودآوری پروژه بر اساس Contribution Margin. آستانه‌ها در
/// [ProfitabilityThresholds] به‌صورت ثابت کد شده‌اند (نه در دیتابیس)، چون
/// معماری فعلی زیرساخت تنظیمات قابل‌ویرایش کاربر برای این مقادیر را ندارد.
enum ProjectProfitabilityStatus { unknown, loss, lowMargin, normalMargin, highMargin }

/// آستانه‌های طبقه‌بندی سودآوری - یک Configuration ثابت در لایه Analytics.
class ProfitabilityThresholds {
  static const double lowMarginMax = 15; // زیر ۱۵٪ = LowMargin
  static const double normalMarginMax = 35; // ۱۵ تا ۳۵٪ = NormalMargin، بالاتر = HighMargin

  static ProjectProfitabilityStatus classify(double? contribution, double? contributionMargin) {
    if (contribution == null || contributionMargin == null) {
      return ProjectProfitabilityStatus.unknown;
    }
    if (contribution < 0) return ProjectProfitabilityStatus.loss;
    if (contributionMargin < lowMarginMax) return ProjectProfitabilityStatus.lowMargin;
    if (contributionMargin <= normalMarginMax) return ProjectProfitabilityStatus.normalMargin;
    return ProjectProfitabilityStatus.highMargin;
  }
}

/// وضعیت درآمد پروژه - مستقل از وضعیت عملیاتی (status) و وضعیت تسویه.
enum RevenueStatus { notFinalized, finalized, adjusted }

enum SettlementStatus { unsettled, settled }

enum CreditStatus { noCredit, hasCredit }

/// معیار مرتب‌سازی گزارش مشتریان - به‌جای Hard-Code در SQL.
enum CustomerReportSort {
  netRevenue,
  contribution,
  contributionMargin,
  received,
  outstandingAR,
  projectCount,
}

/// معیار مرتب‌سازی گزارش پروژه‌ها.
enum ProjectReportSort {
  contribution,
  contributionMargin,
  netRevenue,
  directCost,
  priceIncreaseRate,
  discountRate,
}

// ================= Project Level =================

class ProjectFinancialReport {
  final int projectId;
  final String projectName;
  final int counterpartyId;

  final double initialEstimate;
  final double? finalAmount;
  final double? effectiveFinalAmount;

  final double? grossRevenue;
  final double discountAmount;
  final double? netRevenue;

  final double totalReceived;
  final double advanceBalance;
  final double receivableBalance;
  final double customerCredit;

  final double directProjectCost;
  final double? projectContribution;
  final double? contributionMargin;

  // Estimate → Original Finalization
  final double? priceIncreaseAmount;
  final double? priceIncreaseRate;
  // Finalization → Current Effective (اثر خالص FINAL_ADJUSTMENTها)
  final double finalAdjustments;
  // Estimate → Current Effective (مجموع دو مورد بالا)
  final double? estimateToEffectiveVariance;

  final double? collectionRate;
  final double? outstandingRatio;
  final double? directCostRatio; // directProjectCost / netRevenue * 100
  final double? discountRate; // discountAmount / grossRevenue * 100

  final bool isFinalized;
  final bool isSettled;

  final RevenueStatus revenueStatus;
  final SettlementStatus settlementStatus;
  final CreditStatus creditStatus;
  final ProjectProfitabilityStatus profitabilityStatus;

  ProjectFinancialReport({
    required this.projectId,
    required this.projectName,
    required this.counterpartyId,
    required this.initialEstimate,
    required this.finalAmount,
    required this.effectiveFinalAmount,
    required this.grossRevenue,
    required this.discountAmount,
    required this.netRevenue,
    required this.totalReceived,
    required this.advanceBalance,
    required this.receivableBalance,
    required this.customerCredit,
    required this.directProjectCost,
    required this.projectContribution,
    required this.contributionMargin,
    required this.priceIncreaseAmount,
    required this.priceIncreaseRate,
    required this.finalAdjustments,
    required this.estimateToEffectiveVariance,
    required this.collectionRate,
    required this.outstandingRatio,
    required this.directCostRatio,
    required this.discountRate,
    required this.isFinalized,
    required this.isSettled,
    required this.revenueStatus,
    required this.settlementStatus,
    required this.creditStatus,
    required this.profitabilityStatus,
  });

  /// طبق تصریح متن: هرگز به‌جای سود معرفی نشود؛ فقط نشان می‌دهد چه بخشی از
  /// درآمد خالص هنوز وصول نشده است.
  double? get uncollectedRevenue => netRevenue != null ? netRevenue! - totalReceived : null;
}

// ================= Customer Level =================

class CustomerFinancialReport {
  final int counterpartyId;

  final int projectCount;
  final int finalizedProjectCount;
  final int settledProjectCount;
  final int profitableProjectCount;
  final int lossProjectCount;

  final double grossRevenue;
  final double discountAmount;
  final double netRevenue;

  final double totalReceived;
  final double receivableBalance;
  final double customerCredit;

  /// هم‌جمعیت با Revenue/Discount (فقط پروژه‌های Finalized) - رجوع به
  /// CustomerFinancialMetrics.directProjectCost برای توضیح کامل تصمیم.
  final double directProjectCost;
  /// هزینه مستقیم تمام پروژه‌ها شامل WIP - در Contribution/Margin استفاده
  /// نمی‌شود، فقط جهت اطلاع در دسترس است.
  final double directProjectCostAllProjects;
  final double? projectContribution;
  final double? contributionMargin;

  /// نسبت Lifetime، نه Period.
  final double? collectionRate;
  /// نسبت Closing AR (کل عمر) به Net Revenue (کل عمر) - Lifetime.
  final double? outstandingRatio;

  final double? averageProjectValue;
  final double? averageDiscountRate;

  /// سهم این مشتری از درآمد خالص کل دفتر - null اگر درآمد دفتر صفر باشد یا
  /// در این محاسبه مشخص نشده باشد (توسط سرویس پر می‌شود). این شاخص Lifetime
  /// است؛ رجوع به گزارش نهایی مرحله Reporting Semantics برای دلیل عدم وجود
  /// نسخه Period-based (نیازمند Attribution دقیق‌تر که معماری فعلی ندارد).
  final double? revenueShareOfOffice;

  CustomerFinancialReport({
    required this.counterpartyId,
    required this.projectCount,
    required this.finalizedProjectCount,
    required this.settledProjectCount,
    required this.profitableProjectCount,
    required this.lossProjectCount,
    required this.grossRevenue,
    required this.discountAmount,
    required this.netRevenue,
    required this.totalReceived,
    required this.receivableBalance,
    required this.customerCredit,
    required this.directProjectCost,
    required this.directProjectCostAllProjects,
    required this.projectContribution,
    required this.contributionMargin,
    required this.collectionRate,
    required this.outstandingRatio,
    required this.averageProjectValue,
    required this.averageDiscountRate,
    this.revenueShareOfOffice,
  });
}

// ================= Period Level =================

/// گزارش یک بازه زمانی - همیشه صریحاً «Period» است، نه «Lifetime».
/// طبق قانون این مرحله: Revenue بر مبنای تاریخ سند Finalization، Received بر
/// مبنای تاریخ سند دریافت، Cost بر مبنای تاریخ سند هزینه - نه تاریخ ایجاد پروژه.
class PeriodFinancialReport {
  final String? fromDate;
  final String? toDate;

  final double grossRevenue;
  final double discountAmount;
  final double netRevenue;

  final double directProjectCost;
  final double? projectContribution;

  final double projectOverhead;
  final double officeExpense;

  final double? operatingResult;
  final double? operatingMargin;

  final double customerReceipts;
  final double otherCashInflows;
  final double projectPayments;
  final double projectOverheadPayments;
  final double officePayments;
  final double otherCashOutflows;
  final double openingCash;
  final double closingCash;

  /// طبق تصریح متن: این عدد فقط نشان می‌دهد چه بخشی از درآمد وصول نشده،
  /// هرگز به‌عنوان «سود» نمایش داده نمی‌شود (Accrual ≠ Cash).
  double get netRevenueMinusReceived => netRevenue - customerReceipts;

  double get totalInflows => customerReceipts + otherCashInflows;
  double get totalOutflows =>
      projectPayments + projectOverheadPayments + officePayments + otherCashOutflows;
  double get netCashChange => totalInflows - totalOutflows;

  /// نتیجه بررسی تطبیق جریان نقدی: openingCash + inflows - outflows == closingCash
  bool get cashReconciles => (openingCash + totalInflows - totalOutflows - closingCash).abs() < 1;

  PeriodFinancialReport({
    this.fromDate,
    this.toDate,
    required this.grossRevenue,
    required this.discountAmount,
    required this.netRevenue,
    required this.directProjectCost,
    required this.projectContribution,
    required this.projectOverhead,
    required this.officeExpense,
    required this.operatingResult,
    required this.operatingMargin,
    required this.customerReceipts,
    required this.otherCashInflows,
    required this.projectPayments,
    required this.projectOverheadPayments,
    required this.officePayments,
    required this.otherCashOutflows,
    required this.openingCash,
    required this.closingCash,
  });
}

/// مقایسه عمومی دو بازه برای هر شاخص عددی - یک مدل واحد برای Revenue Growth،
/// Contribution Growth، Operating Result Growth، Cash Received Growth و....
class FinancialPeriodComparison {
  final String metricName;
  final double currentValue;
  final double? previousValue;
  final double? growthAmount;
  final double? growthRate;

  FinancialPeriodComparison._({
    required this.metricName,
    required this.currentValue,
    required this.previousValue,
    required this.growthAmount,
    required this.growthRate,
  });

  factory FinancialPeriodComparison.compute({
    required String metricName,
    required double current,
    required double? previous,
  }) {
    final growthAmount = previous != null ? current - previous : null;
    // مورد ۲۴ مرحله Reporting Semantics: برای شاخص‌هایی که می‌توانند منفی
    // باشند (مثل Contribution/Operating Result در یک دوره زیان‌ده)، اگر
    // مستقیم از previous (نه قدرمطلق آن) به‌عنوان مخرج استفاده شود، ممکن
    // است علامت نرخ رشد معکوس و گمراه‌کننده شود - مثلاً رفتن از -10 به +10
    // با فرمول ساده (current-previous)/previous به‌جای رشد مثبت، عدد
    // "-200%" می‌دهد. استفاده از قدرمطلق مخرج این مشکل را برای همه
    // Metricها (چه همیشه مثبت مثل Revenue، چه بالقوه منفی) به‌طور یکسان و
    // صحیح حل می‌کند.
    final growthRate =
        (previous != null && previous != 0) ? ((current - previous) / previous.abs()) * 100 : null;
    return FinancialPeriodComparison._(
      metricName: metricName,
      currentValue: current,
      previousValue: previous,
      growthAmount: growthAmount,
      growthRate: growthRate,
    );
  }
}

// ================= Management Summary =================

class ManagementFinancialSummary {
  final String? fromDate;
  final String? toDate;

  final double netRevenue;
  final double totalReceived;

  final double directProjectCost;
  final double? projectContribution;

  final double projectOverhead;
  final double officeExpense;
  final double? operatingResult;
  final double? operatingMargin;

  final double receivableBalance;
  final double advanceBalance;
  final double customerCredit;

  final int projectCount;
  final int finalizedProjectCount;
  final int settledProjectCount;
  final int profitableProjectCount;
  final int lossProjectCount;

  final List<FinancialPeriodComparison> comparisons;

  ManagementFinancialSummary({
    this.fromDate,
    this.toDate,
    required this.netRevenue,
    required this.totalReceived,
    required this.directProjectCost,
    required this.projectContribution,
    required this.projectOverhead,
    required this.officeExpense,
    required this.operatingResult,
    required this.operatingMargin,
    required this.receivableBalance,
    required this.advanceBalance,
    required this.customerCredit,
    required this.projectCount,
    required this.finalizedProjectCount,
    required this.settledProjectCount,
    required this.profitableProjectCount,
    required this.lossProjectCount,
    this.comparisons = const [],
  });
}

// ================= Diagnostics =================

class FinancialReportDiagnostics {
  final int revenueLedgerMismatchCount;
  final List<int> revenueLedgerMismatchProjectIds;
  final int negativeARCount;
  final List<int> negativeARProjectIds;
  final int negativeAdvanceCount;
  final List<int> negativeAdvanceProjectIds;
  final int negativeCustomerCreditCount;
  final List<int> negativeCustomerCreditProjectIds;
  final int cashReconciliationErrors;

  const FinancialReportDiagnostics({
    this.revenueLedgerMismatchCount = 0,
    this.revenueLedgerMismatchProjectIds = const [],
    this.negativeARCount = 0,
    this.negativeARProjectIds = const [],
    this.negativeAdvanceCount = 0,
    this.negativeAdvanceProjectIds = const [],
    this.negativeCustomerCreditCount = 0,
    this.negativeCustomerCreditProjectIds = const [],
    this.cashReconciliationErrors = 0,
  });

  bool get hasIssues =>
      revenueLedgerMismatchCount > 0 ||
      negativeARCount > 0 ||
      negativeAdvanceCount > 0 ||
      negativeCustomerCreditCount > 0 ||
      cashReconciliationErrors > 0;
}

/// بسته‌بندی نتیجه یک گزارش تحلیلی همراه با هشدارها/تشخیص‌ها - به‌جای
/// Exception برای خطاهای تحلیلی (نه خطای برنامه/دیتابیس که همچنان Exception
/// باقی می‌ماند).
class FinancialReportResult<T> {
  final T data;
  final List<String> warnings;
  final FinancialReportDiagnostics? diagnostics;

  const FinancialReportResult({
    required this.data,
    this.warnings = const [],
    this.diagnostics,
  });
}
