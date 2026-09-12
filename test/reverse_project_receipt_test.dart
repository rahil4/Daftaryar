// تست‌های DatabaseHelper.reverseProjectReceipt - اصلاح یک سند «دریافت وجه
// پروژه» اشتباه (مثلاً چیزی که باید هزینه ثبت می‌شد) بدون حذف فیزیکی سند
// سیستمی اصلی؛ به‌جایش یک سند برگشتِ دقیقاً معکوس ثبت می‌شود.
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

  group('reverseProjectReceipt — مسیر موفق', () {
    test('پیش از نهایی‌سازی: برگشت دریافت، مانده پیش‌دریافت و نقد را دقیقاً صفر می‌کند', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 5000000,
        date: '1404/02/01',
      );
      expect(await db.projectAdvanceBalance(projectId), 5000000);

      final entries = await db.getJournalEntries(projectId: projectId);
      expect(entries.length, 1);
      final originalId = entries.first.id!;

      final reversalId = await db.reverseProjectReceipt(originalId);
      expect(reversalId, isNot(originalId));
      expect(await db.projectAdvanceBalance(projectId), 0,
          reason: 'برگشت باید دقیقاً اثر دریافت را روی پیش‌دریافت خنثی کند');

      final cashFlow = await db.projectFinancials(projectId);
      expect(cashFlow['received']! - cashFlow['spent']!, 0,
          reason: 'خالص جریان نقدی پروژه باید بعد از برگشت صفر شود');

      // سند اصلی همچنان در تاریخچه باقی مانده - حذف نشده
      final afterEntries = await db.getJournalEntries(projectId: projectId);
      expect(afterEntries.length, 2);
      expect(afterEntries.any((e) => e.id == originalId), true);
    });

    test('پس از نهایی‌سازی: برگشت دریافت، مانده طلب را به حالت قبل برمی‌گرداند', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      final cashAccount = (await db.getCashAccounts()).first;

      final arBeforeReceipt = await db.projectReceivableBalance(projectId);
      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 4000000,
        date: '1404/02/05',
      );
      expect(await db.projectReceivableBalance(projectId), arBeforeReceipt - 4000000);

      final entries = await db.getJournalEntries(projectId: projectId);
      final receiptEntry = entries.firstWhere((e) => e.description == 'دریافت طلب پروژه');

      await db.reverseProjectReceipt(receiptEntry.id!);
      expect(await db.projectReceivableBalance(projectId), arBeforeReceipt,
          reason: 'برگشت باید مانده طلب را دقیقاً به حالت پیش از این دریافت برگرداند');
    });
  });

  group('reverseProjectReceipt — محافظت‌ها', () {
    test('سند دستی (manual) رد می‌شود - چون خودش مستقیماً قابل حذف است', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;
      final expenseAccounts = await db.getAccounts(type: kAccountExpense);
      final expenseAccount = expenseAccounts.first;

      final manualId = await db.createManualJournal(JournalEntryModel(
        date: '1404/02/01',
        description: 'هزینه دستی',
        createdAt: '1404/02/01',
        lines: [
          JournalLineModel(accountId: expenseAccount.id!, debit: 100000, projectId: projectId),
          JournalLineModel(accountId: cashAccount.id!, credit: 100000, projectId: projectId),
        ],
      ));

      expect(() => db.reverseProjectReceipt(manualId), throwsA(isA<Exception>()));
    });

    test('سند سیستمی غیردریافتی (مثل تخفیف) رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      await db.recordProjectDiscount(projectId: projectId, amount: 1000000, date: '1404/02/02');

      final entries = await db.getJournalEntries(projectId: projectId);
      final discountEntry = entries.firstWhere((e) => e.description == 'تخفیف نهایی پروژه');

      expect(() => db.reverseProjectReceipt(discountEntry.id!), throwsA(isA<Exception>()));
    });

    test('اصلاح دوباره همان سند رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 2000000,
        date: '1404/02/01',
      );
      final entries = await db.getJournalEntries(projectId: projectId);
      final originalId = entries.first.id!;

      await db.reverseProjectReceipt(originalId);
      expect(() => db.reverseProjectReceipt(originalId), throwsA(isA<Exception>()));
    });

    test('اگر پیش‌دریافت از زمان دریافت مصرف شده باشد (نهایی‌سازی)، اصلاح خودکار رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 3000000,
        date: '1404/02/01',
      );
      final entries = await db.getJournalEntries(projectId: projectId);
      final originalId = entries.first.id!;

      // نهایی‌سازی کل مانده پیش‌دریافت را به دریافتنی منتقل می‌کند - پیش‌دریافت صفر می‌شود
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/03/01');
      expect(await db.projectAdvanceBalance(projectId), 0);

      expect(() => db.reverseProjectReceipt(originalId), throwsA(isA<Exception>()));
    });
  });
}
