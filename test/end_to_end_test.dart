// تست‌های سرتاسری (End-to-End) چرخه کامل عمر پروژه.
//
// چرا این فایل جداست: بقیه تست‌ها عمدتاً تک‌تابعی‌اند - یک تابع را با
// ورودی مشخص صدا می‌زنند و خروجی‌اش را می‌سنجند. آن‌ها مهم‌اند، ولی یک
// دسته کامل از باگ‌ها را نمی‌گیرند: باگ‌هایی که فقط وقتی چند بخش سالم
// کنار هم قرار می‌گیرند ظاهر می‌شوند.
//
// نمونه واقعی: باگ systemKey. هر تابع به‌تنهایی درست کار می‌کرد؛ فقط
// وقتی داشبورد همه را با هم صدا می‌زد، معلوم می‌شد همه صفر برمی‌گردانند.
// هیچ‌کدام از تست‌های واحد آن را نگرفتند، چون هیچ‌کدام کل زنجیره را طی
// نمی‌کردند.
//
// این تست‌ها چرخه واقعی کار دفتر را دنبال می‌کنند و در هر مرحله *همه*
// اعداد کلیدی را با هم تأیید می‌کنند - سطح پروژه، سطح طرف‌حساب، و سطح
// داشبورد.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daftaryar/db/database_helper.dart';
import 'package:daftaryar/models/account.dart';
import 'package:daftaryar/models/counterparty.dart';
import 'package:daftaryar/models/journal_entry.dart';
import 'package:daftaryar/models/project.dart';
import 'package:daftaryar/models/project_price_event.dart';
import 'package:daftaryar/services/data_health_service.dart';
import 'package:daftaryar/services/management_dashboard_service.dart';
import 'package:daftaryar/utils/dashboard_period.dart';

void main() {
  final db = DatabaseHelper.instance;
  final dashboard = ManagementDashboardService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.wipeAll();
  });

  Future<int> createCounterparty(String name) async {
    return db.insertCounterparty(CounterpartyModel(
      name: name,
      createdAt: '1404/01/01',
      updatedAt: '1404/01/01',
      roles: const ['مشتری'],
    ));
  }

  Future<int> createProject(int cpId, {required double amount, String title = 'پروژه'}) async {
    return db.insertProject(ProjectModel(
      title: title,
      counterpartyId: cpId,
      projectTypes: [kProjectTypes.first],
      status: kProjectStatuses.first,
      startDate: '1404/01/01',
      agreedAmount: amount,
      createdAt: '1404/01/01',
    ));
  }

  group('چرخه کامل عمر یک پروژه - از تعریف تا تسویه', () {
    test('در هر مرحله، اعداد سطح پروژه و سطح دفتر با هم سازگارند', () async {
      final cpId = await createCounterparty('کارفرمای اصلی');
      final projectId = await createProject(cpId, amount: 100000000);
      final cash = (await db.getCashAccounts()).first;

      // ---------- مرحله ۱: پروژه تعریف شده، هیچ پولی رد و بدل نشده ----------
      var summary = await db.projectFinancialSummary(projectId);
      expect(summary['isFinalized'], false);
      expect(summary['netRevenue'], isNull,
          reason: 'پیش از نهایی‌سازی هیچ درآمدی شناسایی نمی‌شود - حتی صفر هم نه، بلکه null');
      expect(summary['totalReceived'], 0);
      expect(summary['receivable'], 0);
      expect(summary['customerAdvance'], 0);
      expect(await db.receivableBalance(cpId), 0);

      // ---------- مرحله ۲: پیش‌دریافت ۳۰ میلیونی ----------
      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cash.id!, amount: 30000000, date: '1404/02/01');

      summary = await db.projectFinancialSummary(projectId);
      expect(summary['totalReceived'], 30000000);
      expect(summary['customerAdvance'], 30000000,
          reason: 'پول پیش از تحویل کار، تعهد است نه درآمد');
      expect(summary['netRevenue'], isNull, reason: 'دریافت پول درآمد نمی‌سازد');
      expect(summary['receivable'], 0, reason: 'هنوز طلبی وجود ندارد چون مبلغی قطعی نشده');

      // ---------- مرحله ۳: افزایش مبلغ حین کار ----------
      await db.addProjectPriceEvent(
        projectId: projectId,
        type: kPriceEventAddition,
        amount: 20000000,
        date: '1404/02/15',
        reason: 'کار اضافه',
      );
      expect(await db.currentExpectedAmount(projectId), 120000000,
          reason: 'برآورد فعلی = ۱۰۰ اولیه + ۲۰ افزایش');

      // ---------- مرحله ۴: نهایی‌سازی (لحظه شناسایی درآمد) ----------
      await db.finalizeProject(
          projectId: projectId, finalAmount: 120000000, date: '1404/03/01');

      summary = await db.projectFinancialSummary(projectId);
      expect(summary['isFinalized'], true);
      expect(summary['netRevenue'], 120000000, reason: 'کل مبلغ توافقی یک‌جا درآمد می‌شود');
      expect(summary['customerAdvance'], 0,
          reason: 'پیش‌دریافت باید به حساب دریافتنی منتقل شده باشد');
      expect(summary['receivable'], 90000000,
          reason: 'طلب = ۱۲۰ درآمد - ۳۰ که قبلاً گرفته شده');
      expect(await db.receivableBalance(cpId), 90000000,
          reason: 'مانده سطح طرف‌حساب باید با سطح پروژه بخواند');

      // ---------- مرحله ۵: تخفیف ۱۰ میلیونی ----------
      await db.recordProjectDiscount(
          projectId: projectId, amount: 10000000, date: '1404/03/05');

      summary = await db.projectFinancialSummary(projectId);
      expect(summary['discount'], 10000000);
      expect(summary['netRevenue'], 110000000, reason: 'درآمد خالص = ۱۲۰ ناخالص - ۱۰ تخفیف');
      expect(summary['receivable'], 80000000, reason: 'طلب هم به همان اندازه کم می‌شود');

      // ---------- مرحله ۶: تسویه کامل ----------
      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cash.id!, amount: 80000000, date: '1404/03/10');

      summary = await db.projectFinancialSummary(projectId);
      expect(summary['totalReceived'], 110000000, reason: '۳۰ + ۸۰');
      expect(summary['receivable'], 0, reason: 'طلب کاملاً تسویه شد');
      expect(summary['isSettled'], true);
      expect(await db.receivableBalance(cpId), 0);

      // ---------- تأیید نهایی: سلامت ساختاری و توازن دفتر ----------
      final health = await DataHealthService(db).run();
      expect(health.isHealthy, true,
          reason: 'پس از یک چرخه کامل، دفتر باید سالم بماند. مشکلات: '
              '${health.issues.map((i) => i.title).join(" | ")}');

      final totals = await db.ledgerTotals();
      expect((totals['debit']! - totals['credit']!).abs() < 1, true,
          reason: 'اصل دوطرفه: بدهکار و بستانکار کل دفتر باید برابر باشند');
    });
  });

  group('سازگاری داشبورد با واقعیت دفتر', () {
    test('اعداد داشبورد دقیقاً همان چیزی است که در سطح پروژه ثبت شده', () async {
      // این تست دقیقاً همان باگی را می‌گیرد که systemKey ایجاد کرده بود:
      // آنجا همه توابع سطح پروژه درست بودند ولی داشبورد صفر نشان می‌داد.
      final cpId = await createCounterparty('مشتری داشبورد');
      final cash = (await db.getCashAccounts()).first;

      // پروژه A: نهایی‌شده با طلب باقی‌مانده
      final projectA = await createProject(cpId, amount: 100000000, title: 'پروژه A');
      await db.finalizeProject(projectId: projectA, finalAmount: 100000000, date: '1404/02/01');
      await db.receiveProjectPayment(
          projectId: projectA, cashAccountId: cash.id!, amount: 60000000, date: '1404/02/10');

      // پروژه B: نهایی‌نشده با پیش‌دریافت
      final projectB = await createProject(cpId, amount: 50000000, title: 'پروژه B');
      await db.receiveProjectPayment(
          projectId: projectB, cashAccountId: cash.id!, amount: 20000000, date: '1404/02/15');

      // مقادیر مرجع از سطح پروژه
      final arA = await db.projectReceivableBalance(projectA);
      final advB = await db.projectAdvanceBalance(projectB);
      expect(arA, 40000000, reason: 'مرجع: ۱۰۰ درآمد - ۶۰ دریافتی');
      expect(advB, 20000000, reason: 'مرجع: پیش‌دریافت پروژه نهایی‌نشده');

      // همان مقادیر باید در داشبورد دیده شوند
      final data = await dashboard.buildDashboard(preset: DashboardPeriodPreset.thisYear);
      expect(data.receivableBalance, arA,
          reason: 'مطالبات داشبورد باید با مجموع مطالبات پروژه‌ها یکی باشد');
      expect(data.advanceBalance, advB,
          reason: 'پیش‌دریافت داشبورد باید با مجموع پیش‌دریافت پروژه‌ها یکی باشد');
      expect(data.closingCash, 80000000, reason: 'موجودی نقد = ۶۰ + ۲۰');
      expect(data.netRevenue.value, 100000000,
          reason: 'فقط پروژه نهایی‌شده درآمد دارد، نه پروژه B');
      expect(data.openProjectsCount, 1, reason: 'فقط پروژه B هنوز باز است');
    });

    test('دریافت نقدی بدون پروژه هم در درآمد داشبورد دیده می‌شود', () async {
      // رگرسیون باگ واقعی: درآمد دفتر فقط از حساب کنترلی «درآمد پروژه‌ها»
      // خوانده می‌شد، پس کارهای کوچک بدون پروژه از گزارش سودآوری غایب
      // بودند در حالی که پولشان در موجودی بود.
      final cpId = await createCounterparty('رضا');
      final cash = (await db.getCashAccounts()).first;
      final incomeAccounts = await db.getAccounts(type: kAccountIncome);
      final nonControlIncome = incomeAccounts.firstWhere((a) => a.systemKey == null);

      await db.createManualJournal(JournalEntryModel(
        date: '1404/02/20',
        description: 'کار کوچک بدون پروژه',
        createdAt: '1404/02/20',
        lines: [
          JournalLineModel(accountId: cash.id!, debit: 10000000, counterpartyId: cpId),
          JournalLineModel(accountId: nonControlIncome.id!, credit: 10000000, counterpartyId: cpId),
        ],
      ));

      final data = await dashboard.buildDashboard(preset: DashboardPeriodPreset.thisYear);
      expect(data.netRevenue.value, 10000000,
          reason: 'درآمد بدون پروژه هم باید در داشبورد دیده شود');
      expect(data.closingCash, 10000000);
    });
  });

  group('سناریوهای مرزی', () {
    test('پروژه بدون هیچ فعالیتی، هیچ عددی را خراب نمی‌کند', () async {
      final cpId = await createCounterparty('مشتری بی‌فعالیت');
      await createProject(cpId, amount: 50000000);

      final data = await dashboard.buildDashboard(preset: DashboardPeriodPreset.thisMonth);
      expect(data.receivableBalance, 0);
      expect(data.advanceBalance, 0);
      expect(data.closingCash, 0);
      expect(data.openProjectsCount, 1);
      expect(data.openProjectsTotal, 50000000,
          reason: 'برآورد پروژه باز باید دیده شود حتی بدون هیچ تراکنشی');

      final health = await DataHealthService(db).run();
      expect(health.isHealthy, true);
    });

    test('دفتر کاملاً خالی باعث خطا یا عدد نامعتبر نمی‌شود', () async {
      final data = await dashboard.buildDashboard(preset: DashboardPeriodPreset.thisMonth);
      expect(data.receivableBalance, 0);
      expect(data.closingCash, 0);
      expect(data.openProjectsCount, 0);
      expect(data.recentEntries, isEmpty);

      final health = await DataHealthService(db).run();
      expect(health.isHealthy, true,
          reason: 'دفتر خالی سالم است - نبود داده با خرابی داده فرق دارد');
    });
  });
}
