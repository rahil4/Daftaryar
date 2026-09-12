import '../models/account.dart';
import '../models/journal_entry.dart';

/// نتیجه‌ی طبقه‌بندی اسناد یک پروژه برای خروجی صورتحساب (PDF): فهرست
/// دریافتی‌ها و فهرست هزینه‌ها، هرکدام مرتب‌شده بر اساس تاریخ.
class ProjectStatementLists {
  final List<Map<String, dynamic>> receipts;
  final List<Map<String, dynamic>> expenses;
  ProjectStatementLists({required this.receipts, required this.expenses});
}

/// از میان همه‌ی اسناد دفترکل یک پروژه، فهرست «دریافتی‌ها» و «هزینه‌ها» را
/// برای خروجی صورتحساب مشتری می‌سازد - فقط دو نوع رویداد واقعی و قابل‌فهم
/// (دریافت‌های نقدی و هزینه‌های مستقیم پروژه)، نه هر سطر دفترکل؛ اسناد
/// سیستمی مثل شناسایی درآمد یا انتقال پیش‌دریافت داخلی‌اند و نباید دیده شوند.
///
/// این منطق عمداً از UI (project_detail_screen) بیرون کشیده شده تا مستقل
/// و بدون نیاز به Widget قابل تست باشد - نقطه‌ی دقیقی که یک باگ واقعی
/// (دوبار شمردن هر هزینه، یک‌بار در فهرست هزینه‌ها و یک‌بار به‌صورت منفی در
/// فهرست دریافتی‌ها) در آن رخ داده بود.
ProjectStatementLists buildProjectStatementLists({
  required List<JournalEntryModel> entries,
  required int projectId,
  required Set<int?> cashAccountIds,
  required Map<int, AccountModel> accountsById,
  int? discountAccountId,
}) {
  final receipts = <Map<String, dynamic>>[];
  final expenses = <Map<String, dynamic>>[];

  for (final e in entries) {
    final entryLines = e.lines.where((l) => l.projectId == projectId).toList();
    if (entryLines.isEmpty) continue;

    // یک سند باید یا «هزینه» باشد یا «دریافت/اصلاح دریافت» - نه هر دو.
    // بدون این تفکیک سطح-به-سطح، پای بستانکار (نقد) هر سند هزینه (بدهکار
    // حساب هزینه / بستانکار نقد) هم چون حساب نقد را بستانکار می‌کند،
    // اشتباهاً به‌عنوان «اصلاح یک دریافت قبلی» با مبلغ منفی در فهرست
    // دریافت‌ها ظاهر می‌شد - یعنی هر هزینه دو بار (یک‌بار مثبت در فهرست
    // هزینه‌ها، یک‌بار منفی در فهرست دریافت‌ها) اثر می‌گذاشت.
    final isExpenseEntry = entryLines.any((l) =>
        l.debit > 0 &&
        accountsById[l.accountId]?.type == kAccountExpense &&
        l.accountId != discountAccountId);

    if (isExpenseEntry) {
      for (final l in entryLines) {
        if (l.debit > 0 &&
            accountsById[l.accountId]?.type == kAccountExpense &&
            l.accountId != discountAccountId) {
          expenses.add({
            'date': e.date,
            'description': e.description ?? accountsById[l.accountId]?.name ?? 'هزینه پروژه',
            'amount': l.debit,
          });
        }
      }
      continue;
    }

    for (final l in entryLines) {
      if (!cashAccountIds.contains(l.accountId)) continue;
      if (l.debit > 0) {
        receipts.add({
          'date': e.date,
          'description': e.description ?? 'دریافت وجه',
          'amount': l.debit,
        });
      } else if (l.credit > 0) {
        // برگشت/اصلاح یک دریافت اشتباه قبلی (رجوع به
        // DatabaseHelper.reverseProjectReceipt) - عمداً به‌جای حذف بی‌صدا
        // از صورتحساب، به‌صورت مبلغ منفی در همان فهرست دریافت‌ها نشان داده
        // می‌شود تا برای مشتری هم روشن باشد که یک دریافت قبلی اصلاح/لغو
        // شده، نه این‌که رقمی گم شده باشد.
        receipts.add({
          'date': e.date,
          'description': e.description ?? 'اصلاح دریافت',
          'amount': -l.credit,
        });
      }
    }
  }

  receipts.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
  expenses.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

  return ProjectStatementLists(receipts: receipts, expenses: expenses);
}
