// تست‌های DatabaseHelper.updateProjectDiscount و updateFinalAdjustment -
// ویرایش مستقیم مبلغ یک سند «تخفیف» یا «اصلاح مبلغ نهایی» موجود، بدون
// ساختن سند جدید (برخلاف reverseProjectDiscount/reverseFinalAdjustment که
// یک سند برگشتِ جدا ثبت می‌کنند). چون project_price_events هیچ کلید خارجی
// به سند مرتبطش ندارد، این متدها یک رویداد قیمتِ «دلتا» اضافه می‌کنند تا
// جمع کل درست بماند - این تست‌ها همان جمع کل را بررسی می‌کنند، نه ردیف خام.
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

  group('updateProjectDiscount', () {
    test('مسیر موفق: همان سند در جا اصلاح می‌شود و جمع تخفیف عدد جدید را نشان می‌دهد', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      final arBefore = await db.projectReceivableBalance(projectId);

      await db.recordProjectDiscount(projectId: projectId, amount: 1000000, date: '1404/02/02');
      final entryId = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'تخفیف نهایی پروژه')
          .id!;

      await db.updateProjectDiscount(
          entryId: entryId, amount: 1500000, date: '1404/02/03', reason: 'اصلاح‌شده');

      final entries = await db.getJournalEntries(projectId: projectId);
      final discountEntries = entries.where((e) => e.description?.startsWith('تخفیف') == true).toList();
      expect(discountEntries.length, 1, reason: 'ویرایش نباید سند دومی بسازد');
      expect(discountEntries.first.id, entryId);
      expect(discountEntries.first.date, '1404/02/03');

      expect(await db.projectReceivableBalance(projectId), arBefore - 1500000);
      final summary = await db.projectFinancialSummary(projectId);
      expect(summary['discount'], 1500000);
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
      expect(
        () => db.updateProjectDiscount(entryId: manualId, amount: 200000, date: '1404/02/01'),
        throwsA(isA<Exception>()),
      );
    });

    test('سند غیرتخفیفی رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;
      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cashAccount.id!, amount: 500000, date: '1404/02/01');
      final receiptEntry = (await db.getJournalEntries(projectId: projectId)).first;
      expect(
        () => db.updateProjectDiscount(entryId: receiptEntry.id!, amount: 100000, date: '1404/02/01'),
        throwsA(isA<Exception>()),
      );
    });

    test('مبلغ صفر یا منفی رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      await db.recordProjectDiscount(projectId: projectId, amount: 1000000, date: '1404/02/02');
      final entryId = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'تخفیف نهایی پروژه')
          .id!;
      expect(
        () => db.updateProjectDiscount(entryId: entryId, amount: 0, date: '1404/02/02'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('updateFinalAdjustment', () {
    test('مسیر موفق: مبلغ افزایشی جدید در همان سند اعمال می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      final arBefore = await db.projectReceivableBalance(projectId);

      await db.recordFinalAdjustment(projectId: projectId, amount: 2000000, date: '1404/02/02');
      final entryId = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'اصلاح مبلغ نهایی پروژه')
          .id!;

      await db.updateFinalAdjustment(entryId: entryId, amount: 3000000, date: '1404/02/03');

      final entries = await db.getJournalEntries(projectId: projectId);
      final adjustmentEntries =
          entries.where((e) => e.description?.startsWith('اصلاح مبلغ نهایی') == true).toList();
      expect(adjustmentEntries.length, 1);
      expect(adjustmentEntries.first.id, entryId);
      expect(await db.projectReceivableBalance(projectId), arBefore + 3000000);
    });

    test('مسیر موفق: تغییر جهت از افزایشی به کاهشی روی همان سند', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      final arBefore = await db.projectReceivableBalance(projectId);

      await db.recordFinalAdjustment(projectId: projectId, amount: 2000000, date: '1404/02/02');
      final entryId = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'اصلاح مبلغ نهایی پروژه')
          .id!;

      await db.updateFinalAdjustment(entryId: entryId, amount: -1000000, date: '1404/02/03');

      expect(await db.projectReceivableBalance(projectId), arBefore - 1000000);
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
      expect(
        () => db.updateFinalAdjustment(entryId: manualId, amount: 500000, date: '1404/02/01'),
        throwsA(isA<Exception>()),
      );
    });

    test('سند نهایی‌سازی واقعی رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      final revenueEntry = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description!.contains('شناسایی درآمد'));
      expect(
        () => db.updateFinalAdjustment(entryId: revenueEntry.id!, amount: 500000, date: '1404/02/01'),
        throwsA(isA<Exception>()),
      );
    });

    test('مقدار صفر رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      await db.recordFinalAdjustment(projectId: projectId, amount: 2000000, date: '1404/02/02');
      final entryId = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'اصلاح مبلغ نهایی پروژه')
          .id!;
      expect(
        () => db.updateFinalAdjustment(entryId: entryId, amount: 0, date: '1404/02/02'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
