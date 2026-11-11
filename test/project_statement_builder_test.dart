// تست‌های buildProjectStatementLists - منطق طبقه‌بندی اسناد یک پروژه به
// فهرست «دریافتی‌ها» و «هزینه‌ها» برای خروجی PDF صورتحساب. این تابع عمداً
// از UI (project_detail_screen._exportStatement) بیرون کشیده شد تا این
// تست‌ها بدون نیاز به Widget/دیتابیس واقعی اجرا شوند و مستقیماً از رگرسیون
// یک باگ واقعی جلوگیری کنند: پای بستانکار (نقد) هر سند هزینه معمولی
// (بدهکار هزینه/بستانکار نقد) اشتباهاً هم به‌عنوان هزینه و هم به‌صورت منفی
// در فهرست دریافتی‌ها ظاهر می‌شد (دوبار شمردن هر هزینه).
import 'package:flutter_test/flutter_test.dart';

import 'package:daftaryar/models/account.dart';
import 'package:daftaryar/models/journal_entry.dart';
import 'package:daftaryar/services/project_statement_builder.dart';

void main() {
  const projectId = 1;
  const cashAccountId = 100;
  const receivableAccountId = 200;
  const expenseAccountId = 300;
  const discountAccountId = 400;

  final accountsById = <int, AccountModel>{
    cashAccountId: AccountModel(
        id: cashAccountId, name: 'صندوق', type: kAccountAsset, createdAt: '1404/01/01'),
    receivableAccountId: AccountModel(
        id: receivableAccountId, name: 'دریافتنی', type: kAccountAsset, createdAt: '1404/01/01'),
    expenseAccountId: AccountModel(
        id: expenseAccountId, name: 'ناهار کارگر', type: kAccountExpense, createdAt: '1404/01/01'),
    discountAccountId: AccountModel(
        id: discountAccountId, name: 'تخفیف خدمات', type: kAccountExpense, createdAt: '1404/01/01'),
  };
  final cashAccountIds = <int?>{cashAccountId};

  ProjectStatementLists build(List<JournalEntryModel> entries) => buildProjectStatementLists(
        entries: entries,
        projectId: projectId,
        cashAccountIds: cashAccountIds,
        accountsById: accountsById,
        discountAccountId: discountAccountId,
      );

  test('سند دریافت وجه (بدهکار نقد) در فهرست دریافتی‌ها با مبلغ مثبت می‌آید', () {
    final result = build([
      JournalEntryModel(
        date: '1404/02/01',
        description: 'دریافت طلب پروژه',
        createdAt: '1404/02/01',
        lines: [
          JournalLineModel(accountId: cashAccountId, debit: 5000000, projectId: projectId),
          JournalLineModel(accountId: receivableAccountId, credit: 5000000, projectId: projectId),
        ],
      ),
    ]);
    expect(result.receipts, hasLength(1));
    expect(result.receipts.single['amount'], 5000000);
    expect(result.expenses, isEmpty);
  });

  test(
      'سند هزینه معمولی (بدهکار هزینه/بستانکار نقد) فقط یک‌بار در فهرست هزینه‌ها می‌آید'
      ' - رگرسیون باگ دوبار-شمارش', () {
    final result = build([
      JournalEntryModel(
        date: '1404/02/05',
        description: 'ناهار کارگر',
        createdAt: '1404/02/05',
        lines: [
          JournalLineModel(accountId: expenseAccountId, debit: 220000, projectId: projectId),
          JournalLineModel(accountId: cashAccountId, credit: 220000, projectId: projectId),
        ],
      ),
    ]);
    expect(result.expenses, hasLength(1));
    expect(result.expenses.single['amount'], 220000);
    expect(result.receipts, isEmpty,
        reason: 'پای بستانکار نقد این سند هزینه نباید هیچ ردی (حتی منفی) در فهرست دریافتی‌ها بگذارد');
  });

  test('برگشت/اصلاح یک دریافت قبلی (بستانکار نقد بدون بدهکار هزینه) با مبلغ منفی در دریافتی‌ها می‌آید',
      () {
    final result = build([
      JournalEntryModel(
        date: '1404/02/10',
        description: 'اصلاح دریافت (سند اصلی #1)',
        createdAt: '1404/02/10',
        lines: [
          JournalLineModel(accountId: receivableAccountId, debit: 3000000, projectId: projectId),
          JournalLineModel(accountId: cashAccountId, credit: 3000000, projectId: projectId),
        ],
      ),
    ]);
    expect(result.receipts, hasLength(1));
    expect(result.receipts.single['amount'], -3000000);
    expect(result.expenses, isEmpty);
  });

  test('چند سند مختلف با هم درست جمع‌بندی و بر اساس تاریخ مرتب می‌شوند', () {
    final result = build([
      JournalEntryModel(
        date: '1404/02/05',
        description: 'ناهار کارگر',
        createdAt: '1404/02/05',
        lines: [
          JournalLineModel(accountId: expenseAccountId, debit: 220000, projectId: projectId),
          JournalLineModel(accountId: cashAccountId, credit: 220000, projectId: projectId),
        ],
      ),
      JournalEntryModel(
        date: '1404/02/01',
        description: 'دریافت طلب پروژه',
        createdAt: '1404/02/01',
        lines: [
          JournalLineModel(accountId: cashAccountId, debit: 5000000, projectId: projectId),
          JournalLineModel(accountId: receivableAccountId, credit: 5000000, projectId: projectId),
        ],
      ),
    ]);
    expect(result.receipts.single['date'], '1404/02/01');
    expect(result.expenses.single['date'], '1404/02/05');
    final totalReceipts = result.receipts.fold<num>(0, (s, r) => s + (r['amount'] as num));
    final totalExpenses = result.expenses.fold<num>(0, (s, r) => s + (r['amount'] as num));
    expect(totalReceipts, 5000000);
    expect(totalExpenses, 220000);
  });

  test('خط تخفیف (حساب تخفیف، از نوع هزینه) به‌عنوان هزینه شمرده نمی‌شود', () {
    final result = build([
      JournalEntryModel(
        date: '1404/02/12',
        description: 'تخفیف نهایی پروژه',
        createdAt: '1404/02/12',
        lines: [
          JournalLineModel(accountId: discountAccountId, debit: 1000000, projectId: projectId),
          JournalLineModel(accountId: receivableAccountId, credit: 1000000, projectId: projectId),
        ],
      ),
    ]);
    expect(result.expenses, isEmpty);
    expect(result.receipts, isEmpty,
        reason: 'سند تخفیف نه هزینه است نه دریافت/برگشت نقدی - نباید در هیچ‌کدام دیده شود');
  });

  test('سطرهای متعلق به پروژه دیگر نادیده گرفته می‌شوند', () {
    const otherProjectId = 2;
    final result = build([
      JournalEntryModel(
        date: '1404/02/01',
        description: 'دریافت پروژه دیگر',
        createdAt: '1404/02/01',
        lines: [
          JournalLineModel(accountId: cashAccountId, debit: 9000000, projectId: otherProjectId),
          JournalLineModel(accountId: receivableAccountId, credit: 9000000, projectId: otherProjectId),
        ],
      ),
    ]);
    expect(result.receipts, isEmpty);
    expect(result.expenses, isEmpty);
  });
}
