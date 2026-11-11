// تست‌های DatabaseHelper.convertReceiptToExpense - تبدیل یک سند «دریافت
// وجه پروژه» که در واقع هزینه بوده (اشتباه در ماهیت، نه فقط مبلغ) به یک
// سند هزینه واقعی، در همان سند (بدون ساختن سند دوم) و با source manual
// (تا از این پس مثل هر سند دستی دیگر آزادانه قابل حذف/ویرایش باشد).
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daftaryar/db/database_helper.dart';
import 'package:daftaryar/models/account.dart';
import 'package:daftaryar/models/counterparty.dart';
import 'package:daftaryar/models/journal_entry.dart';
import 'package:daftaryar/models/project.dart';

void main() {
  final db = DatabaseHelper.instance;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.wipeAll();
  });

  Future<int> createCounterparty(String name) async {
    const now = '1404/01/01';
    return db.insertCounterparty(CounterpartyModel(
      name: name,
      createdAt: now,
      updatedAt: now,
      roles: const ['مشتری'],
    ));
  }

  Future<int> createProject(int counterpartyId, {double agreedAmount = 80000000}) async {
    return db.insertProject(ProjectModel(
      title: 'پروژه تست',
      counterpartyId: counterpartyId,
      projectTypes: [kProjectTypes.first],
      status: kProjectStatuses.first,
      startDate: '1404/01/01',
      agreedAmount: agreedAmount,
      createdAt: '1404/01/01',
    ));
  }

  group('convertReceiptToExpense — مسیر موفق', () {
    test('پیش از نهایی‌سازی: پیش‌دریافت صفر می‌شود و سند به هزینه واقعی تبدیل می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;
      final expenseAccount = (await db.getPostableAccounts(type: kAccountExpense)).first;

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 4000000,
        date: '1404/02/01',
      );
      expect(await db.projectAdvanceBalance(projectId), 4000000);
      final originalEntry = (await db.getJournalEntries(projectId: projectId)).first;
      final entryId = originalEntry.id!;

      await db.convertReceiptToExpense(
        entryId: entryId,
        expenseAccountId: expenseAccount.id!,
        cashAccountId: cashAccount.id!,
        amount: 4000000,
        date: '1404/02/01',
        description: 'هزینه واقعی',
      );

      expect(await db.projectAdvanceBalance(projectId), 0,
          reason: 'دیگر هیچ دریافتی روی پیش‌دریافت این پروژه نیست');
      expect(await db.projectDirectCost(projectId), 4000000,
          reason: 'اکنون باید به‌عنوان هزینه مستقیم پروژه شناخته شود');

      final entries = await db.getJournalEntries(projectId: projectId);
      expect(entries.length, 1, reason: 'تبدیل نباید سند دومی بسازد - همان سند تبدیل شده');
      final converted = entries.first;
      expect(converted.id, entryId);
      expect(converted.isSystemGenerated, false, reason: 'باید از سیستمی به دستی تبدیل شده باشد');
      expect(converted.isDeletable, true, reason: 'از این پس باید مثل هر سند دستی دیگر قابل حذف باشد');

      // اثبات عملی: حالا واقعاً قابل حذف است (چیزی که پیش از تبدیل ممکن نبود)
      await db.deleteJournalEntry(entryId);
      expect(await db.getJournalEntries(projectId: projectId), isEmpty);
    });

    test('پس از نهایی‌سازی: مانده طلب به حالت پیش از دریافت برمی‌گردد', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      final cashAccount = (await db.getCashAccounts()).first;
      final expenseAccount = (await db.getPostableAccounts(type: kAccountExpense)).first;
      final arBefore = await db.projectReceivableBalance(projectId);

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 2000000,
        date: '1404/02/05',
      );
      final entryId = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'دریافت طلب پروژه')
          .id!;

      await db.convertReceiptToExpense(
        entryId: entryId,
        expenseAccountId: expenseAccount.id!,
        cashAccountId: cashAccount.id!,
        amount: 2000000,
        date: '1404/02/05',
      );

      expect(await db.projectReceivableBalance(projectId), arBefore,
          reason: 'برگرداندن اثر دریافت باید مانده طلب را دقیقاً به حالت قبل برساند');
    });
  });

  group('convertReceiptToExpense — محافظت‌ها', () {
    test('سند دستی رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;
      final expenseAccount = (await db.getPostableAccounts(type: kAccountExpense)).first;
      final manualId = await db.createManualJournal(JournalEntryModel(
        date: '1404/02/01',
        description: 'هزینه دستی',
        createdAt: '1404/02/01',
        lines: [
          JournalLineModel(accountId: expenseAccount.id!, debit: 100000, projectId: projectId),
          JournalLineModel(accountId: cashAccount.id!, credit: 100000, projectId: projectId),
        ],
      ));
      expect(
        () => db.convertReceiptToExpense(
          entryId: manualId,
          expenseAccountId: expenseAccount.id!,
          cashAccountId: cashAccount.id!,
          amount: 100000,
          date: '1404/02/01',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('سند غیردریافتی (مثل تخفیف) رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      await db.recordProjectDiscount(projectId: projectId, amount: 1000000, date: '1404/02/02');
      final cashAccount = (await db.getCashAccounts()).first;
      final expenseAccount = (await db.getPostableAccounts(type: kAccountExpense)).first;
      final discountEntry = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'تخفیف نهایی پروژه');
      expect(
        () => db.convertReceiptToExpense(
          entryId: discountEntry.id!,
          expenseAccountId: expenseAccount.id!,
          cashAccountId: cashAccount.id!,
          amount: 500000,
          date: '1404/02/02',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('سند چندسطریِ تقسیم‌شده بابت مازاد دریافتی رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست - Overflow');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/02');
      final cashAccount = (await db.getCashAccounts()).first;
      final expenseAccount = (await db.getPostableAccounts(type: kAccountExpense)).first;

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 50000000,
        date: '1404/02/05',
      );
      final overflowEntry = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'دریافت طلب پروژه');
      expect(overflowEntry.lines.length, 3);

      expect(
        () => db.convertReceiptToExpense(
          entryId: overflowEntry.id!,
          expenseAccountId: expenseAccount.id!,
          cashAccountId: cashAccount.id!,
          amount: 40000000,
          date: '1404/02/05',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('اگر پیش‌دریافت از زمان دریافت مصرف شده باشد (نهایی‌سازی)، تبدیل رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;
      final expenseAccount = (await db.getPostableAccounts(type: kAccountExpense)).first;

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 3000000,
        date: '1404/02/01',
      );
      final entryId = (await db.getJournalEntries(projectId: projectId)).first.id!;

      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/03/01');
      expect(await db.projectAdvanceBalance(projectId), 0);

      expect(
        () => db.convertReceiptToExpense(
          entryId: entryId,
          expenseAccountId: expenseAccount.id!,
          cashAccountId: cashAccount.id!,
          amount: 3000000,
          date: '1404/02/01',
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('مبلغ صفر یا منفی رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;
      final expenseAccount = (await db.getPostableAccounts(type: kAccountExpense)).first;
      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 1000000,
        date: '1404/02/01',
      );
      final entryId = (await db.getJournalEntries(projectId: projectId)).first.id!;
      expect(
        () => db.convertReceiptToExpense(
          entryId: entryId,
          expenseAccountId: expenseAccount.id!,
          cashAccountId: cashAccount.id!,
          amount: 0,
          date: '1404/02/01',
        ),
        throwsA(isA<Exception>()),
      );
    });
  });
}
