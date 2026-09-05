// تست‌های مرحله «Hardening اولویت ۱» — Backup/Restore Atomicity، System
// Account Mapping، و Security Filtering. این‌ها به sqflite_common_ffi نیاز
// دارند؛ اگر Flutter/Dart SDK در محیط اجرا موجود نباشد، اجرا نمی‌شوند - رجوع
// به گزارش نهایی این مرحله برای وضعیت واقعی اجرا.
//
// اصلاحیه (Adversarial Review Fix): دو تست قبلی («Atomic Rollback» و
// «Backup Security - فیلتر Export») به‌دلیل عدم اجرای مسیر Production واقعی
// جایگزین شدند - رجوع به کامنت هرکدام برای توضیح دقیق.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daftaryar/db/database_helper.dart';
import 'package:daftaryar/services/data_health_service.dart';
import 'package:daftaryar/models/account.dart';
import 'package:daftaryar/models/counterparty.dart';
import 'package:daftaryar/models/project.dart';
import 'package:daftaryar/services/backup_service.dart';

void main() {
  final db = DatabaseHelper.instance;
  final backup = BackupService();

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

  Future<int> createProject(int counterpartyId, {double agreedAmount = 50000000}) async {
    return db.insertProject(ProjectModel(
      title: 'پروژه تست بازیابی',
      counterpartyId: counterpartyId,
      projectTypes: [kProjectTypes.first],
      status: kProjectStatuses.first,
      startDate: '1404/01/01',
      agreedAmount: agreedAmount,
      createdAt: '1404/01/01',
    ));
  }

  /// عکس کامل و قابل‌مقایسه از کل وضعیت دیتابیس - نه فقط تعداد رکوردها.
  /// از همان متدهای عمومی موجود DatabaseHelper استفاده می‌کند (بدون افزودن
  /// هیچ API جدیدی به DatabaseHelper Production، طبق محدودیت صریح این
  /// مرحله)؛ خروجی یک ساختار کاملاً JSON-سریالایزبل و قطعی (Deterministic)
  /// است که با jsonEncode مستقیماً قابل مقایسه دقیق است.
  Future<Map<String, dynamic>> fullSnapshot() async {
    final counterparties = await db.getCounterparties(includeInactive: true);
    final projects = await db.getProjects();
    final accounts = await db.getAccounts();
    final entries = await db.getJournalEntries();
    final settings = await db.getAllSettings();
    final priceEvents = <Map<String, dynamic>>[];
    for (final p in projects) {
      priceEvents.addAll((await db.getProjectPriceEvents(p.id!)).map((e) => e.toMap()));
    }
    return {
      'counterparties': counterparties.map((e) => {...e.toMap(), 'roles': e.roles}).toList(),
      'projects': projects.map((e) => e.toMap()).toList(),
      'accounts': accounts.map((e) => e.toMap()).toList(),
      'journalEntries': entries
          .map((e) => {...e.toMap(), 'lines': e.lines.map((l) => l.toMap()).toList()})
          .toList(),
      'projectPriceEvents': priceEvents,
      'settings': settings,
    };
  }

  Map<String, dynamic> buildValidBackupJson({
    required List<Map<String, dynamic>> counterparties,
    required List<Map<String, dynamic>> projects,
    required List<Map<String, dynamic>> accounts,
    required List<Map<String, dynamic>> journalEntries,
    Map<String, String>? settings,
    int version = kBackupFormatVersion,
  }) {
    return {
      'version': version,
      'exportedAt': DateTime.now().toIso8601String(),
      'counterparties': counterparties,
      'projects': projects,
      'projectPriceEvents': <Map<String, dynamic>>[],
      'accounts': accounts,
      'journalEntries': journalEntries,
      'settings': settings ?? <String, String>{},
    };
  }

  group('مورد ۱ — Atomic Restore: شکست واقعی وسط Transaction (اصلاح Adversarial Review)', () {
    test(
        'Validation اولیه PASS می‌شود، چند سند معتبر Insert می‌شوند، سپس نقض واقعی'
        ' Foreign Key رخ می‌دهد و SQLite کل Transaction را Rollback می‌کند', () async {
      // ---------- وضعیت اولیه (باید دقیقاً پس از شکست حفظ شود) ----------
      final oldCpId = await createCounterparty('مشتری قدیمی پیش از Restore');
      await createProject(oldCpId, agreedAmount: 30000000);
      await db.setSetting('fy_start_month', '7');
      final beforeSnapshot = await fullSnapshot();

      // ---------- ساخت Backup ----------
      // نکته حیاتی طراحی این تست: _validateBackupStructure فقط توازن
      // debit/credit و type بودن accountId را بررسی می‌کند - هرگز وجود
      // واقعی projectId/counterpartyId را در بخش‌های دیگر همان فایل چک
      // نمی‌کند (تأیید شد با بازخوانی مستقیم سورس پیش از نوشتن این تست).
      // بنابراین یک سند با projectId=999999 (که هیچ پروژه‌ای با این شناسه
      // در data['projects'] وجود ندارد) از این Validation اولیه بدون خطا
      // عبور می‌کند، وارد Transaction می‌شود، و دقیقاً هنگام INSERT در
      // journal_lines به FOREIGN KEY (projectId) REFERENCES projects(id)
      // برخورد می‌کند - یک شکست واقعی و غیرشبیه‌سازی‌شده در دیتابیس واقعی.
      const backupCounterpartyId = 501;
      const backupProjectId = 601;
      const cashBackupAccountId = 10;
      const directCostBackupAccountId = 20;
      const nonExistentProjectId = 999999;

      final backupJson = buildValidBackupJson(
        counterparties: [
          {
            'id': backupCounterpartyId,
            'name': 'مشتری جدید از Backup',
            'phone': null,
            'address': null,
            'nationalId': null,
            'notes': null,
            'isActive': 1,
            'createdAt': '1404/01/01',
            'updatedAt': '1404/01/01',
            'roles': <String>[],
          },
        ],
        projects: [
          {
            'id': backupProjectId,
            'title': 'پروژه جدید از Backup',
            'counterpartyId': backupCounterpartyId,
            'projectType': kProjectTypes.first,
            'status': kProjectStatuses.first,
            'startDate': '1404/01/05',
            'agreedAmount': 40000000,
            'description': null,
            'createdAt': '1404/01/05',
            'finalAmount': null,
            'finalizedDate': null,
            'finalizedNote': null,
          },
        ],
        accounts: [
          {
            'id': cashBackupAccountId,
            'code': null,
            'name': 'صندوق (از Backup)',
            'type': kAccountAsset,
            'parentId': null,
            'isSystem': 1,
            'systemKey': kSystemKeyCash,
            'createdAt': '1404/01/01',
          },
          {
            'id': directCostBackupAccountId,
            'code': null,
            'name': 'هزینه مستقیم پروژه (از Backup)',
            'type': kAccountExpense,
            'parentId': null,
            'isSystem': 1,
            'systemKey': kSystemKeyDirectProjectCost,
            'createdAt': '1404/01/01',
          },
        ],
        journalEntries: [
          // سند معتبر شماره ۱ - باید با موفقیت داخل Transaction نوشته شود
          {
            'date': '1404/01/06',
            'createdAt': '1404/01/06',
            'lines': [
              {
                'accountId': directCostBackupAccountId,
                'debit': 10000000,
                'credit': 0,
                'projectId': backupProjectId,
                'counterpartyId': backupCounterpartyId,
              },
              {
                'accountId': cashBackupAccountId,
                'debit': 0,
                'credit': 10000000,
                'projectId': backupProjectId,
                'counterpartyId': backupCounterpartyId,
              },
            ],
          },
          // سند معتبر شماره ۲ - این هم باید با موفقیت نوشته شود، تا اثبات
          // شود شکست بعد از حداقل چند Write موفق رخ داده، نه در همان ابتدا
          {
            'date': '1404/01/07',
            'createdAt': '1404/01/07',
            'lines': [
              {
                'accountId': directCostBackupAccountId,
                'debit': 5000000,
                'credit': 0,
                'projectId': backupProjectId,
                'counterpartyId': backupCounterpartyId,
              },
              {
                'accountId': cashBackupAccountId,
                'debit': 0,
                'credit': 5000000,
                'projectId': backupProjectId,
                'counterpartyId': backupCounterpartyId,
              },
            ],
          },
          // سند خرابکار - projectId ارجاعی به پروژه‌ای که اصلاً وجود ندارد
          {
            'date': '1404/01/08',
            'createdAt': '1404/01/08',
            'lines': [
              {
                'accountId': directCostBackupAccountId,
                'debit': 1000000,
                'credit': 0,
                'projectId': nonExistentProjectId,
                'counterpartyId': backupCounterpartyId,
              },
              {
                'accountId': cashBackupAccountId,
                'debit': 0,
                'credit': 1000000,
                'projectId': nonExistentProjectId,
                'counterpartyId': backupCounterpartyId,
              },
            ],
          },
        ],
      );

      final tempFile = File('${Directory.systemTemp.path}/atomic_rollback_fk_test.json');
      await tempFile.writeAsString(jsonEncode(backupJson));

      Object? caughtError;
      try {
        await backup.importBackupFile(tempFile, replaceExisting: true);
      } catch (e) {
        caughtError = e;
      }

      // اثبات این‌که Validation اولیه PASS شده (وگرنه خطا از نوع
      // BackupValidationException می‌بود که پیش از هرگونه نوشتن پرتاب
      // می‌شود) - خطای واقعی باید از جنس دیگری (خطای دیتابیس ناشی از نقض
      // Foreign Key) باشد که فقط داخل Transaction ممکن است رخ دهد.
      expect(caughtError, isNotNull, reason: 'باید یک خطای واقعی رخ داده باشد');
      expect(caughtError, isNot(isA<BackupValidationException>()),
          reason: 'اگر این خطا از نوع BackupValidationException بود، یعنی Validation'
              ' اولیه (نه Transaction) آن را گرفته و این تست چیزی درباره Rollback واقعی'
              ' ثابت نمی‌کرد. خطای واقعی باید از دیتابیس (نقض Foreign Key) باشد.');

      // اثبات این‌که Rollback واقعی SQLite کل تراکنش را برگردانده - نه فقط
      // شمارش رکورد، بلکه محتوای کامل و دقیق تمام جداول کلیدی.
      final afterSnapshot = await fullSnapshot();
      expect(jsonEncode(afterSnapshot), jsonEncode(beforeSnapshot),
          reason: 'دیتابیس باید دقیقاً (byte-for-byte از نظر محتوای منطقی) به وضعیت'
              ' پیش از Restore بازگردد - نه دو سند معتبر اول نصفه باقی مانده باشند و نه'
              ' دیتابیس خالی مانده باشد.');

      await tempFile.delete();
    });
  });

  group('مورد ۲ — System Account Mapping با systemKey', () {
    test('حتی اگر نام حساب سیستمی مقصد تغییر کرده باشد، از طریق systemKey Map می‌شود'
        ' (Test B) و حساب سیستمی تکراری ساخته نمی‌شود', () async {
      final arAccount = await db.getReceivableAccount();
      await db.updateAccount(arAccount!.copyWith(name: 'بدهی مشتریان (نام تغییریافته)'));
      final accountsBefore = await db.getAccounts();
      final systemAccountCountBefore = accountsBefore.where((a) => a.isSystem).length;

      final backupJson = buildValidBackupJson(
        counterparties: const [],
        projects: const [],
        accounts: [
          {
            'id': 501,
            'code': '1100',
            'name': 'حساب‌های دریافتنی',
            'type': kAccountAsset,
            'parentId': null,
            'isSystem': 1,
            'systemKey': kSystemKeyReceivable,
            'createdAt': '1404/01/01',
          },
        ],
        journalEntries: const [],
      );

      final tempFile = File('${Directory.systemTemp.path}/system_account_mapping_test.json');
      await tempFile.writeAsString(jsonEncode(backupJson));

      await backup.importBackupFile(tempFile, replaceExisting: false);

      final accountsAfter = await db.getAccounts();
      final systemAccountCountAfter = accountsAfter.where((a) => a.isSystem).length;

      expect(systemAccountCountAfter, systemAccountCountBefore,
          reason: 'هیچ حساب سیستمی تکراری نباید ساخته شده باشد');
      final stillMapped = await db.getReceivableAccount();
      expect(stillMapped!.name, 'بدهی مشتریان (نام تغییریافته)',
          reason: 'نام واقعی حساب موجود نباید توسط Restore بازنویسی شود');

      await tempFile.delete();
    });
  });

  group('مورد ۳ — Legacy Backup (fallback نام+نوع)', () {
    test('فایل پشتیبان بدون systemKey همچنان با fallback نام+نوع کار می‌کند', () async {
      final accountsBefore = await db.getAccounts();
      final systemCountBefore = accountsBefore.where((a) => a.isSystem).length;

      final legacyBackup = buildValidBackupJson(
        counterparties: const [],
        projects: const [],
        accounts: [
          {
            'id': 601,
            'code': '1100',
            'name': 'حساب‌های دریافتنی',
            'type': kAccountAsset,
            'parentId': null,
            'isSystem': 1,
            'systemKey': null,
            'createdAt': '1404/01/01',
          },
        ],
        journalEntries: const [],
      );

      final tempFile = File('${Directory.systemTemp.path}/legacy_backup_test.json');
      await tempFile.writeAsString(jsonEncode(legacyBackup));

      await backup.importBackupFile(tempFile, replaceExisting: false);

      final accountsAfter = await db.getAccounts();
      final systemCountAfter = accountsAfter.where((a) => a.isSystem).length;
      expect(systemCountAfter, systemCountBefore,
          reason: 'fallback نام+نوع باید حساب موجود را پیدا کند، نه حساب جدید بسازد');

      await tempFile.delete();
    });
  });

  group('مورد ۴ — Backup Security', () {
    test(
        'collectBackupData (منطق واقعی پشت exportToFile) هرگز pin_hash/lock_enabled/'
        'biometric_enabled را در مسیر Database→JSON→File→Read→Decode صادر نمی‌کند'
        ' (اصلاح Adversarial Review - قبلاً فرمول فیلتر در خودِ تست بازنویسی می‌شد)',
        () async {
      await db.setSetting('pin_hash', 'some_hash_value');
      await db.setSetting('lock_enabled', '1');
      await db.setSetting('biometric_enabled', '1');
      await db.setSetting('fy_start_month', '7');

      // اجرای مستقیم متد Production واقعی (نه بازسازی فرمول فیلتر در تست).
      // exportToFile خودش این متد را صدا می‌زند و فقط یک لایه نازک نوشتن
      // فایل/اشتراک‌گذاری (path_provider/share_plus) روی نتیجه همین متد
      // اضافه می‌کند؛ اگر فردا کسی به‌اشتباه در collectBackupData بنویسد
      // 'settings': allSettings (به‌جای settings فیلترشده)، این تست دقیقاً
      // همان‌جا شکست می‌خورد.
      final data = await backup.collectBackupData();

      // چرخه کامل واقعی: encode → file → read → decode → assert
      final tempFile = File('${Directory.systemTemp.path}/export_security_real_test.json');
      await tempFile.writeAsString(jsonEncode(data));
      final rawContent = await tempFile.readAsString();
      final decoded = jsonDecode(rawContent) as Map<String, dynamic>;
      final settings = Map<String, dynamic>.from(decoded['settings'] as Map);

      expect(settings.containsKey('pin_hash'), false,
          reason: 'فایل پشتیبان واقعی (پس از encode/decode کامل) نباید pin_hash داشته باشد');
      expect(settings.containsKey('lock_enabled'), false);
      expect(settings.containsKey('biometric_enabled'), false);
      expect(settings.containsKey('fy_start_month'), true,
          reason: 'تنظیمات غیرامنیتی باید همچنان صادر شوند');

      await tempFile.delete();
    });

    test('Restore بدون security setting در فایل، قفل امنیتی فعلی مقصد را حفظ می‌کند', () async {
      await db.setSetting('pin_hash', 'existing_device_pin_hash');
      await db.setSetting('lock_enabled', '1');

      final backupJson = buildValidBackupJson(
        counterparties: const [],
        projects: const [],
        accounts: const [],
        journalEntries: const [],
        settings: {'fy_start_month': '7'},
      );
      final tempFile = File('${Directory.systemTemp.path}/security_restore_test.json');
      await tempFile.writeAsString(jsonEncode(backupJson));

      await backup.importBackupFile(tempFile, replaceExisting: false);

      final pinAfter = await db.getSetting('pin_hash');
      final lockAfter = await db.getSetting('lock_enabled');
      expect(pinAfter, 'existing_device_pin_hash', reason: 'PIN فعلی نباید پاک/تغییر شود');
      expect(lockAfter, '1', reason: 'قفل فعال باید فعال بماند');

      await tempFile.delete();
    });

    test('حتی اگر فایل (دستکاری‌شده) pin_hash داشته باشد، فیلتر دفاعی سمت Restore'
        ' واقعی (importBackupFile) آن را نادیده می‌گیرد', () async {
      await db.setSetting('pin_hash', 'legit_device_hash');

      final maliciousBackup = buildValidBackupJson(
        counterparties: const [],
        projects: const [],
        accounts: const [],
        journalEntries: const [],
        settings: {'pin_hash': 'attacker_injected_hash'},
      );
      final tempFile = File('${Directory.systemTemp.path}/malicious_backup_test.json');
      await tempFile.writeAsString(jsonEncode(maliciousBackup));

      await backup.importBackupFile(tempFile, replaceExisting: false);

      final pinAfter = await db.getSetting('pin_hash');
      expect(pinAfter, 'legit_device_hash', reason: 'فیلتر دفاعی باید مانع بازنویسی PIN شود');

      await tempFile.delete();
    });
  });

  group('مورد ۵ — Invalid Backup', () {
    test('نسخه ناسازگار رد می‌شود و هیچ تغییری اعمال نمی‌شود', () async {
      final beforeCount = (await db.getCounterparties(includeInactive: true)).length;
      final invalidVersionBackup = buildValidBackupJson(
        counterparties: [
          {
            'id': 1,
            'name': 'نباید وارد شود',
            'isActive': 1,
            'createdAt': '1404/01/01',
            'updatedAt': '1404/01/01',
            'roles': [],
          }
        ],
        projects: const [],
        accounts: const [],
        journalEntries: const [],
        version: 3,
      );
      final tempFile = File('${Directory.systemTemp.path}/invalid_version_test.json');
      await tempFile.writeAsString(jsonEncode(invalidVersionBackup));

      expect(
        () => backup.importBackupFile(tempFile, replaceExisting: true),
        throwsA(isA<BackupValidationException>()),
      );
      final afterCount = (await db.getCounterparties(includeInactive: true)).length;
      expect(afterCount, beforeCount, reason: 'نسخه نامعتبر نباید هیچ داده‌ای وارد کند');

      await tempFile.delete();
    });

    test('JSON غیرقابل‌پارس رد می‌شود', () async {
      final tempFile = File('${Directory.systemTemp.path}/broken_json_test.json');
      await tempFile.writeAsString('{ این یک جیسون معتبر نیست ][');

      expect(
        () => backup.importBackupFile(tempFile, replaceExisting: true),
        throwsA(isA<BackupValidationException>()),
      );

      await tempFile.delete();
    });

    test('عدم توازن سند حسابداری (توسط Validation اولیه، پیش از هر Transaction)،'
        ' کل Restore را رد می‌کند', () async {
      final beforeCount = (await db.getJournalEntries()).length;
      final unbalancedBackup = buildValidBackupJson(
        counterparties: const [],
        projects: const [],
        accounts: const [],
        journalEntries: [
          {
            'date': '1404/01/01',
            'createdAt': '1404/01/01',
            'lines': [
              {'accountId': 1, 'debit': 100, 'credit': 0},
              {'accountId': 2, 'debit': 0, 'credit': 50},
            ],
          },
        ],
      );
      final tempFile = File('${Directory.systemTemp.path}/unbalanced_entry_test.json');
      await tempFile.writeAsString(jsonEncode(unbalancedBackup));

      expect(
        () => backup.importBackupFile(tempFile, replaceExisting: false),
        throwsA(isA<BackupValidationException>()),
      );
      final afterCount = (await db.getJournalEntries()).length;
      expect(afterCount, beforeCount, reason: 'هیچ سندی (حتی سندهای قبل از آن نامتوازن) نباید وارد شده باشد');

      await tempFile.delete();
    });
  });

  group('مورد ۶ — Successful Full Restore (Test A)', () {
    test('یک Restore کامل و معتبر، روابط Foreign Key را صحیح حفظ می‌کند', () async {
      final cpId = await createCounterparty('مشتری اصلی');
      final projectId = await createProject(cpId, agreedAmount: 80000000);
      final cash = (await db.getCashAccounts()).first;
      await db.receiveProjectPayment(
          projectId: projectId, cashAccountId: cash.id!, amount: 20000000, date: '1404/01/10');

      final exportedJson = await backup.collectBackupData();

      final tempFile = File('${Directory.systemTemp.path}/full_restore_test.json');
      await tempFile.writeAsString(jsonEncode(exportedJson));

      await backup.importBackupFile(tempFile, replaceExisting: true);

      final restoredCounterparties = await db.getCounterparties(includeInactive: true);
      final restoredProjects = await db.getProjects();
      final restoredEntries = await db.getJournalEntries();

      expect(restoredCounterparties.length, 1);
      expect(restoredProjects.length, 1);
      expect(restoredProjects.first.counterpartyId, restoredCounterparties.first.id,
          reason: 'رابطه Project→Counterparty باید صحیح نگاشت شده باشد');
      expect(restoredEntries, isNotEmpty);
      final restoredLine = restoredEntries.first.lines.first;
      expect(restoredLine.projectId, restoredProjects.first.id,
          reason: 'رابطه JournalLine→Project باید صحیح نگاشت شده باشد');

      await tempFile.delete();
    });
  });

  group('چرخه کامل پشتیبان‌گیری — اثر انگشت داده پیش و پس از بازیابی', () {
    test('پس از Restore کامل، اثر انگشت داده دقیقاً با پیش از آن یکسان است', () async {
      // این تست همان کاری را می‌کند که کاربر باید دستی انجام دهد: داده
      // واقعی بساز، اثر انگشت بگیر، پشتیبان بگیر، همه‌چیز را پاک کن،
      // بازیابی کن، و اثر انگشت را دوباره مقایسه کن. برخلاف تست‌های
      // موجود که فقط چند فیلد را چک می‌کردند، این تست کل محتوای مالی را
      // با هم می‌سنجد - شامل جمع مبالغ، نه فقط تعداد رکوردها.
      final cpId = await createCounterparty('مشتری چرخه کامل');
      final projectA = await createProject(cpId, agreedAmount: 100000000);
      final projectB = await createProject(cpId, agreedAmount: 50000000);
      final cash = (await db.getCashAccounts()).first;

      // پروژه A: نهایی‌شده + دریافت جزئی
      await db.finalizeProject(projectId: projectA, finalAmount: 100000000, date: '1404/02/01');
      await db.receiveProjectPayment(
          projectId: projectA, cashAccountId: cash.id!, amount: 40000000, date: '1404/02/05');
      // پروژه B: نهایی‌نشده + پیش‌دریافت
      await db.receiveProjectPayment(
          projectId: projectB, cashAccountId: cash.id!, amount: 15000000, date: '1404/02/10');

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
      await db.finalizeProject(projectId: projectId, finalAmount: 30000000, date: '1404/03/01');

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
