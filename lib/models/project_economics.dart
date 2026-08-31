import 'financial_reports.dart';

/// تحلیل اقتصادی یک پروژه - DTO مستقل برای پاسخ به «چرا این پروژه سودده/
/// زیان‌ده شد؟». همه مقادیر پایه از ProjectFinancialReport موجود بازاستفاده
/// می‌شوند (نه محاسبه مجدد)؛ فقط چند شاخص تحلیلی جدید روی همان مقادیر
/// اضافه شده است.
class ProjectEconomicAnalysis {
  final int projectId;
  final String projectName;
  final int counterpartyId;
  final String counterpartyName;

  final double initialEstimate;
  final double priceAdditions;
  final double priceReductions;
  final double netPriceChanges;

  final double? finalAmount;
  final double finalAdjustments;
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

  final double? collectionRate;
  final double? outstandingRatio;

  final bool isFinalized;
  final bool isSettled;

  // ---------- شاخص‌های تحلیلی جدید این مرحله ----------

  /// = finalAmount - initialEstimate (عمداً effectiveFinalAmount استفاده
  /// نمی‌شود، چون FINAL_ADJUSTMENT باید از تغییر قیمت قرارداد اصلی جدا بماند)
  final double? priceVarianceAmount;
  final double? priceVarianceRate;

  /// discountAmount / grossRevenue * 100
  final double? discountRate;

  /// directProjectCost / netRevenue * 100
  final double? directCostRatio;

  final ProjectProfitabilityStatus profitabilityStatus;

  /// netRevenue / directProjectCost - «بازده هزینه مستقیم»؛ هرگز Infinity
  /// تولید نمی‌کند (اگر مخرج صفر باشد null برمی‌گردد)
  final double? revenuePerCostUnit;

  /// netRevenue - totalReceived؛ می‌تواند منفی باشد (مثلاً به دلیل
  /// Overpayment/Customer Credit) - هرگز به صفر Clamp نمی‌شود
  final double? collectionGap;

  /// Alias تحلیلی برای receivableBalance - مقدار جدیدی محاسبه نمی‌شود
  double get remainingReceivable => receivableBalance;

  ProjectEconomicAnalysis({
    required this.projectId,
    required this.projectName,
    required this.counterpartyId,
    required this.counterpartyName,
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
    required this.isFinalized,
    required this.isSettled,
    required this.priceVarianceAmount,
    required this.priceVarianceRate,
    required this.discountRate,
    required this.directCostRatio,
    required this.profitabilityStatus,
    required this.revenuePerCostUnit,
    required this.collectionGap,
  });
}

/// آستانه‌های تشخیص «عوامل قابل توجه» - یک Configuration ثابت در کد (مانند
/// ProfitabilityThresholds)، نه ادعای علّی. این فقط برچسب توصیفی می‌سازد؛
/// هیچ رابطه علت‌ومعلولی قطعی اعلام نمی‌شود.
class ProfitabilityFactorThresholds {
  static const double highDirectCostRatio = 60; // درصد
  static const double highDiscountRate = 10; // درصد
  static const double significantPriceVarianceRate = 30; // درصد، مثبت یا منفی
  static const double significantOutstandingRatio = 20; // درصد
}

/// عوامل قابل‌مشاهده مرتبط با سودآوری یک پروژه - صرفاً گزارش شاخص‌های
/// عددی، بدون ادعای قطعی علّی («سود کم است چون...» نمی‌گوید).
class ProjectProfitabilityFactors {
  final int projectId;
  final double? directCostRatio;
  final double? discountRate;
  final double? priceVarianceRate;
  final double outstandingReceivable; // مبلغ
  final double? outstandingRatio; // نسبت

  /// برچسب‌های توصیفی خنثی - نه ادعای علّی. مثال: «نسبت هزینه مستقیم بالا»
  final List<String> notableFactors;

  ProjectProfitabilityFactors({
    required this.projectId,
    required this.directCostRatio,
    required this.discountRate,
    required this.priceVarianceRate,
    required this.outstandingReceivable,
    required this.outstandingRatio,
    required this.notableFactors,
  });
}

/// میانگین‌های مرجع (Benchmark) - فقط از پروژه‌های Finalized ساخته می‌شود؛
/// هر averageی که نمونه معتبر نداشته باشد null است، نه صفر.
class ProjectBenchmark {
  final int finalizedProjectCount;
  final double? averageNetRevenue;
  final double? averageDirectCost;
  final double? averageContribution;
  final double? averageContributionMargin;
  final double? averageDiscountRate;
  final double? averagePriceVarianceRate;
  final double? averageCollectionRate;

  ProjectBenchmark({
    required this.finalizedProjectCount,
    required this.averageNetRevenue,
    required this.averageDirectCost,
    required this.averageContribution,
    required this.averageContributionMargin,
    required this.averageDiscountRate,
    required this.averagePriceVarianceRate,
    required this.averageCollectionRate,
  });
}

/// تحلیل اقتصادی یک مشتری - مستقل از CustomerFinancialReport موجود (که
/// دست‌نخورده می‌ماند)، ولی مقادیر پایه‌اش را از همان بازاستفاده می‌کند.
class CustomerEconomicAnalysis {
  final int counterpartyId;
  final String counterpartyName;

  final int projectCount;
  final int finalizedProjectCount;

  /// فقط از پروژه‌های Finalized (طبق تعریف رسمی این مرحله)
  final double totalNetRevenue;
  /// هم‌جمعیت با totalNetRevenue (فقط Finalized) - رجوع به
  /// CustomerFinancialMetrics.directProjectCost برای توضیح کامل.
  final double totalDirectCost;
  final double? totalContribution;
  final double? contributionMargin;

  final double totalDiscount;
  final double? discountRate;

  /// این دو مقدار مستقیماً از Ledger سطح-طرف‌حساب خوانده می‌شوند (نه با جمع
  /// زدن مقادیر سطح-پروژه بازسازی می‌شوند)، چون رکوردهای بدون projectId هم
  /// باید لحاظ شوند.
  final double totalReceived;
  final double receivableBalance;
  final double? collectionRate;

  final double? averageProjectValue;
  final double? averageContributionPerProject;

  final int? mostProfitableProjectId;
  final int? leastProfitableProjectId;

  CustomerEconomicAnalysis({
    required this.counterpartyId,
    required this.counterpartyName,
    required this.projectCount,
    required this.finalizedProjectCount,
    required this.totalNetRevenue,
    required this.totalDirectCost,
    required this.totalContribution,
    required this.contributionMargin,
    required this.totalDiscount,
    required this.discountRate,
    required this.totalReceived,
    required this.receivableBalance,
    required this.collectionRate,
    required this.averageProjectValue,
    required this.averageContributionPerProject,
    required this.mostProfitableProjectId,
    required this.leastProfitableProjectId,
  });
}
