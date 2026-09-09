// تست‌های گزارش «دریافت و هزینه» (جایگزین وضعیت مالی قدیمی) - این گزارش
// کاملاً نقدی است: دسته‌بندی cashReceiptsBreakdown/cashReceiptEntries بر
// مبنای طرف‌مقابل سند دریافت وجه، و expenseBreakdownDetailed برای تفکیک
// هزینه به زیرحساب، به همراه drill-down به فهرست اسناد هر دسته.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daftaryar/db/database_helper.dart';
import 'package:daftaryar/models/account.dart';
import 'package:daftaryar/models/cash_receipt_category.dart';
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

  group('cashReceiptsBreakdown / cashReceiptEntries — دسته‌بندی دریافتی نقدی', () {
    test('پیش‌دریافت پروژه‌محور (پیش از Finalization) در دسته پروژه‌ها می‌رود', () async {
      final cpId = await createCounterparty('مشتری الف');
      final projectId = await createProject(cpId);
      final cash = (await db.getCashAccounts()).first;

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cash.id!,
        amount: 15000000,
        date: '1404/02/05',
      );

      final breakdown = await db.cashReceiptsBreakdown(fromDate: '1404/01/01', toDate: '1404/12/29');
      expect(breakdown[CashReceiptCategory.projects], 15000000);
      expect(breakdown[CashReceiptCategory.directIncome], isNull);
      expect(breakdown[CashReceiptCategory.other], isNull);

      final entries =
          await db.cashReceiptEntries(category: CashReceiptCategory.projects, fromDate: '1404/01/01', toDate: '1404/12/29');
      expect(entries.length, 1);
      expect(entries.first.description, 'پیش‌دریافت پروژه');
    });

    test('تسویه طلب پس از Finalization هم در دسته پروژه‌ها می‌رود', () async {
      final cpId = await createCounterparty('مشتری ب');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 80000000, date: '1404/02/01');
      final cash = (await db.getCashAccounts()).first;

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cash.id!,
        amount: 30000000,
        date: '1404/02/10',
      );

      final breakdown = await db.cashReceiptsBreakdown(fromDate: '1404/01/01', toDate: '1404/12/29');
      expect(breakdown[CashReceiptCategory.projects], 30000000);
    });

    test('دریافت مستقیم روی یک حساب درآمدی بدون پروژه، در دسته «درآمد مستقیم» می‌رود', () async {
      final cash = (await db.getCashAccounts()).first;
      final otherIncome =
          (await db.getAccounts(type: kAccountIncome)).firstWhere((a) => a.name == 'سایر درآمدها');

      await db.createManualJournal(JournalEntryModel(
        date: '1404/03/01',
        createdAt: '1404/03/01',
        description: 'فروش نقشه اضافه',
        lines: [
          JournalLineModel(accountId: cash.id!, debit: 2000000),
          JournalLineModel(accountId: otherIncome.id!, credit: 2000000),
        ],
      ));

      final breakdown = await db.cashReceiptsBreakdown(fromDate: '1404/01/01', toDate: '1404/12/29');
      expect(breakdown[CashReceiptCategory.directIncome], 2000000);
      expect(breakdown[CashReceiptCategory.projects], isNull);
    });

    test('آورده مالک به سرمایه در دسته «سایر منابع» می‌رود', () async {
      final cash = (await db.getCashAccounts()).first;
      final capital =
          (await db.getAccounts(type: kAccountEquity)).firstWhere((a) => a.name == 'سرمایه');

      await db.createManualJournal(JournalEntryModel(
        date: '1404/03/05',
        createdAt: '1404/03/05',
        description: 'آورده نقدی مالک',
        lines: [
          JournalLineModel(accountId: cash.id!, debit: 5000000),
          JournalLineModel(accountId: capital.id!, credit: 5000000),
        ],
      ));

      final breakdown = await db.cashReceiptsBreakdown(fromDate: '1404/01/01', toDate: '1404/12/29');
      expect(breakdown[CashReceiptCategory.other], 5000000);
    });

    test('بازه تاریخ فیلتر می‌شود - دریافتی خارج از بازه شمرده نمی‌شود', () async {
      final cpId = await createCounterparty('مشتری ج');
      final projectId = await createProject(cpId);
      final cash = (await db.getCashAccounts()).first;

      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cash.id!, amount: 1000000, date: '1404/01/10');
      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cash.id!, amount: 2000000, date: '1404/05/10');

      final breakdown = await db.cashReceiptsBreakdown(fromDate: '1404/05/01', toDate: '1404/05/30');
      expect(breakdown[CashReceiptCategory.projects], 2000000,
          reason: 'فقط دریافتی داخل بازه باید شمرده شود');
    });
  });

  group('accountChildrenBreakdown / accountBalanceWithDescendants — تفکیک سلسله‌مراتبی هزینه', () {
    test('یک برگ بدون زیرحساب مستقیم در سطح سرشاخه‌ها ظاهر می‌شود و فهرست اسناد آن قابل بازیابی است', () async {
      final cash = (await db.getCashAccounts()).first;
      final transport =
          (await db.getAccounts(type: kAccountExpense)).firstWhere((a) => a.name == 'حمل و نقل');

      await db.createManualJournal(JournalEntryModel(
        date: '1404/02/15',
        createdAt: '1404/02/15',
        description: 'کرایه رفت‌وآمد میدانی',
        lines: [
          JournalLineModel(accountId: transport.id!, debit: 800000),
          JournalLineModel(accountId: cash.id!, credit: 800000),
        ],
      ));

      final roots =
          await db.accountChildrenBreakdown(kAccountExpense, fromDate: '1404/01/01', toDate: '1404/12/29');
      final row = roots.firstWhere((r) => (r['account'] as AccountModel).name == 'حمل و نقل');
      expect(row['total'], 800000);
      expect(row['hasChildren'], false);

      final entries = await db.getJournalEntries(
          accountId: transport.id, fromDate: '1404/01/01', toDate: '1404/12/29');
      expect(entries.length, 1);
      expect(entries.first.description, 'کرایه رفت‌وآمد میدانی');
    });

    test('سرشاخه = مجموع زیرشاخه‌ها؛ زیرشاخه با زیرشاخه ادامه‌دار درست جمع می‌بندد تا برگ', () async {
      final cash = (await db.getCashAccounts()).first;
      final officeExpense =
          (await db.getAccounts(type: kAccountExpense)).firstWhere((a) => a.name == 'هزینه‌های دفتر');

      // یک زیرشاخه مستقیم زیر سرشاخه، و یک زیرشاخهِ زیرشاخه (دو سطح پایین‌تر)
      final level1 = await db.insertAccount(AccountModel(
        name: 'اجاره دفتر',
        type: kAccountExpense,
        parentId: officeExpense.id,
        allowChildren: true,
        createdAt: '1404/01/01',
      ));
      final level2 = await db.insertAccount(AccountModel(
        name: 'اجاره شعبه مرکزی',
        type: kAccountExpense,
        parentId: level1,
        createdAt: '1404/01/01',
      ));

      await db.createManualJournal(JournalEntryModel(
        date: '1404/02/20',
        createdAt: '1404/02/20',
        description: 'اجاره ماهانه شعبه مرکزی',
        lines: [
          JournalLineModel(accountId: level2, debit: 3000000),
          JournalLineModel(accountId: cash.id!, credit: 3000000),
        ],
      ));

      // سرشاخه («هزینه‌های دفتر») باید کل ۳ میلیون را از دو سطح پایین‌تر رول‌آپ کند
      final rootTotal =
          await db.accountBalanceWithDescendants(officeExpense.id!, fromDate: '1404/01/01', toDate: '1404/12/29');
      expect(rootTotal, 3000000);

      final roots =
          await db.accountChildrenBreakdown(kAccountExpense, fromDate: '1404/01/01', toDate: '1404/12/29');
      final officeRow = roots.firstWhere((r) => (r['account'] as AccountModel).id == officeExpense.id);
      expect(officeRow['total'], 3000000);
      expect(officeRow['hasChildren'], true);

      final underOffice = await db.accountChildrenBreakdown(kAccountExpense,
          parentId: officeExpense.id, fromDate: '1404/01/01', toDate: '1404/12/29');
      expect(underOffice.length, 1);
      expect(underOffice.first['total'], 3000000);
      expect(underOffice.first['hasChildren'], true);

      final underLevel1 =
          await db.accountChildrenBreakdown(kAccountExpense, parentId: level1, fromDate: '1404/01/01', toDate: '1404/12/29');
      expect(underLevel1.length, 1);
      expect((underLevel1.first['account'] as AccountModel).name, 'اجاره شعبه مرکزی');
      expect(underLevel1.first['total'], 3000000);
      expect(underLevel1.first['hasChildren'], false);
    });
  });
}
