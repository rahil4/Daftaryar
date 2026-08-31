import 'financial_reports.dart';

/// یک نقطه در نمودار روند ماهانه - فقط برچسب و مقدار
class TrendPoint {
  final String label; // مثلاً «مرداد ۱۴۰۴»
  final double? value; // null یعنی غیرقابل‌محاسبه، نه صفر
  TrendPoint({required this.label, required this.value});
}

/// یک هشدار مدیریتی Rule-Based (نه AI)
class ManagementAlert {
  final String title;
  final String message;
  final ManagementAlertSeverity severity;
  ManagementAlert({required this.title, required this.message, required this.severity});
}

enum ManagementAlertSeverity { info, warning, error }

/// مقدار یک KPI همراه با تغییر نسبت به دوره قبل - null-safe از ابتدا
class KpiValue {
  final double? value;
  final double? previousValue;
  final double? growthRate; // درصد؛ null اگر previousValue صفر/نامعلوم باشد

  KpiValue({required this.value, this.previousValue, this.growthRate});
}

/// View Model کامل داشبورد مدیریتی - فقط برای نمایش، هرگز در دیتابیس
/// ذخیره نمی‌شود و خودش هیچ محاسبه Ledger‌ای انجام نمی‌دهد؛ همه مقادیرش از
/// FinancialReportingService/FinancialMetricsService پر می‌شوند.
///
/// طبقه‌بندی صریح Time Basis (مورد ۷/۲۰ مرحله Reporting Semantics):
///
/// == PERIOD METRICS (فقط رویدادهای [fromDate, toDate]) ==
/// netRevenue, directProjectCost, projectContribution, officeExpense,
/// projectOverhead, operatingResult, operatingMargin (بخش KPI Summary) +
/// تمام بخش Cash Position + periodReceiptToRevenueRatio +
/// closingReceivableToPeriodRevenueRatio (صورت‌کسر Balance ولی مخرج Period) +
/// periodArCollectionRate + receivableMovement (increase/decrease همان بازه) +
/// discount/adjustment/pricing بخش Pricing.
///
/// == CURRENT / LIFETIME STATE (مستقل از بازه انتخابی) ==
/// receivableBalance, customerCreditBalance, advanceBalance (این سه Closing
/// Balance «الان»‌اند، نه فقط پایان بازه انتخابی - هرچند از نظر عددی با
/// انتخاب toDate=امروز یکی می‌شوند) + finalizedProjectsCount/
/// settledProjectsCount/unsettledProjectsCount + allProjects/worstProjects/
/// bestProjects/outstandingProjects/lossProjects (تمام تاریخچه پروژه‌ها) +
/// customers/top5CustomersRevenueShare (Lifetime، رجوع به مستندات
/// FinancialReportingService.getTopCustomersRevenueShare).
///
/// این دو دسته هرگز نباید در یک مقایسه یا نمودار به‌اشتباه ترکیب شوند.
class ManagementDashboardData {
  final String? fromDate;
  final String? toDate;
  final String periodLabel;

  // KPI Summary
  final KpiValue netRevenue;
  final KpiValue directProjectCost;
  final KpiValue projectContribution;
  final KpiValue officeExpense;
  final KpiValue projectOverhead;
  final KpiValue operatingResult;
  final KpiValue operatingMargin;

  // Cash Position
  final double openingCash;
  final double customerReceipts;
  final double otherCashInflows;
  final double projectPayments;
  final double projectOverheadPayments;
  final double officePayments;
  final double otherCashOutflows;
  final double closingCash;
  final bool cashReconciles;

  // Receivables
  final double receivableBalance; // Closing Balance - مانده مطالبات در پایان بازه (مستقل، نه یک Ratio)
  final double customerCreditBalance;
  final double advanceBalance;
  final Map<String, double> receivableMovement; // opening/newReceivables/collections/adjustments/other/closing

  /// نسبت دریافتی نقدی بازه به درآمد شناسایی‌شده همان بازه - **نرخ وصول
  /// مطالبات همین بازه نیست**، چون دریافتی می‌تواند بابت مطالبات قدیمی‌تر
  /// باشد. عمداً periodReceiptToRevenueRatio نام‌گذاری شد (نه collectionRate)
  /// تا با نسخه Lifetime سطح پروژه/مشتری (ProjectFinancialMetrics.collectionRate)
  /// اشتباه گرفته نشود.
  final double? periodReceiptToRevenueRatio;

  /// نسبت مانده مطالبات در پایان بازه (یک Balance) به درآمد همان بازه (یک
  /// Flow) - یک شاخص مدیریتی مکمل است، نه استاندارد Collection KPI. برای
  /// بازه‌های کوتاه با درآمد کم و مطالبات انباشته قدیمی می‌تواند اعداد
  /// بسیار بزرگ (مثلاً >۱۰۰۰٪) بدهد که لزوماً وضعیت بد نیست.
  final double? closingReceivableToPeriodRevenueRatio;

  /// شاخص دقیق‌تر وصول: دریافتی واقعی این بازه تقسیم بر (مانده طلب ابتدای
  /// بازه + طلب جدید همین بازه) - یعنی «چه سهمی از مطالباتی که می‌توانستیم
  /// در این بازه وصول کنیم واقعاً وصول شد». null اگر مخرج صفر باشد.
  final double? periodArCollectionRate;

  // Settlement - هشدار مهم (مورد ۲۲ مرحله Reporting Semantics): این سه
  // شمارش، وضعیت فعلی/زنده تمام پروژه‌ها را نشان می‌دهند (Current State)،
  // نه تعداد پروژه‌هایی که «در طول بازه انتخابی» Finalize/Settle شده‌اند.
  // چون سیستم هیچ تاریخ رویداد Settlement مستقلی ثبت نمی‌کند، چنین ادعایی
  // (Settled-in-Period) قابل ساخت نیست؛ همیشه با برچسب «وضعیت فعلی» نمایش
  // داده شوند، نه به‌عنوان رویداد همان بازه انتخابی.
  final int finalizedProjectsCount;
  final int settledProjectsCount;
  final int unsettledProjectsCount;

  // Projects
  final List<ProjectFinancialReport> allProjects;
  final List<ProjectFinancialReport> worstProjects;
  final List<ProjectFinancialReport> bestProjects;
  final List<ProjectFinancialReport> outstandingProjects; // AR > 0، نزولی
  final List<ProjectFinancialReport> lossProjects;

  // Customers
  final List<CustomerFinancialReport> customers;
  final double? top5CustomersRevenueShare;

  // Pricing
  final double totalInitialEstimates;
  final double totalFinalAmounts; // فقط پروژه‌های Finalized
  final double totalAdditions;
  final double totalReductions;
  final double? averagePriceIncreaseRate;

  // Discount
  final double totalDiscount;
  final double? discountToGrossRevenueRatio;

  // Adjustments (سطح دفتر - جمع روی پروژه‌های Finalized)
  final double totalPositiveAdjustments;
  final double totalNegativeAdjustments;
  final double netAdjustments;

  // Trend Charts
  final List<TrendPoint> revenueTrend;
  final List<TrendPoint> operatingResultTrend;
  final List<TrendPoint> cashFlowTrend;
  final List<TrendPoint> contributionMarginTrend;

  // Alerts & Diagnostics
  final List<ManagementAlert> alerts;
  final FinancialReportDiagnostics diagnostics;

  ManagementDashboardData({
    this.fromDate,
    this.toDate,
    required this.periodLabel,
    required this.netRevenue,
    required this.directProjectCost,
    required this.projectContribution,
    required this.officeExpense,
    required this.projectOverhead,
    required this.operatingResult,
    required this.operatingMargin,
    required this.openingCash,
    required this.customerReceipts,
    required this.otherCashInflows,
    required this.projectPayments,
    required this.projectOverheadPayments,
    required this.officePayments,
    required this.otherCashOutflows,
    required this.closingCash,
    required this.cashReconciles,
    required this.receivableBalance,
    required this.customerCreditBalance,
    required this.advanceBalance,
    required this.receivableMovement,
    required this.periodReceiptToRevenueRatio,
    required this.closingReceivableToPeriodRevenueRatio,
    required this.periodArCollectionRate,
    required this.finalizedProjectsCount,
    required this.settledProjectsCount,
    required this.unsettledProjectsCount,
    required this.allProjects,
    required this.worstProjects,
    required this.bestProjects,
    required this.outstandingProjects,
    required this.lossProjects,
    required this.customers,
    required this.top5CustomersRevenueShare,
    required this.totalInitialEstimates,
    required this.totalFinalAmounts,
    required this.totalAdditions,
    required this.totalReductions,
    required this.averagePriceIncreaseRate,
    required this.totalDiscount,
    required this.discountToGrossRevenueRatio,
    required this.totalPositiveAdjustments,
    required this.totalNegativeAdjustments,
    required this.netAdjustments,
    required this.revenueTrend,
    required this.operatingResultTrend,
    required this.cashFlowTrend,
    required this.contributionMarginTrend,
    required this.alerts,
    required this.diagnostics,
  });
}
