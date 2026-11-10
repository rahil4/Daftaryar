// تضمین می‌کند مسیر دسته‌ای محاسبه شاخص‌های پروژه (loadSnapshot - تعداد
// ثابت کوئری) دقیقاً همان اعداد مسیر تک‌پروژه‌ای (یک دسته کوئری به‌ازای هر
// پروژه) را می‌دهد. مسیر دسته‌ای فقط برای سرعت اضافه شده؛ هر اختلاف عددی
// بین این دو یعنی یک گزارش مالی اشتباه.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daftaryar/db/database_helper.dart';
import 'package:daftaryar/models/counterparty.dart';
import 'package:daftaryar/models/financial_metrics.dart';
import 'package:daftaryar/models/journal_entry.dart';
import 'package:daftaryar/models/project.dart';
import 'package:daftaryar/models/project_price_event.dart';
import 'package:daftaryar/services/financial_metrics_service.dart';
import 'package:daftaryar/services/financial_reporting_service.dart';

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

  Future<int> createCounterparty(String name) {
    return db.insertCounterparty(CounterpartyModel(
        name: name, createdAt: '1404/01/01', updatedAt: '1404/01/01', roles: const ['مشتری']));
  }

  Future<int> createProject(int counterpartyId, String title, {double agreedAmount = 10000000}) {
    return db.insertProject(ProjectModel(
      title: title,
      counterpartyId: counterpartyId,
      projectTypes: [kProjectTypes.first],
      status: kProjectStatuses.first,
      startDate: '1404/01/01',
      agreedAmount: agreedAmount,
      createdAt: '1404/01/01',
    ));
  }

  /// دیتاستی که هر حالت مالی پروژه را حداقل یک‌بار دارد.
  Future<List<int>> seedVariedProjects() async {
    final cash = (await db.getCashAccounts()).first;
    final directCost = (await db.getDirectProjectCostAccount())!;
    final revenue = (await db.getProjectRevenueAccount())!;
    final ar = (await db.getReceivableAccount())!;
    final cpA = await createCounterparty('الف');
    final cpB = await createCounterparty('ب');

    Future<void> cost(int projectId, int counterpartyId, int amount) {
      return db.createSystemJournal(JournalEntryModel(
        date: '1404/01/20',
        createdAt: '1404/01/20',
        lines: [
          JournalLineModel(
              accountId: directCost.id!, debit: amount, projectId: projectId, counterpartyId: counterpartyId),
          JournalLineModel(
              accountId: cash.id!, credit: amount, projectId: projectId, counterpartyId: counterpartyId),
        ],
      ));
    }

    // ۱) بدون هیچ فعالیتی
    final untouched = await createProject(cpA, 'بدون فعالیت');

    // ۲) در جریان: پیش‌دریافت + تغییر قیمت پیش از نهایی‌سازی + هزینه
    final open = await createProject(cpA, 'در جریان');
    await db.receiveProjectPayment(
        projectId: open, cashAccountId: cash.id!, amount: 3000000, date: '1404/01/05');
    await db.addProjectPriceEvent(
        projectId: open, type: kPriceEventAddition, amount: 2000000, date: '1404/01/06');
    await db.addProjectPriceEvent(
        projectId: open, type: kPriceEventReduction, amount: -500000, date: '1404/01/07');
    await cost(open, cpA, 1200000);

    // ۳) نهایی‌شده با مانده طلب، تخفیف و اصلاح مبلغ نهایی
    final finalized = await createProject(cpA, 'نهایی با مانده');
    await db.receiveProjectPayment(
        projectId: finalized, cashAccountId: cash.id!, amount: 4000000, date: '1404/01/05');
    await db.finalizeProject(projectId: finalized, finalAmount: 12000000, date: '1404/02/01');
    await db.recordProjectDiscount(projectId: finalized, amount: 500000, date: '1404/02/02');
    await db.recordFinalAdjustment(projectId: finalized, amount: 1500000, date: '1404/02/03');
    await cost(finalized, cpA, 3000000);

    // ۴) نهایی‌شده و کاملاً تسویه
    final settled = await createProject(cpB, 'تسویه‌شده');
    await db.finalizeProject(projectId: settled, finalAmount: 8000000, date: '1404/02/01');
    await db.receiveProjectPayment(
        projectId: settled, cashAccountId: cash.id!, amount: 8000000, date: '1404/02/05');

    // ۵) مازاد دریافتی (بستانکاری مشتری)
    final overpaid = await createProject(cpB, 'مازاد دریافتی');
    await db.receiveProjectPayment(
        projectId: overpaid, cashAccountId: cash.id!, amount: 9000000, date: '1404/01/05');
    await db.finalizeProject(projectId: overpaid, finalAmount: 7000000, date: '1404/02/01');

    // ۶) زیان‌ده: هزینه مستقیم بیشتر از درآمد
    final loss = await createProject(cpB, 'زیان‌ده');
    await db.finalizeProject(projectId: loss, finalAmount: 2000000, date: '1404/02/01');
    await cost(loss, cpB, 5000000);

    // ۷) ناسازگاری درآمد با دفتر: سند دستی مستقیم روی حساب درآمد پروژه
    final mismatch = await createProject(cpA, 'ناسازگار');
    await db.finalizeProject(projectId: mismatch, finalAmount: 6000000, date: '1404/02/01');
    await db.createManualJournal(JournalEntryModel(
      date: '1404/02/10',
      createdAt: '1404/02/10',
      lines: [
        JournalLineModel(accountId: ar.id!, debit: 700000, projectId: mismatch, counterpartyId: cpA),
        JournalLineModel(accountId: revenue.id!, credit: 700000, projectId: mismatch, counterpartyId: cpA),
      ],
    ));

    return [untouched, open, finalized, settled, overpaid, loss, mismatch];
  }

  void expectSameMetrics(ProjectFinancialMetrics batch, ProjectFinancialMetrics single) {
    final reason = 'پروژه ${single.projectId}';
    expect(batch.projectId, single.projectId, reason: reason);
    expect(batch.initialEstimate, single.initialEstimate, reason: reason);
    expect(batch.priceAdditions, single.priceAdditions, reason: reason);
    expect(batch.priceReductions, single.priceReductions, reason: reason);
    expect(batch.netPriceChanges, single.netPriceChanges, reason: reason);
    expect(batch.finalAmount, single.finalAmount, reason: reason);
    expect(batch.finalAdjustments, single.finalAdjustments, reason: reason);
    expect(batch.effectiveFinalAmount, single.effectiveFinalAmount, reason: reason);
    expect(batch.grossRevenue, single.grossRevenue, reason: reason);
    expect(batch.discountAmount, single.discountAmount, reason: reason);
    expect(batch.netRevenue, single.netRevenue, reason: reason);
    expect(batch.totalReceived, single.totalReceived, reason: reason);
    expect(batch.advanceBalance, single.advanceBalance, reason: reason);
    expect(batch.receivableBalance, single.receivableBalance, reason: reason);
    expect(batch.customerCredit, single.customerCredit, reason: reason);
    expect(batch.directProjectCost, single.directProjectCost, reason: reason);
    expect(batch.projectContribution, single.projectContribution, reason: reason);
    expect(batch.contributionMargin, single.contributionMargin, reason: reason);
    expect(batch.collectionRate, single.collectionRate, reason: reason);
    expect(batch.outstandingRatio, single.outstandingRatio, reason: reason);
    expect(batch.priceIncreaseAmount, single.priceIncreaseAmount, reason: reason);
    expect(batch.priceIncreaseRate, single.priceIncreaseRate, reason: reason);
    expect(batch.isFinalized, single.isFinalized, reason: reason);
    expect(batch.isSettled, single.isSettled, reason: reason);
    expect(batch.status, single.status, reason: reason);
    expect(batch.finalizedDate, single.finalizedDate, reason: reason);
  }

  test('شاخص‌های دسته‌ای هر پروژه دقیقاً با مسیر تک‌پروژه‌ای برابر است', () async {
    final ids = await seedVariedProjects();
    final snapshot = await metrics.loadSnapshot();

    expect(snapshot.projects.map((p) => p.id).toSet(), ids.toSet());
    for (final id in ids) {
      expectSameMetrics(snapshot.metricsById[id]!, await metrics.getProjectMetrics(id));
    }

    // دیتاست باید واقعاً حالت‌های غیرصفر را پوشش دهد، وگرنه برابریِ «صفر با
    // صفر» چیزی را ثابت نمی‌کند.
    final all = snapshot.metricsById.values;
    expect(all.where((m) => (m.customerCredit ?? 0) > 0), isNotEmpty);
    expect(all.where((m) => m.advanceBalance > 0), isNotEmpty);
    expect(all.where((m) => m.receivableBalance > 0), isNotEmpty);
    expect(all.where((m) => m.discountAmount > 0 && m.finalAdjustments != 0), isNotEmpty);
    expect(all.where((m) => m.priceAdditions > 0 && m.priceReductions > 0), isNotEmpty);
    expect(all.where((m) => (m.projectContribution ?? 0) < 0), isNotEmpty);
  });

  test('مانده‌های پایه دسته‌ای با توابع تک‌پروژه‌ای DatabaseHelper برابر است', () async {
    final ids = await seedVariedProjects();
    final aggregates = await db.projectLedgerAggregates();

    for (final id in ids) {
      final reason = 'پروژه $id';
      expect(aggregates.received[id] ?? 0, (await db.projectFinancials(id))['received'], reason: reason);
      expect(aggregates.receivable[id] ?? 0, await db.projectReceivableBalance(id), reason: reason);
      expect(aggregates.advance[id] ?? 0, await db.projectAdvanceBalance(id), reason: reason);
      expect(aggregates.customerCredit[id] ?? 0, await db.projectCustomerCreditBalance(id),
          reason: reason);
      expect(aggregates.revenueLedger[id] ?? 0, await db.projectRevenueLedgerBalance(id), reason: reason);
      expect(aggregates.directCost[id] ?? 0, await db.projectDirectCost(id), reason: reason);
    }
  });

  test('وضعیت تسویه دسته‌ای با DatabaseHelper.isProjectSettled برابر است', () async {
    final ids = await seedVariedProjects();
    final snapshot = await metrics.loadSnapshot();

    for (final id in ids) {
      expect(snapshot.metricsById[id]!.isSettled, await db.isProjectSettled(id), reason: 'پروژه $id');
    }
    // حداقل یک پروژه تسویه‌شده و یک تسویه‌نشده در دیتاست هست، وگرنه این
    // تست چیزی را ثابت نمی‌کند.
    expect(snapshot.metricsById.values.where((m) => m.isSettled), isNotEmpty);
    expect(snapshot.metricsById.values.where((m) => m.isFinalized && !m.isSettled), isNotEmpty);
  });

  test('تشخیص ناسازگاری درآمد دسته‌ای با reconcileProject تک‌پروژه‌ای برابر است', () async {
    final ids = await seedVariedProjects();
    final diagnostics = await reporting.getDiagnostics();

    final expectedMismatch = <int>{};
    for (final id in ids) {
      if ((await metrics.reconcileProject(id)).status == 'MISMATCH') expectedMismatch.add(id);
    }
    expect(expectedMismatch, hasLength(1), reason: 'دیتاست دقیقاً یک پروژه ناسازگار دارد');
    expect(diagnostics.revenueLedgerMismatchProjectIds.toSet(), expectedMismatch);
    expect(diagnostics.revenueLedgerMismatchCount, 1);
  });

  test('شاخص‌های مشتری با و بدون نتیجه دسته‌ای برابر است', () async {
    await seedVariedProjects();
    final snapshot = await metrics.loadSnapshot();
    final counterpartyIds = snapshot.projects.map((p) => p.counterpartyId).toSet();
    expect(counterpartyIds, hasLength(2));

    for (final cid in counterpartyIds) {
      final withSnapshot = await metrics.getCustomerMetrics(cid, snapshot: snapshot);
      final without = await metrics.getCustomerMetrics(cid);
      final reason = 'طرف‌حساب $cid';
      expect(withSnapshot.projectCount, without.projectCount, reason: reason);
      expect(withSnapshot.grossRevenue, without.grossRevenue, reason: reason);
      expect(withSnapshot.discountAmount, without.discountAmount, reason: reason);
      expect(withSnapshot.netRevenue, without.netRevenue, reason: reason);
      expect(withSnapshot.totalReceived, without.totalReceived, reason: reason);
      expect(withSnapshot.receivableBalance, without.receivableBalance, reason: reason);
      expect(withSnapshot.customerCredit, without.customerCredit, reason: reason);
      expect(withSnapshot.directProjectCost, without.directProjectCost, reason: reason);
      expect(withSnapshot.directProjectCostAllProjects, without.directProjectCostAllProjects,
          reason: reason);
      expect(withSnapshot.projectContribution, without.projectContribution, reason: reason);
      expect(withSnapshot.contributionMargin, without.contributionMargin, reason: reason);
    }
  });
}
