// تست چرخه کامل پشتیبان‌گیری - در فایل مستقل خودش.
//
// چرا جدا: این تست در فایل backup_restore_test.dart بارها شکست می‌خورد،
// در حالی که دقیقاً همان سناریو در end_to_end_test.dart پاس می‌شد. علت،
// وضعیت باقی‌مانده از تست‌های پیشین همان فایل بود - به‌ویژه تستی که
// importBackupFile با replaceExisting: true اجرا می‌کند و کل جدول
// حساب‌ها را حذف و بازسازی می‌کند. حتی wipeAll صریح در ابتدای تست هم
// کافی نبود.
//
// درس عمومی: تستی که به وضعیت پاک دیتابیس وابسته است، نباید در فایلی
// باشد که تست‌های دیگرش ساختار دیتابیس را تغییر می‌دهند.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daftaryar/db/database_helper.dart';
import 'package:daftaryar/models/counterparty.dart';
import 'package:daftaryar/models/project.dart';
import 'package:daftaryar/services/backup_service.dart';
import 'package:daftaryar/services/data_health_service.dart';
import 'package:daftaryar/utils/formatters.dart';

void main() {
  final db = DatabaseHelper.instance;
  final backup = BackupService();
  final today = todayJalaliString();

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
      createdAt: today,
      updatedAt: today,
      roles: const ['مشتری'],
    ));
  }

  Future<int> createProject(int counterpartyId, {double agreedAmount = 50000000}) async {
    return db.insertProject(ProjectModel(
      title: 'پروژه تست چرخه پشتیبان',
      counterpartyId: counterpartyId,
      projectTypes: [kProjectTypes.first],
      status: kProjectStatuses.first,
      startDate: today,
      agreedAmount: agreedAmount,
      createdAt: today,
    ));
  }

  group('چرخه کامل پشتیبان‌گیری — اثر انگشت داده پیش و پس از بازیابی', () {
    test('پس از Restore کامل، اثر انگشت داده دقیقاً با پیش از آن یکسان است', () async {
      // این تست همان کاری را می‌کند که کاربر باید دستی انجام دهد: داده
      // واقعی بساز، اثر انگشت بگیر، پشتیبان بگیر، همه‌چیز را پاک کن،
      // بازیابی کن، و اثر انگشت را دوباره مقایسه کن. برخلاف تست‌های
      // موجود که فقط چند فیلد را چک می‌کردند، این تست کل محتوای مالی را
      // با هم می‌سنجد - شامل جمع مبالغ، نه فقط تعداد رکوردها.
      // پاک‌سازی صریح در خودِ تست: تست پیش از این
      // (importBackupFile با replaceExisting: true) حساب‌ها را حذف و
      // بازسازی می‌کند. اتکا به setUp کافی نیست چون هر مرجعی که پیش از
      // آن گرفته شده باشد به شناسه‌های قدیمی اشاره می‌کند.
      await db.wipeAll();

      final cpId = await createCounterparty('مشتری چرخه کامل');
      final projectA = await createProject(cpId, agreedAmount: 100000000);
      final projectB = await createProject(cpId, agreedAmount: 50000000);
      final cash = (await db.getCashAccounts()).first;

      // پروژه A: نهایی‌شده + دریافت جزئی
      await db.finalizeProject(projectId: projectA, finalAmount: 100000000, date: today);

      // تأیید میانی: نهایی‌سازی واقعاً طلب ساخته باشد. بدون این بررسی، اگر
      // مرحله بعد شکست بخورد معلوم نیست تقصیر نهایی‌سازی بوده یا دریافت.
      final arAfterFinalize = await db.projectReceivableBalance(projectA);
      expect(arAfterFinalize, 100000000,
          reason: 'نهایی‌سازی باید طلب ۱۰۰ میلیونی بسازد؛ اگر صفر است یعنی سند'
              ' نهایی‌سازی ثبت نشده یا به پروژه دیگری خورده است');

      // تأیید سطح طرف‌حساب: کنترل Overpayment دقیقاً این مانده را می‌سنجد،
      // نه مانده سطح پروژه. اگر این صفر باشد ولی بالایی درست، یعنی سند به
      // counterpartyId دیگری تگ شده است.
      final cpArAfterFinalize = await db.receivableBalance(cpId);
      expect(cpArAfterFinalize, 100000000,
          reason: 'مانده طلب سطح طرف‌حساب باید با سطح پروژه یکی باشد - کنترل'
              ' Overpayment روی همین عدد تصمیم می‌گیرد');

      await db.receiveProjectPayment(
          projectId: projectA, cashAccountId: cash.id!, amount: 40000000, date: today);
      // پروژه B: نهایی‌نشده + پیش‌دریافت
      await db.receiveProjectPayment(
          projectId: projectB, cashAccountId: cash.id!, amount: 15000000, date: today);

      final before = await db.dataFingerprint();
      expect(before['اسناد']! > 0, true, reason: 'باید داده واقعی ساخته شده باشد');

      final exported = await backup.collectBackupData();
      final tempFile = File('${Directory.systemTemp.path}/full_cycle_fingerprint.json');
      await tempFile.writeAsString(jsonEncode(exported));

      // بازیابی کامل (replaceExisting) - معادل نصب دوباره برنامه
      await backup.importBackupFile(tempFile, replaceExisting: true);

      final after = await db.dataFingerprint();
      expect(after, before,
          reason: 'اثر انگشت داده پس از بازیابی باید دقیقاً یکسان باشد.\n'
              'پیش: $before\nپس: $after');

      await tempFile.delete();
    });

    test('پس از بازیابی، بررسی سلامت ساختاری هم باید پاک باشد', () async {
      final cpId = await createCounterparty('مشتری سلامت پس از بازیابی');
      final projectId = await createProject(cpId, agreedAmount: 30000000);
      await db.finalizeProject(projectId: projectId, finalAmount: 30000000, date: today);

      final exported = await backup.collectBackupData();
      final tempFile = File('${Directory.systemTemp.path}/health_after_restore.json');
      await tempFile.writeAsString(jsonEncode(exported));
      await backup.importBackupFile(tempFile, replaceExisting: true);

      final health = await DataHealthService(db).run();
      expect(health.isHealthy, true,
          reason: 'بازیابی نباید یکپارچگی ساختاری را بشکند. مشکلات: '
              '${health.issues.map((i) => i.title).join(" | ")}');

      await tempFile.delete();
    });
  });
}
