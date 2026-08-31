import 'financial_reports.dart';
import 'management_dashboard_data.dart';

/// خروجی کامل لایه تحلیل عملکرد عملیاتی - یک ViewModel واحد، بدون تکثیر
/// مدل‌های کوچک غیرضروری. همه مقادیر از لایه‌های Metrics/Reporting/Economics
/// موجود خوانده می‌شوند؛ هیچ مقداری در دیتابیس ذخیره نمی‌شود.
class OperationalPerformanceData {
  final String periodStart;
  final String periodEnd;
  final String periodLabel;

  // ---------- بخش ۱: Activity Overview ----------
  // توجه مهم (مستند در warnings هم): چون هیچ «تاریخ تسویه» در سیستم ثبت
  // نمی‌شود، settledProjectCount/openProjectCount وضعیت فعلی (زمان تولید
  // گزارش) را نشان می‌دهند، نه وضعیت دقیق «در پایان بازه».
  final int projectCount; // کل دیتاست (Lifetime - همه پروژه‌های ثبت‌شده)
  final int newProjectCount; // Project.createdAt در بازه
  final int finalizedProjectCount; // Project.finalizedDate در بازه
  final int settledProjectCount; // وضعیت فعلی
  final int openProjectCount; // وضعیت فعلی (Finalize‌نشده یا Settle‌نشده)
  final int cancelledProjectCount; // Project.status فعلی

  final Map<String, int> countByStatus; // بر اساس Statusهای واقعی موجود پروژه

  // ---------- بخش ۲: Financial Performance (بر مبنای JournalEntry.date) ----------
  final double finalizedRevenue;
  final double finalizedDirectCost;
  final double? finalizedContribution;
  final double? finalizedContributionMargin; // نسبت تجمعی کل بازه (نه میانگین)

  // ---------- بخش ۳: Project Volume vs Financial Volume ----------
  final double? revenuePerFinalizedProject;
  final double? contributionPerFinalizedProject;

  /// میانگین حسابی Margin پروژه‌های Finalize‌شده در بازه - عمداً از
  /// finalizedContributionMargin (که یک نسبت تجمعی است) متفاوت است؛ هر
  /// پروژه با وزن یکسان لحاظ می‌شود، نه با وزن اندازه درآمدش.
  final double? averageProjectMargin;

  // ---------- بخش ۴/۵: Growth Decomposition ----------
  final double? revenueGrowthRate;
  final double? averageRevenueGrowthRate;
  final double? contributionGrowthRate;
  final double? projectVolumeGrowthRate;

  /// واحد: Percentage Points، نه درصد رشد (مثلاً 78% -> 70% یعنی -8، نه -8%)
  final double? contributionMarginChangePoints;

  // ---------- بخش ۸: Project Outcome Distribution (فقط Finalize‌شده در بازه) ----------
  final int lossProjectCount;
  final int lowMarginProjectCount;
  final int normalMarginProjectCount;
  final int highMarginProjectCount;
  final double? lossProjectRate;

  // ---------- بخش ۹: Customer Concentration ----------
  // محدودیت مستند: این سه شاخص Lifetime هستند (نه محدود به بازه انتخابی)،
  // چون API موجود getTopCustomersRevenueShare بازه‌ای نیست و افزودن نسخه
  // بازه‌ای آن برای این مرحله ضرورت کافی نداشت (بند «از ایجاد Abstraction
  // غیرضروری خودداری کن»).
  final double? top1CustomerRevenueShare;
  final double? top3CustomerRevenueShare;
  final double? top5CustomerRevenueShare;

  // ---------- بخش ۱۰: Pricing Performance (بر مبنای ProjectPriceEvent.date) ----------
  final double totalPriceAdditions;
  final double totalPriceReductions;
  final double netPriceChange;

  // ---------- بخش ۱۱: Discount Performance (بر مبنای ProjectPriceEvent.date) ----------
  final double totalDiscount;
  final double? discountRate;
  final double? discountPerFinalizedProject;

  // ---------- بخش ۱۲: Collection Performance ----------
  final double totalReceived; // بر مبنای JournalEntry.date در بازه
  final double receivableBalance; // مانده در پایان بازه (Closing)
  final double customerCredit; // مانده در پایان بازه (Closing)

  /// نسبت دریافتی نقدی بازه به درآمد همان بازه - ممکن است شامل وصول
  /// مطالبات قدیمی‌تر باشد؛ «نرخ وصول مطالبات همین بازه» نیست (رجوع به
  /// periodArCollectionRate برای آن مفهوم دقیق‌تر).
  final double? periodReceiptToRevenueRatio;

  /// دریافتی واقعی بازه تقسیم بر (مانده طلب ابتدای بازه + طلب جدید همان
  /// بازه) - شاخص دقیق‌تر «چه سهمی از مطالبات قابل‌وصول این بازه واقعاً
  /// وصول شد». null اگر مخرج صفر باشد.
  final double? periodArCollectionRate;

  final double? collectionGap;

  // ---------- بخش ۷: Work In Progress (وضعیت فعلی، نه محدود به بازه) ----------
  final int wipProjectCount;
  final double wipInitialEstimate; // عمداً «Initial Estimate» نامیده شد، نه Revenue
  final double wipDirectCost;
  final double wipReceived;

  // ---------- مقایسه دوره‌ای (از مدل موجود FinancialPeriodComparison) ----------
  final List<FinancialPeriodComparison> comparisons;

  // ---------- روند تاریخی (فقط Observed، نه Forecast) ----------
  final List<TrendPoint> revenueTrend;
  final List<TrendPoint> contributionTrend;
  final List<TrendPoint> projectVolumeTrend; // تعداد پروژه Finalize‌شده هر ماه
  final List<TrendPoint> receivableTrend; // مانده AR در پایان هر ماه

  // ---------- هشدارها و تشخیص ----------
  final List<ManagementAlert> alerts;
  final FinancialReportDiagnostics diagnostics;

  /// یادداشت‌های صریح محدودیت داده - هرگز برای تولید عدد حدس زده نشد؛
  /// در عوض این‌جا اعلام می‌شود.
  final List<String> warnings;

  OperationalPerformanceData({
    required this.periodStart,
    required this.periodEnd,
    required this.periodLabel,
    required this.projectCount,
    required this.newProjectCount,
    required this.finalizedProjectCount,
    required this.settledProjectCount,
    required this.openProjectCount,
    required this.cancelledProjectCount,
    required this.countByStatus,
    required this.finalizedRevenue,
    required this.finalizedDirectCost,
    required this.finalizedContribution,
    required this.finalizedContributionMargin,
    required this.revenuePerFinalizedProject,
    required this.contributionPerFinalizedProject,
    required this.averageProjectMargin,
    required this.revenueGrowthRate,
    required this.averageRevenueGrowthRate,
    required this.contributionGrowthRate,
    required this.projectVolumeGrowthRate,
    required this.contributionMarginChangePoints,
    required this.lossProjectCount,
    required this.lowMarginProjectCount,
    required this.normalMarginProjectCount,
    required this.highMarginProjectCount,
    required this.lossProjectRate,
    required this.top1CustomerRevenueShare,
    required this.top3CustomerRevenueShare,
    required this.top5CustomerRevenueShare,
    required this.totalPriceAdditions,
    required this.totalPriceReductions,
    required this.netPriceChange,
    required this.totalDiscount,
    required this.discountRate,
    required this.discountPerFinalizedProject,
    required this.totalReceived,
    required this.receivableBalance,
    required this.customerCredit,
    required this.periodReceiptToRevenueRatio,
    required this.periodArCollectionRate,
    required this.collectionGap,
    required this.wipProjectCount,
    required this.wipInitialEstimate,
    required this.wipDirectCost,
    required this.wipReceived,
    required this.comparisons,
    required this.revenueTrend,
    required this.contributionTrend,
    required this.projectVolumeTrend,
    required this.receivableTrend,
    required this.alerts,
    required this.diagnostics,
    required this.warnings,
  });
}
