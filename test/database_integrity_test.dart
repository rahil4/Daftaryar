// تست‌های یکپارچگی دیتابیس (Financial Data Integrity Hardening). این‌ها به
// sqflite_common_ffi نیاز دارند (بدون دستگاه/شبیه‌ساز واقعی اجرا می‌شوند)؛
// در محیط توسعه فعلی (بدون نصب Flutter SDK) اجرا نشده‌اند - رجوع کنید به
// گزارش نهایی، بخش «Do Not Claim Success Without Evidence».
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daftaryar/db/database_helper.dart';
import 'package:daftaryar/services/data_health_service.dart';
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
    // هر تست از یک وضعیت کاملاً تمیز شروع می‌شود تا تست‌ها به‌هم وابسته نباشند
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

  group('مورد ۵ — Atomic بودن Finalization', () {
    test('سناریوی موفق: پروژه Finalize و Journal/PriceEvent صحیح ایجاد می‌شود', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);

      await db.finalizeProject(projectId: projectId, finalAmount: 120000000, date: '1404/02/01');

      final project = await db.getProject(projectId);
      expect(project!.isFinalized, true);
      expect(project.finalAmount, 120000000);

      final revenueBalance = await db.projectRevenueLedgerBalance(projectId);
      expect(revenueBalance, 120000000, reason: 'درآمد باید در Ledger شناسایی شده باشد');
    });

    test('Idempotency: نهایی‌سازی تکراری رد می‌شود و سند دوم نمی‌سازد', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 100000000, date: '1404/02/01');

      expect(
        () => db.finalizeProject(projectId: projectId, finalAmount: 999, date: '1404/02/02'),
        throwsA(isA<Exception>()),
      );

      final revenueBalance = await db.projectRevenueLedgerBalance(projectId);
      expect(revenueBalance, 100000000, reason: 'تلاش دوم نباید مبلغ درآمد را تغییر دهد');
    });
  });

  group('مورد ۸ — کنترل Overpayment در سطح Project', () {
    test('receiveProjectPayment هرگز throw نمی‌کند - مازاد Graceful به بستانکاری مشتری می‌رود (رفتار عمدی Stage 1، نه باگ)', () async {
      final cpId = await createCounterparty('مشتری مشترک - Overflow');
      final projectB = await createProject(cpId);
      await db.finalizeProject(projectId: projectB, finalAmount: 10000000, date: '1404/02/02');
      final cashAccount = (await db.getCashAccounts()).first;

      // دریافت ۵۰ میلیون روی پروژه‌ای با طلب فقط ۱۰ میلیون - طبق طراحی
      // عمدی Stage 1 (_creditArWithOverflowGuard)، این هرگز throw نمی‌کند؛
      // ۱۰ میلیون به AR و ۴۰ میلیون مازاد به «بستانکاری مشتری» می‌رود.
      await db.receiveProjectPayment(
        projectId: projectB,
        cashAccountId: cashAccount.id!,
        amount: 50000000,
        date: '1404/02/05',
      );

      final projectBAr = await db.projectReceivableBalance(projectB);
      final projectBCredit = await db.projectCustomerCreditBalance(projectB);
      expect(projectBAr, 0, reason: 'کل طلب ۱۰ میلیونی باید تسویه شده باشد');
      expect(projectBCredit, 40000000,
          reason: 'مازاد ۴۰ میلیون باید Graceful به بستانکاری مشتری برود، نه این‌که خطا بدهد یا AR را منفی کند');
    });

    test('یک سند دستی خام (نه Workflow با Overflow Guard) که AR پروژه B را بیش از مانده واقعی‌اش بستانکار کند رد می‌شود', () async {
      final cpId = await createCounterparty('مشتری مشترک');
      final projectA = await createProject(cpId);
      final projectB = await createProject(cpId);

      // پروژه A نهایی می‌شود و طلب ۱۰۰ میلیونی ایجاد می‌کند
      await db.finalizeProject(projectId: projectA, finalAmount: 100000000, date: '1404/02/01');
      final counterpartyArBefore = await db.receivableBalance(cpId);
      expect(counterpartyArBefore, 100000000);

      // پروژه B هم Finalize می‌شود تا مانده AR واقعی و محدود (۱۰ میلیون) داشته باشد
      await db.finalizeProject(projectId: projectB, finalAmount: 10000000, date: '1404/02/02');

      final arAccount = await db.getReceivableAccount();
      final cashAccount = (await db.getCashAccounts()).first;

      // برخلاف receiveProjectPayment (که از _creditArWithOverflowGuard عبور
      // می‌کند و هرگز خطا نمی‌دهد)، یک سند دستی خام مستقیماً سعی می‌کند
      // ۵۰ میلیون از AR پروژه B را بستانکار کند - در حالی که مانده واقعی
      // آن فقط ۱۰ میلیون است (مانده کل طرف‌حساب ۱۱۰ میلیون است، پس کنترل
      // سطح طرف‌حساب به‌تنهایی این را اشتباهاً قبول می‌کرد). کنترل سطح
      // پروژه در _validateJournalEntry باید این مسیر بدون Overflow Guard
      // را رد کند - دقیقاً همان‌جایی که محافظت سطح پروژه واقعاً لازم است.
      expect(
        () => db.createManualJournal(JournalEntryModel(
          date: '1404/02/05',
          createdAt: '1404/02/05',
          lines: [
            JournalLineModel(
                accountId: cashAccount.id!,
                debit: 50000000,
                counterpartyId: cpId,
                projectId: projectB),
            JournalLineModel(
                accountId: arAccount!.id!,
                credit: 50000000,
                counterpartyId: cpId,
                projectId: projectB),
          ],
        )),
        throwsA(isA<Exception>()),
        reason: 'پروژه B فقط ۱۰ میلیون طلب دارد؛ یک سند دستی نباید بتواند ۵۰ میلیون از AR آن را بستانکار کند',
      );

      final projectBAr = await db.projectReceivableBalance(projectB);
      expect(projectBAr, 10000000,
          reason: 'مانده پروژه B باید دقیقاً همان ۱۰ میلیون اولیه بماند - سند رد‌شده نباید هیچ اثری گذاشته باشد');
    });
  });

  group('مورد ۴ — محافظت حذف سند System-generated', () {
    test('سند حاصل از Finalization قابل حذف نیست', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 100000000, date: '1404/02/01');

      final entries = await db.getJournalEntries(projectId: projectId);
      expect(entries, isNotEmpty);
      final systemEntry = entries.first;
      expect(systemEntry.isSystemGenerated, true);

      expect(
        () => db.deleteJournalEntry(systemEntry.id!),
        throwsA(isA<Exception>()),
      );

      final stillExists = await db.getJournalEntry(systemEntry.id!);
      expect(stillExists, isNotNull, reason: 'سند سیستمی باید بدون تغییر باقی مانده باشد');
    });

    test('سند دستی صریح (source=manual) همچنان قابل حذف است', () async {
      // تغییر نسبت به مرحله قبل: دیگر صرفاً «بدون source» به معنی قابل‌حذف
      // نیست؛ باید صراحتاً از createManualJournal (یا source=manual) استفاده
      // شود - دقیقاً همان چیزی که این تست بررسی می‌کند.
      final cpId = await createCounterparty('محمد');
      final accounts = await db.getPostableAccounts();
      final cash = (await db.getCashAccounts()).first;
      final income = accounts.firstWhere((a) => a.type == kAccountIncome);

      final entryId = await db.createManualJournal(JournalEntryModel(
        date: '1404/01/01',
        createdAt: '1404/01/01',
        lines: [
          JournalLineModel(accountId: cash.id!, debit: 1000000, counterpartyId: cpId),
          JournalLineModel(accountId: income.id!, credit: 1000000, counterpartyId: cpId),
        ],
      ));

      await db.deleteJournalEntry(entryId);
      final afterDelete = await db.getJournalEntry(entryId);
      expect(afterDelete, isNull, reason: 'سند دستی صریح باید با موفقیت حذف شود');
    });

    test('مورد ۵ — سند با source نامشخص (NULL/Legacy) محافظت‌شده است، نه قابل‌حذف', () async {
      final cpId = await createCounterparty('محمد');
      final accounts = await db.getPostableAccounts();
      final cash = (await db.getCashAccounts()).first;
      final income = accounts.firstWhere((a) => a.type == kAccountIncome);

      // شبیه‌سازی یک سند «قدیمی» که از مسیر insertJournalEntry خام (بدون
      // source) وارد شده - مثلاً باقی‌مانده از پیش از افزودن این مکانیزم.
      final entryId = await db.insertJournalEntry(JournalEntryModel(
        date: '1404/01/01',
        createdAt: '1404/01/01',
        lines: [
          JournalLineModel(accountId: cash.id!, debit: 500000, counterpartyId: cpId),
          JournalLineModel(accountId: income.id!, credit: 500000, counterpartyId: cpId),
        ],
      ));

      expect(
        () => db.deleteJournalEntry(entryId),
        throwsA(isA<Exception>()),
        reason: 'سند با source نامشخص نباید حدس زده شود که دستی بوده؛ باید محافظت شود',
      );
    });
  });

  group('مورد ۳ — محافظت System Account', () {
    test('ویرایش نام حساب سیستمی، systemKey را حفظ می‌کند', () async {
      final arAccount = await db.getReceivableAccount();
      expect(arAccount, isNotNull);

      await db.updateAccount(arAccount!.copyWith(name: 'نام جدید حساب دریافتنی'));

      final afterEdit = await db.getReceivableAccount();
      expect(afterEdit, isNotNull, reason: 'حساب باید همچنان از طریق systemKey پیدا شود');
      expect(afterEdit!.name, 'نام جدید حساب دریافتنی');
      expect(afterEdit.systemKey, kSystemKeyReceivable);
    });

    test('حتی تلاش صریح برای حذف systemKey یک حساب سیستمی نادیده گرفته می‌شود', () async {
      final arAccount = await db.getReceivableAccount();
      // شبیه‌سازی یک فراخوانی اشتباه که سعی می‌کند systemKey را null کند
      await db.updateAccount(AccountModel(
        id: arAccount!.id,
        name: arAccount.name,
        type: arAccount.type,
        isSystem: false, // تلاش برای تبدیل به غیرسیستمی
        systemKey: null, // تلاش برای حذف systemKey
        createdAt: arAccount.createdAt,
      ));

      final afterAttempt = await db.getReceivableAccount();
      expect(afterAttempt, isNotNull,
          reason: 'لایه دیتابیس باید systemKey/isSystem را مستقل از ورودی محافظت کند');
      expect(afterAttempt!.systemKey, kSystemKeyReceivable);
      expect(afterAttempt.isSystem, true);
    });

    test('حذف فیزیکی حساب سیستمی رد می‌شود', () async {
      final arAccount = await db.getReceivableAccount();
      expect(
        () => db.deleteAccount(arAccount!.id!),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('مورد ۱۰ — Quick Receipt پروژه‌محور', () {
    test('دریافت روی پروژه Finalize‌نشده به Advance می‌رود، نه Revenue', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      final cashAccount = (await db.getCashAccounts()).first;

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 20000000,
        date: '1404/01/10',
      );

      final advanceBalance = await db.projectAdvanceBalance(projectId);
      final revenueBalance = await db.projectRevenueLedgerBalance(projectId);
      expect(advanceBalance, 20000000, reason: 'مبلغ باید به پیش‌دریافت برود');
      expect(revenueBalance, 0, reason: 'هیچ درآمدی نباید شناسایی شده باشد');
    });

    test('دریافت روی پروژه Finalize‌شده به تسویه AR می‌رود', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 100000000, date: '1404/02/01');
      final cashAccount = (await db.getCashAccounts()).first;

      await db.receiveProjectPayment(
        projectId: projectId,
        cashAccountId: cashAccount.id!,
        amount: 40000000,
        date: '1404/02/05',
      );

      final arBalance = await db.projectReceivableBalance(projectId);
      expect(arBalance, 60000000, reason: 'مانده طلب باید کاهش یابد، نه این‌که درآمد دوباره ثبت شود');
    });
  });

  group('مرحله ۱.۱ — مورد ۱: محافظت کامل‌تر System Account', () {
    test('تلاش برای تغییر type یک حساب سیستمی نادیده گرفته می‌شود', () async {
      final arAccount = await db.getReceivableAccount();
      await db.updateAccount(AccountModel(
        id: arAccount!.id,
        name: arAccount.name,
        type: kAccountExpense, // تلاش برای تبدیل دارایی به هزینه
        isSystem: arAccount.isSystem,
        systemKey: arAccount.systemKey,
        createdAt: arAccount.createdAt,
      ));
      final after = await db.getReceivableAccount();
      expect(after!.type, kAccountAsset, reason: 'نوع حساب سیستمی نباید تغییر کند');
    });

    test('تلاش برای دادن والد به یک حساب سیستمی نادیده گرفته می‌شود', () async {
      final arAccount = await db.getReceivableAccount();
      final someOtherAsset = (await db.getPostableAccounts(type: kAccountAsset))
          .firstWhere((a) => a.id != arAccount!.id);
      await db.updateAccount(arAccount!.copyWith(parentId: someOtherAsset.id));
      final after = await db.getReceivableAccount();
      expect(after!.parentId, isNull, reason: 'حساب کنترلی سیستمی نباید زیرمجموعه چیز دیگری شود');
    });

    test('انتخاب یک حساب سیستمی به‌عنوان والد یک حساب جدید رد می‌شود', () async {
      final arAccount = await db.getReceivableAccount();
      expect(
        () => db.insertAccount(AccountModel(
          name: 'زیرحساب اشتباه',
          type: kAccountAsset,
          parentId: arAccount!.id,
          createdAt: '1404/01/01',
        )),
        throwsA(isA<Exception>()),
        reason: 'اگر مجاز بود، AR غیرقابل‌ثبت (non-postable) می‌شد و تمام Workflowهای مالی می‌شکستند',
      );
    });

    test('حذف حساب سیستمی رد می‌شود (Regression مرحله ۱)', () async {
      final arAccount = await db.getReceivableAccount();
      expect(() => db.deleteAccount(arAccount!.id!), throwsA(isA<Exception>()));
    });
  });

  group('مرحله ۱.۱ — مورد ۲: تغییرناپذیری Counterparty پروژه دارای سابقه مالی', () {
    test('سناریو ۱ - بدون سابقه مالی: تغییر کارفرما مجاز است', () async {
      final cpA = await createCounterparty('کارفرمای A');
      final cpB = await createCounterparty('کارفرمای B');
      final projectId = await createProject(cpA);

      final project = await db.getProject(projectId);
      await db.updateProject(project!.copyWith(counterpartyId: cpB));

      final after = await db.getProject(projectId);
      expect(after!.counterpartyId, cpB);
    });

    test('سناریو ۲ - با سابقه مالی (پیش از Finalize): تغییر کارفرما رد می‌شود', () async {
      final cpA = await createCounterparty('کارفرمای A');
      final cpB = await createCounterparty('کارفرمای B');
      final projectId = await createProject(cpA);
      final cashAccount = (await db.getCashAccounts()).first;

      // فقط یک پیش‌دریافت، بدون Finalization
      await db.receiveProjectPayment(
        projectId: projectId, cashAccountId: cashAccount.id!, amount: 10000000, date: '1404/01/05');

      final project = await db.getProject(projectId);
      expect(
        () => db.updateProject(project!.copyWith(counterpartyId: cpB)),
        throwsA(isA<Exception>()),
      );
    });

    test('سناریو ۳ - پروژه Finalized: تغییر کارفرما رد می‌شود', () async {
      final cpA = await createCounterparty('کارفرمای A');
      final cpB = await createCounterparty('کارفرمای B');
      final projectId = await createProject(cpA);
      await db.finalizeProject(projectId: projectId, finalAmount: 50000000, date: '1404/02/01');

      final project = await db.getProject(projectId);
      expect(
        () => db.updateProject(project!.copyWith(counterpartyId: cpB)),
        throwsA(isA<Exception>()),
      );
    });

    test('سناریو ۴ - تغییر اطلاعات غیرمالی (عنوان) پروژه Finalize‌نشده مجاز است', () async {
      final cpA = await createCounterparty('کارفرمای A');
      final projectId = await createProject(cpA);
      final project = await db.getProject(projectId);
      await db.updateProject(project!.copyWith(title: 'عنوان جدید'));
      final after = await db.getProject(projectId);
      expect(after!.title, 'عنوان جدید');
    });
  });

  group('مرحله ۱.۱ — مورد ۳/۴: Integrity و State Machine در updateProject', () {
    test('پروژه عادی نمی‌تواند مستقیماً از طریق updateProject به نهایی‌شده تبدیل شود', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      final project = await db.getProject(projectId);
      expect(
        () => db.updateProject(project!.copyWith(status: kProjectStatusFinalized)),
        throwsA(isA<Exception>()),
        reason: 'Finalization بدون finalAmount/Journal واقعی نباید ممکن باشد',
      );
    });

    test('پروژه نهایی‌شده نمی‌تواند از طریق Update عمومی به لغوشده تبدیل شود', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/01/01');
      final project = await db.getProject(projectId);
      expect(
        () => db.updateProject(project!.copyWith(status: kProjectStatusCancelled)),
        throwsA(isA<Exception>()),
        reason: 'ترکیب Finalized+Cancelled در این مدل معتبر نیست',
      );
    });

    test('پروژه عادی نمی‌تواند مستقیماً از طریق updateProject به لغوشده تبدیل شود'
        ' (اصلاح مرحله ۱.۱ - قبلاً این مسیر مجاز بود، اکنون باید از cancelProject'
        ' اختصاصی عبور کند)', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      final project = await db.getProject(projectId);
      expect(
        () => db.updateProject(project!.copyWith(status: kProjectStatusCancelled)),
        throwsA(isA<Exception>()),
        reason: 'State transition به Cancelled باید صریح و از Workflow اختصاصی باشد',
      );
    });

    test('cancelProject به‌درستی پروژه عادی را لغو می‌کند (Workflow اختصاصی جدید)', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      await db.cancelProject(projectId);
      final after = await db.getProject(projectId);
      expect(after!.status, kProjectStatusCancelled);
    });

    test('cancelProject روی پروژه نهایی‌شده رد می‌شود', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/01/01');
      expect(() => db.cancelProject(projectId), throwsA(isA<Exception>()));
    });

    test('finalizeProject روی پروژه لغوشده رد می‌شود (تکمیل Invariant Cancelled+Finalized)', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      await db.cancelProject(projectId);
      expect(
        () => db.finalizeProject(projectId: projectId, finalAmount: 1000000, date: '1404/01/01'),
        throwsA(isA<Exception>()),
      );
    });

    test('ترکیب نامعتبر Cancelled+finalAmount رد می‌شود', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      final project = await db.getProject(projectId);
      expect(
        () => db.updateProject(
            project!.copyWith(status: kProjectStatusCancelled, finalAmount: 1000)),
        throwsA(isA<Exception>()),
      );
    });

    test('پروژه نهایی‌شده: تلاش برای تغییر finalAmount از Update عمومی رد می‌شود', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/01/01');
      final project = await db.getProject(projectId);
      expect(
        () => db.updateProject(project!.copyWith(finalAmount: 99999999)),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('مورد ۶/۹ — مقدار صریح Journal Source در هر دو مسیر', () {
    test('Workflow سیستمی (Finalization) دقیقاً source=system تولید می‌کند', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId);
      await db.finalizeProject(projectId: projectId, finalAmount: 10000000, date: '1404/01/01');
      final entries = await db.getJournalEntries(projectId: projectId);
      expect(entries, isNotEmpty);
      for (final e in entries) {
        expect(e.source, kJournalSourceSystem);
      }
    });

    test('createManualJournal دقیقاً source=manual تولید می‌کند، حتی اگر ورودی چیز دیگری بدهد', () async {
      final cpId = await createCounterparty('محمد');
      final cash = (await db.getCashAccounts()).first;
      final income = (await db.getPostableAccounts()).firstWhere((a) => a.type == kAccountIncome);
      final entryId = await db.createManualJournal(JournalEntryModel(
        date: '1404/01/01',
        createdAt: '1404/01/01',
        source: kJournalSourceSystem, // تلاش عمدی برای گمراه‌کردن - باید نادیده گرفته شود
        lines: [
          JournalLineModel(accountId: cash.id!, debit: 200000, counterpartyId: cpId),
          JournalLineModel(accountId: income.id!, credit: 200000, counterpartyId: cpId),
        ],
      ));
      final entry = await db.getJournalEntry(entryId);
      expect(entry!.source, kJournalSourceManual,
          reason: 'createManualJournal باید صرف‌نظر از source ورودی، manual را enforce کند');
    });
  });

  group('مورد ۸ — یادداشت درباره Backup/Restore', () {
    test('insertJournalEntry پایه، مقدار source ورودی را دست‌نخورده نگه می‌دارد'
        ' (پیش‌نیاز صحت Restore - رجوع به گزارش نهایی برای محدودیت پوشش تست)', () async {
      // این تست خودِ فایل پشتیبان یا FilePicker را شبیه‌سازی نمی‌کند (نیازمند
      // Mock کردن Platform Channel فراتر از sqflite_common_ffi است)؛ فقط
      // تضمین می‌کند که تابع پایه‌ای که BackupService برای Restore استفاده
      // می‌کند (insertJournalEntry، نه createManualJournal/createSystemJournal)
      // مقدار source را force نمی‌کند - دقیقاً رفتاری که Restore به آن متکی است.
      final cpId = await createCounterparty('محمد');
      final cash = (await db.getCashAccounts()).first;
      final income = (await db.getPostableAccounts()).firstWhere((a) => a.type == kAccountIncome);

      final systemLikeId = await db.insertJournalEntry(JournalEntryModel(
        date: '1404/01/01',
        createdAt: '1404/01/01',
        source: kJournalSourceSystem,
        lines: [
          JournalLineModel(accountId: cash.id!, debit: 300000, counterpartyId: cpId),
          JournalLineModel(accountId: income.id!, credit: 300000, counterpartyId: cpId),
        ],
      ));
      final restored = await db.getJournalEntry(systemLikeId);
      expect(restored!.source, kJournalSourceSystem,
          reason: 'Restore یک سند سیستمی قدیمی نباید آن را به manual تبدیل کند');
    });
  });

  group('Account Hierarchy (گزینه A) — تفکیک Leaf-Lock از Identity Protection', () {
    test('صندوق/بانک اکنون می‌توانند زیرحساب بگیرند (allowChildren=true)', () async {
      final assetAccounts = await db.getAccounts(type: kAccountAsset);
      final bankAccount = assetAccounts.firstWhere((a) => a.systemKey == kSystemKeyBank);
      expect(bankAccount.allowChildren, true);
      final newSubAccountId = await db.insertAccount(AccountModel(
        name: 'بانک ملی',
        type: kAccountAsset,
        parentId: bankAccount.id,
        createdAt: '1404/01/01',
      ));
      final saved = await db.getAccount(newSubAccountId);
      expect(saved!.parentId, bankAccount.id,
          reason: 'برخلاف قبل از این تغییر، ساخت زیرحساب زیر «بانک» اکنون باید مجاز باشد');
    });

    test('حساب‌های کنترلی واقعی (AR/Advance/Revenue/Overhead/Discount) همچنان'
        ' Leaf-Locked هستند (Regression محافظت قبلی)', () async {
      final controlKeys = [
        kSystemKeyReceivable,
        kSystemKeyCustomerAdvance,
        kSystemKeyProjectRevenue,
        kSystemKeyProjectOverhead,
        kSystemKeyServiceDiscount,
      ];
      final allAccounts = await db.getAccounts();
      for (final key in controlKeys) {
        final acc = allAccounts.firstWhere((a) => a.systemKey == key);
        expect(acc.allowChildren, false, reason: '$key باید Leaf-Locked بماند');
        expect(
          () => db.insertAccount(AccountModel(
              name: 'زیرحساب اشتباه برای $key',
              type: acc.type,
              parentId: acc.id,
              createdAt: '1404/01/01')),
          throwsA(isA<Exception>()),
          reason: '$key هرگز نباید بتواند والد شود؛ وگرنه Workflowهای مالی که مستقیم'
              ' روی id آن سند می‌زنند می‌شکنند',
        );
      }
    });

    test('ویرایش عمومی نمی‌تواند allowChildren یک حساب سیستمی را دستکاری کند', () async {
      final arAccount = await db.getReceivableAccount();
      await db.updateAccount(arAccount!.copyWith(allowChildren: true));
      final after = await db.getReceivableAccount();
      expect(after!.allowChildren, false,
          reason: 'allowChildren یک حساب کنترلی باید مثل systemKey/isSystem/type محافظت‌شده باشد');
    });

    test('وصولی مستقیم به یک زیرحساب بانکی، در AR Movement به‌درستی «وصولی نقدی» طبقه‌بندی می‌شود'
        ' (رفع اثر جانبی Movement Classification)', () async {
      final assetAccounts2 = await db.getAccounts(type: kAccountAsset);
      final bankAccount = assetAccounts2.firstWhere((a) => a.systemKey == kSystemKeyBank);
      final bankMelliId = await db.insertAccount(AccountModel(
        name: 'بانک ملی',
        type: kAccountAsset,
        parentId: bankAccount.id,
        createdAt: '1404/01/01',
      ));

      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId, agreedAmount: 100000000);
      await db.finalizeProject(projectId: projectId, finalAmount: 100000000, date: '1404/01/10');

      // دریافت مستقیم به زیرحساب «بانک ملی» (نه خودِ «بانک»)، از طریق سند
      // دستی چون Workflow آماده receiveProjectPayment حساب صندوق/بانک را
      // از getCashAccounts می‌گیرد که بانک ملی را هم به‌درستی برمی‌گرداند.
      final cashAccounts = await db.getCashAccounts();
      expect(cashAccounts.any((a) => a.id == bankMelliId), true,
          reason: 'getCashAccounts باید بانک ملی را هم به‌عنوان حساب نقدی/بانکی بشناسد');

      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: bankMelliId, amount: 40000000, date: '1404/01/15');

      final movement = await db.arMovement(projectId: projectId);
      expect(movement['collections'], 40000000,
          reason: 'وصولی به زیرحساب بانکی باید Collections طبقه‌بندی شود، نه «سایر»'
              ' (بدون این اصلاح، otherKey مستقیم null بود چون بانک ملی خودش systemKey ندارد)');
    });
  });

  group('حساب‌های کنترلی — systemKey (رگرسیون باگ بحرانی صفر شدن همه مانده‌ها)', () {
    test('همه حساب‌های کنترلی باید systemKey داشته باشند، وگرنه محاسبات'
        ' مطالبات/پیش‌دریافت/بستانکاری بی‌سروصدا صفر برمی‌گردند', () async {
      // این تست از یک باگ واقعی محافظت می‌کند: ستون systemKey بعداً به
      // جدول accounts اضافه شد ولی Migration آن را برای حساب‌های موجود پر
      // نمی‌کرد. چون _projectControlAccountBalance وقتی حساب را پیدا نکند
      // به‌جای خطا، صفر برمی‌گرداند، این نقص هیچ نشانه‌ای نشان نمی‌داد -
      // فقط همه اعداد داشبورد صفر بودند در حالی که اسناد واقعی وجود داشتند.
      expect(await db.getReceivableAccount(), isNotNull, reason: 'حساب دریافتنی باید یافت شود');
      expect(await db.getPayableAccount(), isNotNull);
      expect(await db.getCustomerAdvanceAccount(), isNotNull);
      expect(await db.getCustomerCreditAccount(), isNotNull);
      expect(await db.getProjectRevenueAccount(), isNotNull);
      expect(await db.getProjectOverheadAccount(), isNotNull);
      expect(await db.getServiceDiscountAccount(), isNotNull);
      expect((await db.getCashAccounts()), isNotEmpty, reason: 'صندوق/بانک باید یافت شوند');
    });

    test('پیش‌دریافت یک پروژه نهایی‌نشده واقعاً محاسبه می‌شود (نه صفر)', () async {
      final cpId = await createCounterparty('مشتری پیش‌دریافت');
      final projectId = await createProject(cpId, agreedAmount: 100000000);
      final cash = (await db.getCashAccounts()).first;

      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cash.id!, amount: 30000000, date: '1404/06/01');

      final advance = await db.projectAdvanceBalance(projectId);
      expect(advance, 30000000,
          reason: 'پروژه نهایی‌نشده: دریافت باید به پیش‌دریافت برود و در مانده دیده شود');

      // و باید در محاسبه دسته‌ای داشبورد هم دیده شود
      final batch = await db.advanceBalanceForOpenProjects();
      expect(batch[projectId], 30000000,
          reason: 'محاسبه دسته‌ای داشبورد باید همان عدد را بدهد');
    });
  });

  group('DataHealthService — بررسی سلامت ساختاری', () {
    test('دیتابیس سالم (پس از نصب اولیه) هیچ مشکلی گزارش نمی‌کند', () async {
      final result = await DataHealthService(db).run();
      expect(result.isHealthy, true,
          reason: 'نصب تازه باید همه حساب‌های کنترلی و دفتر متوازن داشته باشد. مشکلات: '
              '${result.issues.map((i) => i.title).join(" | ")}');
    });

    test('حذف یک حساب کنترلی، بلافاصله به‌عنوان مشکل بحرانی گزارش می‌شود', () async {
      // این دقیقاً همان دسته خرابی است که باگ systemKey را هفته‌ها پنهان
      // نگه داشت: از دید محاسبات مالی «همه مانده‌ها صفرند» معتبر به‌نظر
      // می‌رسید، ولی از دید یکپارچگی ساختاری یک خرابی آشکار است.
      final ar = await db.getReceivableAccount();
      final raw = await db.database;
      await raw.update('accounts', {'systemKey': null}, where: 'id = ?', whereArgs: [ar!.id]);

      final result = await DataHealthService(db).run();
      expect(result.isHealthy, false);
      expect(result.hasCritical, true);
      expect(result.issues.any((i) => i.title.contains('دریافتنی')), true,
          reason: 'باید دقیقاً همان حساب گمشده نام برده شود');
    });

    test('دفتر نامتوازن به‌عنوان مشکل بحرانی گزارش می‌شود', () async {
      // یک سطر تک‌طرفه مستقیم در دیتابیس (دور زدن اعتبارسنجی) - شبیه‌سازی
      // داده آسیب‌دیده
      final raw = await db.database;
      final cash = (await db.getCashAccounts()).first;
      final entryId = await raw.insert('journal_entries',
          {'date': '1404/01/01', 'createdAt': '1404/01/01', 'source': 'manual'});
      await raw.insert('journal_lines',
          {'entryId': entryId, 'accountId': cash.id, 'debit': 5000000, 'credit': 0});

      final result = await DataHealthService(db).run();
      expect(result.hasCritical, true);
      expect(result.issues.any((i) => i.title.contains('متوازن')), true);
    });
  });

  group('قرارداد پایداری (STABILITY.md)', () {
    test('نسخه دیتابیس بدون گفت‌وگوی صریح بالا نمی‌رود', () async {
      // این تست عمداً به یک عدد ثابت گره خورده است. اگر کسی (چه انسان، چه
      // دستیار هوش مصنوعی) نسخه دیتابیس را بالا ببرد، این تست می‌شکند و
      // مجبور می‌شود آگاهانه تصمیم بگیرد - نه اینکه یک Migration ساختاری
      // در میان بقیه تغییرات ناخواسته رد شود.
      //
      // پروژه در «حالت تثبیت» است؛ رجوع کنید به STABILITY.md.
      // اگر واقعاً یک Migration لازم است: STABILITY.md را بخوانید، مراحل
      // چهارگانه را انجام دهید، و سپس این عدد را به‌روز کنید.
      const expectedSchemaVersion = 5;

      final raw = await db.database;
      final actual = await raw.getVersion();
      expect(actual, expectedSchemaVersion,
          reason: 'نسخه Schema تغییر کرده است. اگر این تغییر عمدی است، '
              'STABILITY.md را بخوانید و سپس expectedSchemaVersion را به‌روز کنید. '
              'هر Migration جدید یک ریسک ساختاری است - باگ systemKey دقیقاً از '
              'یک Migration ناقص آمد و هفته‌ها بی‌صدا داده مالی را خراب نشان داد.');
    });
  });
}
