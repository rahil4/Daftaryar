/// دسته‌بندی منبع دریافتی‌های نقدی یک بازه، برای گزارش «دریافت و هزینه».
/// طرف‌مقابل هر سند دریافت وجه یکی از این‌هاست:
/// - projects: پیش‌دریافت یا تسویه طلب یک پروژه (بیشتر دریافتی‌های روزمره)
/// - directIncome: دریافتی مستقیم روی یک حساب درآمدی، بدون اتصال به پروژه
/// - other: هر منبع دیگر (مثلاً آورده مالک به سرمایه)
enum CashReceiptCategory { projects, directIncome, other }

extension CashReceiptCategoryLabel on CashReceiptCategory {
  String get label {
    switch (this) {
      case CashReceiptCategory.projects:
        return 'دریافت از مشتریان/پروژه‌ها';
      case CashReceiptCategory.directIncome:
        return 'درآمد مستقیم';
      case CashReceiptCategory.other:
        return 'سایر منابع';
    }
  }
}
