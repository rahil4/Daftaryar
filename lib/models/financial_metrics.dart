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

  final double? collectionRate; // درصد، null اگر netRevenue==0
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

  final double directProjectCost;
  final double? projectContribution;
  final double? contributionMargin;

  final double? collectionRate;
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

  ProjectReconciliation({
    required this.projectId,
    required this.calculatedGrossRevenue,
    required this.ledgerRevenueBalance,
    required this.revenueMatches,
    required this.status,
    this.note,
  });
}
