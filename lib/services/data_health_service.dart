import '../db/database_helper.dart';
import '../models/account.dart';

/// شدت یک مشکل سلامت داده
enum HealthSeverity {
  /// خرابی ساختاری - محاسبات مالی غیرقابل‌اتکا می‌شوند
  critical,

  /// ناهنجاری که باید بررسی شود ولی محاسبات را از کار نمی‌اندازد
  warning,
}

class HealthIssue {
  final HealthSeverity severity;
  final String title;
  final String detail;
  const HealthIssue({required this.severity, required this.title, required this.detail});
}

class HealthCheckResult {
  final List<HealthIssue> issues;
  const HealthCheckResult(this.issues);

  bool get isHealthy => issues.isEmpty;
  bool get hasCritical => issues.any((i) => i.severity == HealthSeverity.critical);
  int get criticalCount => issues.where((i) => i.severity == HealthSeverity.critical).length;
}

/// بررسی سلامت ساختاری دیتابیس.
///
/// این سرویس عمداً از FinancialReportDiagnostics موجود جداست: آن یکی
/// ناهنجاری‌های *مالی* را می‌سنجد (مانده منفی، عدم تطابق درآمد با دفتر)،
/// این یکی یکپارچگی *ساختاری* را - یعنی پیش‌فرض‌هایی که همه محاسبات مالی
/// روی آن‌ها بنا شده‌اند.
///
/// انگیزه: یک باگ واقعی هفته‌ها پنهان ماند چون ستون systemKey حساب‌های
/// کنترلی در یک Migration پر نشده بود؛ نتیجه‌اش صفر شدن خاموش همه
/// مانده‌های مطالبات و پیش‌دریافت بود. هیچ‌کدام از تشخیص‌های مالی موجود
/// این را نمی‌گرفتند، چون از دید آن‌ها «همه مانده‌ها صفرند» یک وضعیت
/// کاملاً معتبر است. بررسی‌های زیر دقیقاً همان دسته خرابی را می‌گیرند.
class DataHealthService {
  final DatabaseHelper _db;
  DataHealthService([DatabaseHelper? db]) : _db = db ?? DatabaseHelper.instance;

  /// حساب‌های کنترلی که نبودشان همه محاسبات وابسته را از کار می‌اندازد
  static const Map<String, String> _requiredControlAccounts = {
    kSystemKeyReceivable: 'حساب‌های دریافتنی',
    kSystemKeyPayable: 'حساب‌های پرداختنی',
    kSystemKeyCustomerAdvance: 'پیش‌دریافت مشتری',
    kSystemKeyCustomerCredit: 'بستانکاری مشتری',
    kSystemKeyProjectRevenue: 'درآمد پروژه‌ها',
    kSystemKeyProjectOverhead: 'سربار عمومی پروژه‌ها',
    kSystemKeyServiceDiscount: 'تخفیف خدمات',
  };

  Future<HealthCheckResult> run() async {
    final issues = <HealthIssue>[];
    issues.addAll(await _checkControlAccounts());
    issues.addAll(await _checkCashAccounts());
    issues.addAll(await _checkLedgerBalance());
    issues.addAll(await _checkOrphanReferences());
    return HealthCheckResult(issues);
  }

  /// آیا همه حساب‌های کنترلی با systemKey معتبر وجود دارند؟
  Future<List<HealthIssue>> _checkControlAccounts() async {
    final issues = <HealthIssue>[];
    final accounts = await _db.getAccounts();
    final presentKeys = accounts.map((a) => a.systemKey).whereType<String>().toSet();

    for (final entry in _requiredControlAccounts.entries) {
      if (!presentKeys.contains(entry.key)) {
        issues.add(HealthIssue(
          severity: HealthSeverity.critical,
          title: 'حساب کنترلی «${entry.value}» یافت نشد',
          detail: 'محاسبات وابسته به این حساب نادرست خواهند بود. '
              'از آخرین پشتیبان سالم بازیابی کنید.',
        ));
      }
    }
    return issues;
  }

  /// آیا حداقل یک حساب نقدی/بانکی وجود دارد؟
  Future<List<HealthIssue>> _checkCashAccounts() async {
    final cash = await _db.getCashAccounts();
    if (cash.isEmpty) {
      return [
        const HealthIssue(
          severity: HealthSeverity.critical,
          title: 'هیچ حساب صندوق یا بانکی وجود ندارد',
          detail: 'ثبت دریافت و پرداخت و همه محاسبات نقدی ممکن نیست.',
        )
      ];
    }
    return [];
  }

  /// اصل بنیادی حسابداری دوطرفه: مجموع بدهکار کل دفتر باید دقیقاً با
  /// مجموع بستانکار برابر باشد. نابرابری یعنی دیتابیس آسیب دیده.
  Future<List<HealthIssue>> _checkLedgerBalance() async {
    final totals = await _db.ledgerTotals();
    final debit = totals['debit'] ?? 0;
    final credit = totals['credit'] ?? 0;
    // تلورانس یک ریال برای خطای ممیز شناور
    if ((debit - credit).abs() > 1) {
      return [
        HealthIssue(
          severity: HealthSeverity.critical,
          title: 'دفترکل متوازن نیست',
          detail: 'مجموع بدهکار و بستانکار برابر نیستند '
              '(اختلاف: ${(debit - credit).abs().round()}). '
              'این یعنی داده آسیب دیده است.',
        )
      ];
    }
    return [];
  }

  /// سطرهایی که به حساب یا پروژه حذف‌شده ارجاع می‌دهند
  Future<List<HealthIssue>> _checkOrphanReferences() async {
    final issues = <HealthIssue>[];
    final orphanAccounts = await _db.countOrphanJournalAccountRefs();
    if (orphanAccounts > 0) {
      issues.add(HealthIssue(
        severity: HealthSeverity.critical,
        title: 'ارجاع به حساب حذف‌شده',
        detail: '$orphanAccounts سطر سند به حسابی ارجاع می‌دهد که دیگر وجود ندارد.',
      ));
    }
    final unbalanced = await _db.countUnbalancedEntries();
    if (unbalanced > 0) {
      issues.add(HealthIssue(
        severity: HealthSeverity.critical,
        title: 'سند نامتوازن',
        detail: '$unbalanced سند حسابداری وجود دارد که بدهکار و بستانکارش برابر نیست.',
      ));
    }
    return issues;
  }
}
