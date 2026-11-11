// تست‌های DatabaseHelper.updateProjectReceipt - ویرایش مستقیم مبلغ/حساب
// نقد/تاریخ یک سند «دریافت وجه پروژه» موجود، بدون ساختن سند جدید (برخلاف
// reverseProjectReceipt که یک سند برگشتِ جدا ثبت می‌کند).
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

  group('updateProjectReceipt — مسیر موفق', () {
    test('تغییر مبلغ روی سند دریافتِ پیش از نهایی‌سازی، همان سند را در جا اصلاح می‌کند', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 5000000,
        date: '1404/02/01',
      );
      final before = await db.getJournalEntries(projectId: projectId);
      expect(before.length, 1);
      final entryId = before.first.id!;

      await db.updateProjectReceipt(
        entryId: entryId,
        cashAccountId: cashAccount.id!,
        amount: 7000000,
        date: '1404/02/02',
        description: 'اصلاح‌شده',
      );

      expect(await db.projectAdvanceBalance(projectId), 7000000);
      final after = await db.getJournalEntries(projectId: projectId);
      expect(after.length, 1, reason: 'ویرایش نباید سند دومی بسازد - همان سند در جای خودش اصلاح می‌شود');
      expect(after.first.id, entryId);
      expect(after.first.date, '1404/02/02');
      expect(after.first.description, 'اصلاح‌شده');
    });

    test('تغییر حساب نقد/بانک، جریان نقدی حساب جدید را درست منعکس می‌کند', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccounts = await db.getCashAccounts();
      // اطمینان از وجود دست‌کم دو حساب نقد/بانک برای این تست (بانک پیش‌فرض seed می‌شود)
      expect(cashAccounts.length, greaterThanOrEqualTo(2));
      final oldCash = cashAccounts[0];
      final newCash = cashAccounts[1];

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: oldCash.id!,
        amount: 3000000,
        date: '1404/02/01',
      );
      final entryId = (await db.getJournalEntries(projectId: projectId)).first.id!;

      await db.updateProjectReceipt(
        entryId: entryId,
        cashAccountId: newCash.id!,
        amount: 3000000,
        date: '1404/02/01',
      );

      final oldCashFlow = await db.projectFinancials(projectId);
      // projectFinancials فقط روی همان مجموعه حساب‌های نقدی کار می‌کند، پس
      // به‌جای آن مستقیم از خط سند مطمئن می‌شویم حساب واقعاً عوض شده.
      final entries = await db.getJournalEntries(projectId: projectId);
      final line = entries.first.lines.firstWhere((l) => l.debit > 0);
      expect(line.accountId, newCash.id);
      expect(oldCashFlow['received'], 3000000);
    });

    test('پس از نهایی‌سازی: ویرایش مبلغ دریافتنی، مانده طلب را درست به‌روزرسانی می‌کند', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      final cashAccount = (await db.getCashAccounts()).first;

      final arBeforeReceipt = await db.projectReceivableBalance(projectId);
      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 2000000,
        date: '1404/02/05',
      );
      final entryId = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'دریافت طلب پروژه')
          .id!;

      await db.updateProjectReceipt(
        entryId: entryId,
        cashAccountId: cashAccount.id!,
        amount: 5000000,
        date: '1404/02/05',
      );

      expect(await db.projectReceivableBalance(projectId), arBeforeReceipt - 5000000);
    });
  });

  group('updateProjectReceipt — محافظت‌ها', () {
    test('سند دستی (manual) رد می‌شود', () async {
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
        () => db.updateProjectReceipt(
            entryId: manualId, cashAccountId: cashAccount.id!, amount: 200000, date: '1404/02/01'),
        throwsA(isA<Exception>()),
      );
    });

    test('سند سیستمی غیردریافتی (مثل تخفیف) رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/01');
      await db.recordProjectDiscount(projectId: projectId, amount: 1000000, date: '1404/02/02');
      final cashAccount = (await db.getCashAccounts()).first;

      final discountEntry = (await db.getJournalEntries(projectId: projectId))
          .firstWhere((e) => e.description == 'تخفیف نهایی پروژه');

      expect(
        () => db.updateProjectReceipt(
            entryId: discountEntry.id!, cashAccountId: cashAccount.id!, amount: 500000, date: '1404/02/02'),
        throwsA(isA<Exception>()),
      );
    });

    test('سند چندسطریِ تقسیم‌شده بابت مازاد دریافتی رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست - Overflow');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/02/02');
      final cashAccount = (await db.getCashAccounts()).first;

      // دریافت ۵۰ میلیون روی طلب ۱۰ میلیونی - بین AR و بستانکاری مشتری
      // تقسیم می‌شود (سه سطر: بدهکار نقد + بستانکار AR + بستانکار بستانکاری)
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
        () => db.updateProjectReceipt(
            entryId: overflowEntry.id!, cashAccountId: cashAccount.id!, amount: 40000000, date: '1404/02/05'),
        throwsA(isA<Exception>()),
      );
    });

    test('اگر پیش‌دریافت از زمان دریافت مصرف شده باشد (نهایی‌سازی)، ویرایش رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;

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
        () => db.updateProjectReceipt(
            entryId: entryId, cashAccountId: cashAccount.id!, amount: 4000000, date: '1404/02/01'),
        throwsA(isA<Exception>()),
      );
    });

    test('مبلغ صفر یا منفی رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری تست');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 1000000,
        date: '1404/02/01',
      );
      final entryId = (await db.getJournalEntries(projectId: projectId)).first.id!;

      expect(
        () => db.updateProjectReceipt(
            entryId: entryId, cashAccountId: cashAccount.id!, amount: 0, date: '1404/02/01'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
