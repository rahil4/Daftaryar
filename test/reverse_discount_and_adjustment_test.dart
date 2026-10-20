// تست‌های DatabaseHelper.reverseProjectDiscount و reverseFinalAdjustment -
// اصلاح یک سند «تخفیف» یا «اصلاح مبلغ نهایی» اشتباه با ثبت یک سند برگشتِ
// دقیقاً معکوس (به‌همراه یک رویداد قیمتِ خنثی‌کننده)، بدون حذف فیزیکی سند
// سیستمی اصلی.
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

  group('reverseProjectDiscount', () {
    test('مسیر موفق: مانده طلب و جمع تخفیف را دقیقاً به حالت قبل برمی‌گرداند', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      final arBefore = await db.projectReceivableBalance(projectId);

      await db.recordProjectDiscount(projectId: projectId, amount: 1000000, date: '1404/02/02');
      expect(await db.projectReceivableBalance(projectId), arBefore - 1000000);
      final summaryAfterDiscount = await db.projectFinancialSummary(projectId);
      expect(summaryAfterDiscount['discount'], 1000000);

      final discountEntry =
          (await db.getJournalEntries(projectId: projectId)).firstWhere((e) => e.description == 'تخفیف نهایی پروژه');
      await db.reverseProjectDiscount(discountEntry.id!);

      expect(await db.projectReceivableBalance(projectId), arBefore);
      final summaryAfterReverse = await db.projectFinancialSummary(projectId);
      expect(summaryAfterReverse['discount'], 0);
    });

    test('سند دستی رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;
      final expenseAccount = (await db.getAccounts(type: kAccountExpense)).first;
      final manualId = await db.createManualJournal(JournalEntryModel(
        date: '1404/02/01',
        description: 'هزینه دستی',
        createdAt: '1404/02/01',
        lines: [
          JournalLineModel(accountId: expenseAccount.id!, debit: 100000, projectId: projectId),
          JournalLineModel(accountId: cashAccount.id!, credit: 100000, projectId: projectId),
        ],
      ));
      expect(() => db.reverseProjectDiscount(manualId), throwsA(isA<Exception>()));
    });

    test('سند غیرتخفیفی (مثل دریافت وجه) رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;
      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cashAccount.id!, amount: 500000, date: '1404/02/01');
      final receiptEntry = (await db.getJournalEntries(projectId: projectId)).first;
      expect(() => db.reverseProjectDiscount(receiptEntry.id!), throwsA(isA<Exception>()));
    });

    test('اصلاح دوباره همان سند رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      await db.recordProjectDiscount(projectId: projectId, amount: 1000000, date: '1404/02/02');
      final discountEntry =
          (await db.getJournalEntries(projectId: projectId)).firstWhere((e) => e.description == 'تخفیف نهایی پروژه');
      await db.reverseProjectDiscount(discountEntry.id!);
      expect(() => db.reverseProjectDiscount(discountEntry.id!), throwsA(isA<Exception>()));
    });
  });

  group('reverseFinalAdjustment', () {
    test('مسیر موفق (اصلاح افزایشی): مانده طلب را دقیقاً به حالت قبل برمی‌گرداند', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      final arBefore = await db.projectReceivableBalance(projectId);

      await db.recordFinalAdjustment(projectId: projectId, amount: 2000000, date: '1404/02/02');
      expect(await db.projectReceivableBalance(projectId), arBefore + 2000000);

      final adjustmentEntry = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'اصلاح مبلغ نهایی پروژه');
      await db.reverseFinalAdjustment(adjustmentEntry.id!);

      expect(await db.projectReceivableBalance(projectId), arBefore);
    });

    test('مسیر موفق (اصلاح کاهشی): مانده طلب را دقیقاً به حالت قبل برمی‌گرداند', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      final arBefore = await db.projectReceivableBalance(projectId);

      await db.recordFinalAdjustment(projectId: projectId, amount: -1500000, date: '1404/02/02');
      expect(await db.projectReceivableBalance(projectId), arBefore - 1500000);

      final adjustmentEntry = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'اصلاح مبلغ نهایی پروژه');
      await db.reverseFinalAdjustment(adjustmentEntry.id!);

      expect(await db.projectReceivableBalance(projectId), arBefore);
    });

    test('سند دستی رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;
      final expenseAccount = (await db.getAccounts(type: kAccountExpense)).first;
      final manualId = await db.createManualJournal(JournalEntryModel(
        date: '1404/02/01',
        description: 'هزینه دستی',
        createdAt: '1404/02/01',
        lines: [
          JournalLineModel(accountId: expenseAccount.id!, debit: 100000, projectId: projectId),
          JournalLineModel(accountId: cashAccount.id!, credit: 100000, projectId: projectId),
        ],
      ));
      expect(() => db.reverseFinalAdjustment(manualId), throwsA(isA<Exception>()));
    });

    test('سند دریافت وجه با توضیح دستکاری‌شده مشابه، رد می‌شود (چون سطر نقد/بانک دارد)', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;
      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 500000,
        date: '1404/02/01',
        description: 'اصلاح مبلغ نهایی: تلاش برای فریب تشخیص',
      );
      final receiptEntry = (await db.getJournalEntries(projectId: projectId)).first;
      expect(() => db.reverseFinalAdjustment(receiptEntry.id!), throwsA(isA<Exception>()));
    });

    test('سند نهایی‌سازی (شناسایی درآمد) با وجود ساختار حسابی یکسان، رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      final revenueEntry = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description!.contains('شناسایی درآمد'));
      expect(() => db.reverseFinalAdjustment(revenueEntry.id!), throwsA(isA<Exception>()));
    });

    test('اصلاح دوباره همان سند رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      await db.recordFinalAdjustment(projectId: projectId, amount: 2000000, date: '1404/02/02');
      final adjustmentEntry = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'اصلاح مبلغ نهایی پروژه');
      await db.reverseFinalAdjustment(adjustmentEntry.id!);
      expect(() => db.reverseFinalAdjustment(adjustmentEntry.id!), throwsA(isA<Exception>()));
    });
  });
}
