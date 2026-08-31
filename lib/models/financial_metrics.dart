/// مدل‌های خروجی لایه Financial Metrics - هیچ‌کدام جدول دیتابیس نیستند،
/// صرفاً DTOهای محاسباتی‌اند که هر بار از روی Ledger موجود ساخته می‌شوند.
/// قرارداد null-vs-zero: 0 یعنی مقدار واقعاً صفر است؛ null یعنی «قابل محاسبه
/// نیست» (مثلاً تقسیم بر صفر، یا پروژه هنوز Finalize نشده).
library financial_metrics;

class ProjectFinancialMetrics {
  final int projectId;

  final double initialEstimate;
  final double priceAdditions;
  final double priceReductions;
  final double netPriceChanges;

  final double? finalAmount; // مبلغ اصلی Finalization - هرگز overwrite نمی‌شود
  final double finalAdjustments; // مجموع علامت‌دار FINAL_ADJUSTMENTها
  final double? effectiveFinalAmount; // finalAmount + finalAdjustments

  final double? grossRevenue; // = effectiveFinalAmount برای پروژه Finalized
  final double discountAmount;
  final double? netRevenue; // = grossRevenue - discountAmount

  final double totalReceived; // دریافتی واقعی نقدی (نه Revenue)
  final double advanceBalance;
  final double receivableBalance;
  final double? customerCredit; // null یعنی غیرقابل‌اتکا (جزئیات در سرویس)

  final double directProjectCost;

  final double? projectContribution; // netRevenue - directProjectCost
  final double? contributionMargin; // درصد، null اگر netRevenue==0

  /// نسبت Lifetime دریافتی کل عمر پروژه به Revenue کل عمر پروژه - نه یک
  /// بازه؛ مقایسه آن با نسخه Period-based سطح Dashboard/Operational
  /// Performance (که نام و معنای متفاوتی دارند) اشتباه است.
  final double? collectionRate; // درصد، null اگر netRevenue==0
  /// نسبت Closing AR (کل عمر) به Net Revenue (کل عمر) - Lifetime.
  final double? outstandingRatio; // درصد، null اگر netRevenue==0

  final double? priceIncreaseAmount; // finalAmount - initialEstimate
  final double? priceIncreaseRate; // درصد، null اگر initialEstimate==0

  final bool isFinalized;
  final bool isSettled;

  final String status;
  final String? finalizedDate;

  ProjectFinancialMetrics({
    required this.projectId,
    required this.initialEstimate,
    required this.priceAdditions,
    required this.priceReductions,
    required this.netPriceChanges,
    required this.finalAmount,
    required this.finalAdjustments,
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
    required this.collectionRate,
    required this.outstandingRatio,
    required this.priceIncreaseAmount,
    required this.priceIncreaseRate,
    required this.isFinalized,
    required this.isSettled,
    required this.status,
    this.finalizedDate,
  });
}

class CustomerFinancialMetrics {
  final int counterpartyId;
  final int projectCount; // تعداد پروژه‌های Finalized (طبق قرارداد این مرحله)

  final double grossRevenue;
  final double discountAmount;
  final double netRevenue;

  final double totalReceived;
  final double receivableBalance;
  final double customerCredit;

  /// هزینه مستقیم پروژه‌های Finalized این مشتری - عمداً هم‌جمعیت با
  /// Revenue/Discount (نه همه پروژه‌ها)، چون این مقدار مبنای محاسبه
  /// projectContribution/contributionMargin است و صورت/مخرج باید از یک
  /// جمعیت بیایند.
  final double directProjectCost;

  /// هزینه مستقیم تمام پروژه‌های این مشتری، شامل پروژه‌های در جریان (WIP)
  /// که هنوز Finalize نشده‌اند. این عدد در محاسبه Contribution/Margin
  /// استفاده نمی‌شود (چون Revenue متناظرش هنوز قطعی نیست) - فقط برای
  /// دیدن کل هزینه واقعی صرف‌شده روی این مشتری در دسترس است.
  final double directProjectCostAllProjects;

  final double? projectContribution;
  final double? contributionMargin;

  /// نسبت Lifetime (کل عمر داده‌ها)، نه محدود به یک بازه؛ رجوع کنید به
  /// PeriodFinancialReport برای معادل Period-based با نام و معنای متفاوت.
  final double? collectionRate;

  /// نسبت Closing AR (کل عمر) به Net Revenue (کل عمر) - Lifetime، نه Period.
  final double? outstandingRatio;

  final double? averageProjectValue; // netRevenue / projectCount
  final double? averageDiscountRate; // discountAmount / grossRevenue * 100

  CustomerFinancialMetrics({
    required this.counterpartyId,
    required this.projectCount,
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
  });
}

class OfficeFinancialMetrics {
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

  OfficeFinancialMetrics({
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
  });
}

class CashFlowMetrics {
  final String? fromDate;
  final String? toDate;

  final double openingCash;
  final double customerReceipts;
  final double otherCashInflows;
  final double projectPayments;
  final double projectOverheadPayments;
  final double officePayments;
  final double otherCashOutflows;
  final double closingCash;

  CashFlowMetrics({
    this.fromDate,
    this.toDate,
    required this.openingCash,
    required this.customerReceipts,
    required this.otherCashInflows,
    required this.projectPayments,
    required this.projectOverheadPayments,
    required this.officePayments,
    required this.otherCashOutflows,
    required this.closingCash,
  });

  double get totalInflows => customerReceipts + otherCashInflows;
  double get totalOutflows => projectPayments + projectOverheadPayments + officePayments + otherCashOutflows;
  double get netChange => totalInflows - totalOutflows;
}

/// نتیجه بررسی داخلی تطبیق (Reconciliation) - برای تشخیص ناسازگاری احتمالی
/// بین مقدار محاسبه‌شده از جدول Project/PriceEvent و مانده واقعی Ledger.
class ProjectReconciliation {
  final int projectId;
  final double calculatedGrossRevenue; // از Project.finalAmount + FINAL_ADJUSTMENTها
  final double ledgerRevenueBalance; // مانده واقعی حساب درآمد پروژه برای این پروژه
  final bool revenueMatches;
  final String status; // 'OK' یا 'MISMATCH' یا 'NOT_APPLICABLE'
  final String? note;

  // مورد ۲۷ مرحله Reporting Semantics: «از تشخیص به گزارش دقیق» - این
  // فیلدها زمینه کامل محاسبه calculatedGrossRevenue را فراهم می‌کنند تا در
  // صورت MISMATCH، کاربر بدون کوئری دستی دیتابیس بفهمد عدد از کجا آمده.
  final double? finalAmount; // مبلغ نهایی اصلی (خام، هرگز overwrite نشده)
  final double? finalAdjustments; // مجموع علامت‌دار FINAL_ADJUSTMENTها
  final double? discountAmount; // مجموع تخفیف (فقط جهت اطلاع؛ در calculatedGrossRevenue دخالت ندارد چون آن Gross است نه Net)

  /// calculatedGrossRevenue - ledgerRevenueBalance؛ فقط جهت خوانایی به‌عنوان
  /// getter محاسبه می‌شود، مقدار مستقلی ذخیره نمی‌کند.
  double get difference => calculatedGrossRevenue - ledgerRevenueBalance;

  ProjectReconciliation({
    required this.projectId,
    required this.calculatedGrossRevenue,
    required this.ledgerRevenueBalance,
    required this.revenueMatches,
    required this.status,
    this.note,
    this.finalAmount,
    this.finalAdjustments,
    this.discountAmount,
  });
}
