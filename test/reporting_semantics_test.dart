// تست‌های مرحله «Reporting Semantics & Management Analytics». این‌ها به
// sqflite_common_ffi نیاز دارند؛ در محیط توسعه فعلی (بدون Flutter SDK) اجرا
// نشده‌اند - رجوع به گزارش نهایی، بخش Commands Actually Executed.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'package:daftaryar/db/database_helper.dart';
import 'package:daftaryar/models/counterparty.dart';
import 'package:daftaryar/models/journal_entry.dart';
import 'package:daftaryar/models/project.dart';
import 'package:daftaryar/services/financial_metrics_service.dart';
import 'package:daftaryar/services/financial_reporting_service.dart';
import 'package:daftaryar/services/management_dashboard_service.dart';
import 'package:daftaryar/services/operational_performance_service.dart';
import 'package:daftaryar/utils/dashboard_period.dart';
import 'package:daftaryar/models/financial_reports.dart';

void main() {
  final db = DatabaseHelper.instance;
  final metrics = FinancialMetricsService(db);
  final reporting = FinancialReportingService(db: db, metrics: metrics);

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

  // ==================== مورد ۳۳: سناریوی Integration کامل ====================
  group('مورد ۳۳ — سناریوی Integration کامل با اعداد دقیق متن', () {
    test('Project A: تمام لایه‌ها دقیقاً همان اعداد را می‌دهند', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId, agreedAmount: 100000000);
      final cash = (await db.getCashAccounts()).first;

      // Customer pays: 50 before finalization
      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cash.id!, amount: 50000000, date: '1404/01/10');
      // Finalized = 120
      await db.finalizeProject(projectId: projectId, finalAmount: 120000000, date: '1404/02/01');
      // Discount = 10
      await db.recordProjectDiscount(projectId: projectId, amount: 10000000, date: '1404/02/05');
      // Direct Cost = 40
      final directCostAccount = await db.getDirectProjectCostAccount();
      await _postDirectCost(db,
          directCostAccountId: directCostAccount!.id!,
          cashAccountId: cash.id!,
          amount: 40000000,
          projectId: projectId,
          counterpartyId: cpId,
          date: '1404/02/06');
      // Customer pays: 30 after finalization
      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cash.id!, amount: 30000000, date: '1404/02/10');

      // ---- Project Metrics ----
      final pm = await metrics.getProjectMetrics(projectId);
      expect(pm.initialEstimate, 100000000);
      expect(pm.finalAmount, 120000000);
      expect(pm.grossRevenue, 120000000);
      expect(pm.discountAmount, 10000000);
      expect(pm.netRevenue, 110000000, reason: '120 - 10 = 110');
      expect(pm.directProjectCost, 40000000);
      expect(pm.projectContribution, 70000000, reason: '110 - 40 = 70');
      expect(pm.totalReceived, 80000000, reason: '50 + 30 = 80');
      // نکته مهم (رجوع به گزارش نهایی، بخش Remaining Ambiguities): متن اصلی
      // Specification برای این سناریو «Closing AR = 40» را ادعا کرده بود؛
      // اما طبق ردیابی دقیق منطق موجود و تأییدشده سیستم (که در مراحل قبل
      // ساخته و تست شده):
      //   AR پس از Finalization = 120 (Debit) - 50 (انتقال Advance) = 70
      //   AR پس از Discount = 70 - 10 = 60
      //   AR پس از دریافت 30 پس از Finalization = 60 - 30 = 30
      // که دقیقاً با فرمول مستقل Net Revenue - Total Received = 110 - 80 =
      // 30 نیز یکسان است. عدد «۴۰» در متن Specification از نظر ریاضی با
      // بقیه اعداد همان سناریو (Net Revenue=110, Received=80) سازگار نیست؛
      // این تست از عدد صحیح و اثبات‌شده (30) استفاده می‌کند، نه عدد نوشته‌شده
      // در متن (که حدس زده نشد، بلکه به‌صراحت در گزارش نهایی اعلام شده).
      expect(pm.receivableBalance, 30000000, reason: 'Closing AR = NetRevenue(110) - Received(80) = 30');
      expect(pm.advanceBalance, 0);

      // ---- Project Report (لایه Reporting) ----
      final pr = await reporting.getProjectReport(projectId);
      expect(pr.netRevenue, 110000000);
      expect(pr.projectContribution, 70000000);
      expect(pr.receivableBalance, 30000000);

      // ---- Customer Metrics ----
      final cm = await metrics.getCustomerMetrics(cpId);
      expect(cm.netRevenue, 110000000);
      expect(cm.directProjectCost, 40000000, reason: 'تک پروژه Finalized، هم‌جمعیت با Revenue');
      expect(cm.projectContribution, 70000000);

      // ---- Period Report (بازه شامل هر دو ماه) ----
      final period = await reporting.getPeriodReport(fromDate: '1404/01/01', toDate: '1404/02/28');
      expect(period.netRevenue, 110000000, reason: 'درآمد در تاریخ سند Finalization (بهمن/اسفند نه، همون بازه) شناسایی می‌شود');
      expect(period.customerReceipts, 80000000);
      expect(period.directProjectCost, 40000000);

      // ---- Reconciliation ----
      final recon = await metrics.reconcileProject(projectId);
      expect(recon.status, 'OK');
      expect(recon.difference, 0);
    });
  });

  // ==================== مورد ۱۲: باگ Monthly Buckets ====================
  group('مورد ۱۲ — Monthly Buckets باید دقیقاً با بازه Intersection بگیرند', () {
    test('بازه سفارشی ۱۵ مرداد تا ۱۰ شهریور - هیچ روزی خارج از بازه نباید بیاید', () {
      final buckets = DashboardPeriodResolver.monthlyBuckets('1405/05/15', '1405/06/10');
      expect(buckets.length, 2);
      expect(buckets[0].fromDate, '1405/05/15');
      expect(buckets[0].toDate, '1405/05/31');
      expect(buckets[1].fromDate, '1405/06/01');
      expect(buckets[1].toDate, '1405/06/10');
    });

    test('بازه یک‌ماهه کامل - رفتار قبلی بدون تغییر (Regression)', () {
      final buckets = DashboardPeriodResolver.monthlyBuckets('1404/05/01', '1404/05/31');
      expect(buckets.length, 1);
      expect(buckets[0].fromDate, '1404/05/01');
      expect(buckets[0].toDate, '1404/05/31');
    });
  });

  // ==================== مورد ۹/۱۰: Fiscal Year ====================
  group('مورد ۹/۱۰ — Fiscal Year باید واقعاً اثر داشته باشد', () {
    test('با Fiscal Start = 7/1، سال مالی جاری از مهر شروع می‌شود', () {
      // امروز فرضی: ۱ آذر ۱۴۰۴ (داخل سال مالی که از مهر ۱۴۰۴ شروع شده)
      final today = Jalali(1404, 9, 1);
      final range = DashboardPeriodResolver.resolve(
        DashboardPeriodPreset.thisYear,
        today: today,
        fiscalYearStartMonth: 7,
        fiscalYearStartDay: 1,
      );
      expect(range.fromDate, '1404/07/01');
      expect(range.toDate, '1405/06/31');
      expect(range.label, 'سال مالی جاری');
    });

    test('با Fiscal Start = 7/1، سال مالی قبل درست محاسبه شود', () {
      final today = Jalali(1404, 9, 1);
      final range = DashboardPeriodResolver.resolve(
        DashboardPeriodPreset.lastYear,
        today: today,
        fiscalYearStartMonth: 7,
        fiscalYearStartDay: 1,
      );
      expect(range.fromDate, '1403/07/01');
      expect(range.toDate, '1404/06/31');
      expect(range.label, 'سال مالی قبل');
    });

    test('بدون تنظیم سال مالی (پیش‌فرض ۱/۱) - رفتار تقویمی قبلی حفظ شود (Regression)', () {
      final today = Jalali(1404, 5, 1);
      final range = DashboardPeriodResolver.resolve(DashboardPeriodPreset.thisYear, today: today);
      expect(range.fromDate, '1404/01/01');
      expect(range.label, 'امسال');
    });
  });

  // ==================== مورد ۲۴: Growth با previous صفر یا منفی ====================
  group('مورد ۲۴ — Growth Metrics باید برای صفر/منفی امن باشند', () {
    test('previous = 0 باید growthRate=null بدهد (تقسیم بر صفر نامعتبر)،'
        ' اما growthAmount همچنان قابل‌محاسبه بماند (تفاضل مطلق، نه نسبت)', () {
      final c = FinancialPeriodComparison.compute(metricName: 'x', current: 100, previous: 0);
      expect(c.growthRate, isNull, reason: 'درصد رشد از مبنای صفر تعریف‌نشده است (تقسیم بر صفر)');
      expect(c.growthAmount, 100.0,
          reason: 'برخلاف درصد، تفاضل مطلق (current-previous=100-0=100) کاملاً معتبر و معنادار است'
              ' - این یک عدد دیگر است، نه یک نسبت؛ null کردنش اطلاعات واقعی را بدون دلیل پنهان می‌کرد');
    });

    test('رفتن از Contribution منفی به مثبت نباید علامت رشد را معکوس کند', () {
      final c = FinancialPeriodComparison.compute(metricName: 'contribution', current: 10, previous: -10);
      // (10 - (-10)) / abs(-10) * 100 = 20/10*100 = 200% (مثبت، نه -200%)
      expect(c.growthRate, 200.0);
    });
  });

  // ==================== مورد ۲۵: Profitability با Revenue صفر/نامعتبر ====================
  group('مورد ۲۵ — Profitability Thresholds برای Revenue نامعتبر', () {
    test('Revenue=null → Unknown، نه خطا', () {
      expect(ProfitabilityThresholds.classify(null, null), ProjectProfitabilityStatus.unknown);
    });

    test('Contribution=0 و Margin=0 → LowMargin (طبق آستانه فعلی <15٪)، بدون Division by Zero', () {
      expect(ProfitabilityThresholds.classify(0, 0), ProjectProfitabilityStatus.lowMargin);
    });
  });

  // ==================== مورد ۵: ناهماهنگی جمعیت Customer Metrics ====================
  group('مورد ۵ — Customer Metrics باید جمعیت سازگار داشته باشد', () {
    test('پروژه Finalized + پروژه WIP با هزینه: directProjectCost فقط Finalized را می‌شمارد', () async {
      final cpId = await createCounterparty('مشتری با دو پروژه');
      final finalizedProject = await createProject(cpId, agreedAmount: 50000000);
      final wipProject = await createProject(cpId, agreedAmount: 30000000);
      final cash = (await db.getCashAccounts()).first;
      final directCostAccount = await db.getDirectProjectCostAccount();

      await db.finalizeProject(projectId: finalizedProject, finalAmount: 50000000, date: '1404/01/15');
      await _postDirectCost(db,
          directCostAccountId: directCostAccount!.id!,
          cashAccountId: cash.id!,
          amount: 10000000,
          projectId: finalizedProject,
          counterpartyId: cpId,
          date: '1404/01/16');
      // پروژه WIP هم هزینه دارد ولی هنوز Finalize نشده
      await _postDirectCost(db,
          directCostAccountId: directCostAccount.id!,
          cashAccountId: cash.id!,
          amount: 5000000,
          projectId: wipProject,
          counterpartyId: cpId,
          date: '1404/01/20');

      final cm = await metrics.getCustomerMetrics(cpId);
      expect(cm.netRevenue, 50000000);
      expect(cm.directProjectCost, 10000000,
          reason: 'فقط هزینه پروژه Finalized - هم‌جمعیت با Revenue');
      expect(cm.directProjectCostAllProjects, 15000000,
          reason: 'هزینه هر دو پروژه (شامل WIP) - جداگانه و صریح گزارش می‌شود');
      expect(cm.projectContribution, 40000000, reason: '50 - 10 = 40 (نه 50-15=35)');
    });
  });

  // ==================== مورد ۱۷: AR Movement Identity ====================
  group('مورد ۱۷ — AR Movement Identity باید همیشه دقیقاً برقرار باشد', () {
    test('Opening + New - Collections - Adjustments + Other = Closing', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId, agreedAmount: 100000000);
      final cash = (await db.getCashAccounts()).first;

      await db.finalizeProject(projectId: projectId, finalAmount: 100000000, date: '1404/01/10');
      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cash.id!, amount: 30000000, date: '1404/01/15');

      final movement = await reporting.getReceivableMovement(fromDate: '1404/01/01', toDate: '1404/01/31');
      final computedClosing = movement['opening']! +
          movement['newReceivables']! -
          movement['collections']! -
          movement['adjustments']! +
          movement['other']!;
      expect(computedClosing, movement['closing']);
      expect(movement['closing'], 70000000);
    });
  });

  // ==================== مورد ۱۶: Cash Reconciliation ====================
  group('مورد ۱۶ — Cash Reconciliation', () {
    test('سناریوی متوازن → cashReconciles = true', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId, agreedAmount: 50000000);
      final cash = (await db.getCashAccounts()).first;
      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cash.id!, amount: 20000000, date: '1404/01/10');

      final period = await reporting.getPeriodReport(fromDate: '1404/01/01', toDate: '1404/01/31');
      expect(period.cashReconciles, true);
    });
  });

  // ==================== مورد ۲۶: Diagnostics hasIssues ====================
  group('مورد ۲۶ — Diagnostics.hasIssues باید همه دسته‌ها را پوشش دهد', () {
    test('فقط negativeCustomerCreditCount>0 هم باید hasIssues=true بدهد', () {
      const diag = FinancialReportDiagnostics(negativeCustomerCreditCount: 1);
      expect(diag.hasIssues, true);
    });
  });

  // ==================== مورد ۲/۳: نام‌گذاری صریح Collection در Dashboard/OperationalPerformance ====================
  group('مورد ۲/۳ — Dashboard و Operational Performance باید نام‌های صریح Period-based داشته باشند', () {
    test('ManagementDashboardService: periodReceiptToRevenueRatio به‌درستی محاسبه می‌شود', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId, agreedAmount: 100000000);
      final cash = (await db.getCashAccounts()).first;
      await db.finalizeProject(projectId: projectId, finalAmount: 100000000, date: '1404/01/10');
      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cash.id!, amount: 40000000, date: '1404/01/15');

      final dashboardService = ManagementDashboardService(db: db, metrics: metrics, reporting: reporting);
      final data = await dashboardService.buildDashboard(
        preset: DashboardPeriodPreset.custom,
        customFrom: '1404/01/01',
        customTo: '1404/01/31',
        includeComparison: false,
        includeTrend: false,
      );
      expect(data.periodReceiptToRevenueRatio, 40.0, reason: '40 دریافتی / 100 درآمد بازه * 100 = 40٪');
    });

    test('OperationalPerformanceService: periodReceiptToRevenueRatio و periodArCollectionRate در دسترس‌اند', () async {
      final cpId = await createCounterparty('محمد');
      final projectId = await createProject(cpId, agreedAmount: 100000000);
      final cash = (await db.getCashAccounts()).first;
      await db.finalizeProject(projectId: projectId, finalAmount: 100000000, date: '1404/01/10');
      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cash.id!, amount: 40000000, date: '1404/01/15');

      final opService = OperationalPerformanceService(db: db, metrics: metrics, reporting: reporting);
      final range = DashboardPeriodResolver.resolve(DashboardPeriodPreset.custom,
          customFrom: '1404/01/01', customTo: '1404/01/31');
      final data = await opService.buildOperationalPerformance(period: range, includeComparison: false, includeTrend: false);
      expect(data.periodReceiptToRevenueRatio, 40.0);
      expect(data.periodArCollectionRate, 40.0,
          reason: '40 وصولی / (Opening=0 + NewReceivables=100) * 100 = 40٪');
    });
  });
}

/// کمکی برای ساخت یک سند هزینه مستقیم پروژه در تست‌ها (سیستمی، Debit
/// Direct Cost / Credit Cash)
Future<int> _postDirectCost(
  DatabaseHelper db, {
  required int directCostAccountId,
  required int cashAccountId,
  required double amount,
  required int projectId,
  required int counterpartyId,
  required String date,
}) {
  return db.createSystemJournal(JournalEntryModel(
    date: date,
    createdAt: date,
    lines: [
      JournalLineModel(
          accountId: directCostAccountId,
          debit: amount.round(),
          projectId: projectId,
          counterpartyId: counterpartyId),
      JournalLineModel(
          accountId: cashAccountId,
          credit: amount.round(),
          projectId: projectId,
          counterpartyId: counterpartyId),
    ],
  ));
}

