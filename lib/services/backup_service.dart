import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../db/database_helper.dart';
import '../models/counterparty.dart';
import '../models/project.dart';
import '../models/project_price_event.dart';
import '../models/account.dart';
import '../models/journal_entry.dart';
import '../utils/formatters.dart';
import 'backup_crypto.dart';

/// نسخه فعلی فرمت فایل پشتیبان. فقط همین نسخه برای Restore پشتیبانی
/// می‌شود؛ طبق سیاست این مرحله («سیستم Migration کامل بین نسخه‌ها ساخته
/// نشود مگر ضروری باشد»)، نسخه‌های دیگر با خطای صریح رد می‌شوند، نه حدس
/// زده یا به‌زور Import شوند.
const int kBackupFormatVersion = 5;

/// کلید تنظیمات برای تاریخ آخرین پشتیبان‌گیری موفق - در همان جدول
/// key-value تنظیمات موجود ذخیره می‌شود (بدون هیچ جدول/ستون جدید)، برای
/// یادآور پشتیبان‌گیری در داشبورد.
const String kLastBackupDateSettingKey = 'last_backup_date';

/// استثنای اختصاصی برای خطاهای اعتبارسنجی/بازیابی پشتیبان - پیام آن برای
/// نمایش مستقیم به کاربر مناسب است.
class BackupValidationException implements Exception {
  final String message;
  BackupValidationException(this.message);
  @override
  String toString() => message;
}

/// فایل انتخاب‌شده رمزنگاری‌شده است ولی رمز عبوری داده نشده - سیگنالی برای
/// لایه UI تا از کاربر رمز عبور بپرسد و importBackupFile را دوباره با آن
/// فراخوانی کند؛ این استثنا به‌خودی‌خود به معنای خطا/فایل نامعتبر نیست.
class BackupPasswordRequiredException implements Exception {
  @override
  String toString() => 'این فایل پشتیبان رمزنگاری‌شده است.';
}

class BackupService {
  final _db = DatabaseHelper.instance;

  /// [password] اختیاری است: اگر داده شود، کل فایل پشتیبان با
  /// AES-256-GCM رمزنگاری می‌شود (رجوع به BackupCrypto) - چون این فایل
  /// معمولاً از طریق کانال‌های عمومی (پیامک/ایمیل/فضای ابری) به اشتراک
  /// گذاشته می‌شود و بدون رمز، کل اطلاعات مالی خام قابل‌خواندن است. فراموش
  /// کردن این رمز به معنای از دست رفتن کامل و بدون بازگشت آن فایل خاص است
  /// - هیچ راه دیگری برای رمزگشایی وجود ندارد.
  Future<String> exportToFile({String? password}) async {
    final data = await collectBackupData();
    final plainJson = const JsonEncoder.withIndent('  ').convert(data);
    final content = (password != null && password.isNotEmpty)
        ? jsonEncode(BackupCrypto.encrypt(plainJson, password))
        : plainJson;

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/daftaryar_backup_$stamp.json');
    await file.writeAsString(content);

    // ثبت تاریخ آخرین پشتیبان‌گیری موفق - برای یادآور داشبورد. همین‌جا (نه
    // پس از تأیید Share) ثبت می‌شود چون گزارش نتیجه Share روی همه پلتفرم‌ها
    // قابل‌اتکا نیست؛ فایل پشتیبان با موفقیت ساخته شده که خودش هدف اصلی است.
    await _db.setSetting(kLastBackupDateSettingKey, todayJalaliString());

    await Share.shareXFiles([XFile(file.path)], text: 'پشتیبان دفتریار');
    return file.path;
  }

  /// جمع‌آوری کامل داده پشتیبان - شامل فیلتر امنیتی (اولویت ۳ مرحله
  /// Hardening) - بدون هیچ وابستگی به path_provider/share_plus. این متد
  /// به‌طور مستقیم و بدون نیاز به Mock کردن هیچ Platform Channel ای در
  /// تست واحد (با sqflite_common_ffi) قابل‌فراخوانی است، تا اگر در آینده
  /// کسی به‌اشتباه فیلتر امنیتی را حذف کند (مثلاً 'settings': allSettings
  /// به‌جای settings فیلترشده)، تست مستقیماً و بدون نیاز به شبیه‌سازی
  /// دوباره منطق، آن را تشخیص دهد.
  Future<Map<String, dynamic>> collectBackupData() async {
    final counterparties = await _db.getCounterparties(includeInactive: true);
    final projects = await _db.getProjects();
    // getAccounts برای نمایش با 'type ASC, code ASC' مرتب می‌شود. زیرحساب‌های
    // بدون کد (مثلاً «آورده مالک» زیر «سرمایه») در SQLite با code=NULL در
    // ترتیب صعودی قبل از هر مقدار غیر-NULL می‌آیند - یعنی زیرحساب می‌تواند
    // در فایل پشتیبان قبل از والدش (که کد دارد، مثل «سرمایه» با کد ۳۰۰۰)
    // ظاهر شود. بازیابی این لیست را همان‌طور که هست دوباره درج می‌کند، پس
    // به parentId والدی سند می‌زند که هنوز در دیتابیس تازه ساخته نشده -
    // FOREIGN KEY constraint failed. دقیقاً همان کلاس باگ اسناد حسابداری
    // زیر (رجوع به توضیح entries) - ترتیب صدور باید ترتیب واقعی درج (id
    // صعودی) باشد، که تضمین می‌کند والد همیشه پیش از فرزندش ساخته شده.
    final accounts = await _db.getAccounts()
      ..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
    // getJournalEntries برای نمایش (جدیدترین اول) با 'date DESC, id DESC'
    // مرتب می‌شود. اگر همین ترتیب مستقیم در فایل پشتیبان صادر شود، در
    // بازیابی اتمیک (replaceExisting) اسناد به ترتیب معکوس دوباره درج
    // می‌شوند - و کنترل Overpayment سطح طرف‌حساب/پروژه که مانده لحظه‌ای
    // حساب را می‌سنجد، اسناد چندگانه هم‌تاریخ (بسیار رایج) را به‌اشتباه رد
    // می‌کند، چون سند «دریافت» پیش از سند «شناسایی درآمد» که طلب را ساخته
    // بازپخش می‌شود. ترتیب صدور باید همان ترتیب واقعی درج (id صعودی) باشد
    // تا بازیابی، دقیقاً به همان توالی که رخ داده، بازپخش شود.
    final entries = await _db.getJournalEntries()
      ..sort((a, b) => (a.id ?? 0).compareTo(b.id ?? 0));
    final allSettings = await _db.getAllSettings();
    // امنیت (اولویت ۳ این مرحله): تنظیمات حساس/امنیتی (pin_hash و هر
    // Setting دیگری که ماهیت قفل دستگاه را کنترل می‌کند) هرگز نباید در
    // فایل پشتیبان عادی صادر شوند. این فیلتر از همان لیست مرکزی
    // DatabaseHelper.kSecuritySettingKeys استفاده می‌کند تا با فیلتر
    // دفاعی سمت Restore هم از یک منبع واحد باشد.
    final settings = Map<String, String>.fromEntries(
        allSettings.entries.where((e) => !DatabaseHelper.kSecuritySettingKeys.contains(e.key)));
    final priceEvents = <Map<String, dynamic>>[];
    for (final p in projects) {
      final events = await _db.getProjectPriceEvents(p.id!);
      priceEvents.addAll(events.map((e) => e.toMap()));
    }

    return {
      'version': kBackupFormatVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'counterparties':
          counterparties.map((e) => {...e.toMap(), 'roles': e.roles}).toList(),
      'projects': projects.map((e) => {...e.toMap(), 'projectTypes': e.projectTypes}).toList(),
      'projectPriceEvents': priceEvents,
      'accounts': accounts.map((e) => e.toMap()).toList(),
      'journalEntries': entries
          .map((e) => {
                ...e.toMap(),
                'lines': e.lines.map((l) => l.toMap()).toList(),
              })
          .toList(),
      'settings': settings,
    };
  }

  // ==================== اعتبارسنجی پیش از هرگونه نوشتن ====================
  // طبق اولویت ۱ این مرحله: JSON باید پیش از پاک‌کردن هر داده‌ای، کامل
  // اعتبارسنجی شود (نسخه + ساختار + توازن اسناد حسابداری) تا خطاهای
  // ساختاری قبل از هر تغییری در دیتابیس شناسایی شوند.

  /// اعتبارسنجی کامل ساختار/نسخه/توازن مالی فایل پشتیبان. در صورت نامعتبر
  /// بودن، BackupValidationException پرتاب می‌کند - هیچ تغییری در دیتابیس
  /// هنوز اعمال نشده است (این تابع فقط داده ورودی JSON را می‌خواند).
  void _validateBackupStructure(Map<String, dynamic> data) {
    final version = data['version'];
    if (version is! int || version != kBackupFormatVersion) {
      throw BackupValidationException(
          'نسخه فایل پشتیبان پشتیبانی نمی‌شود (نسخه دریافتی: ${version ?? 'نامشخص'}؛ نسخه موردنیاز: $kBackupFormatVersion).');
    }

    for (final key in ['counterparties', 'projects', 'accounts', 'journalEntries']) {
      if (data[key] is! List) {
        throw BackupValidationException('ساختار فایل پشتیبان نامعتبر است: بخش «$key» یافت نشد یا نوع آن اشتباه است.');
      }
    }
    // projectPriceEvents و settings در نسخه‌های خیلی قدیمی ممکن است غایب
    // باشند؛ اگر حاضرند باید نوع درستی داشته باشند.
    if (data.containsKey('projectPriceEvents') && data['projectPriceEvents'] is! List) {
      throw BackupValidationException('ساختار فایل پشتیبان نامعتبر است: بخش «projectPriceEvents» نوع اشتباهی دارد.');
    }
    if (data.containsKey('settings') && data['settings'] is! Map) {
      throw BackupValidationException('ساختار فایل پشتیبان نامعتبر است: بخش «settings» نوع اشتباهی دارد.');
    }

    // اعتبارسنجی تک‌تک اسناد حسابداری: هر سند باید حداقل یک سطر معتبر
    // داشته باشد و جمع بدهکار دقیقاً برابر جمع بستانکار باشد. اگر حتی یک
    // سند نامتوازن/ناقص باشد، کل Restore رد می‌شود - نه این‌که آن یک سند
    // بی‌سروصدا نادیده گرفته شود (رفتار قبلی) و نه این‌که با داده ناقص
    // ادامه یابد.
    final entriesRaw = data['journalEntries'] as List;
    for (var i = 0; i < entriesRaw.length; i++) {
      final e = entriesRaw[i];
      if (e is! Map) {
        throw BackupValidationException('سند حسابداری شماره ${i + 1} در فایل پشتیبان ساختار نامعتبری دارد.');
      }
      final linesRaw = e['lines'];
      if (linesRaw is! List || linesRaw.isEmpty) {
        throw BackupValidationException('سند حسابداری شماره ${i + 1} فاقد سطر معتبر است.');
      }
      int totalDebit = 0, totalCredit = 0;
      for (final l in linesRaw) {
        if (l is! Map || l['accountId'] is! int) {
          throw BackupValidationException('یکی از سطرهای سند حسابداری شماره ${i + 1} ارجاع حساب نامعتبر دارد.');
        }
        final debit = (l['debit'] as num?)?.round() ?? 0;
        final credit = (l['credit'] as num?)?.round() ?? 0;
        if (debit < 0 || credit < 0) {
          throw BackupValidationException('سند حسابداری شماره ${i + 1} مقدار منفی نامعتبر دارد.');
        }
        totalDebit += debit;
        totalCredit += credit;
      }
      if (totalDebit != totalCredit || totalDebit == 0) {
        throw BackupValidationException(
            'سند حسابداری شماره ${i + 1} نامتوازن است (بدهکار=$totalDebit، بستانکار=$totalCredit) و کل بازیابی متوقف شد.');
      }
    }
  }

  /// بازیابی از فایل انتخابی. در حالت replaceExisting=true، کل عملیات
  /// (پاک‌سازی + Import) داخل یک Transaction واقعی SQLite انجام می‌شود:
  /// یا کل Backup با موفقیت جایگزین می‌شود، یا در صورت هر خطا، دیتابیس
  /// دقیقاً به‌همان وضعیت پیش از Restore بازمی‌گردد (Rollback خودکار).
  Future<void> importFromPickedFile({bool replaceExisting = false, String? password}) async {
    final file = await pickBackupFile();
    if (file == null) return;
    await importBackupFile(file, replaceExisting: replaceExisting, password: password);
  }

  /// فقط انتخاب فایل (بدون Import) - جدا شده تا مسیر UI بتواند ابتدا فایل
  /// را انتخاب کند و تنها در صورت رمزنگاری‌شده‌بودنِ آن (خطای
  /// BackupPasswordRequiredException از importBackupFile)، رمز عبور را از
  /// کاربر بپرسد و importBackupFile را با همان File دوباره فراخوانی کند -
  /// بدون این‌که کاربر مجبور شود فایل را دوباره انتخاب کند.
  Future<File?> pickBackupFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return null;
    return File(result.files.single.path!);
  }

  /// هسته قابل‌تست Restore - مستقیم یک File می‌گیرد (نه از طریق FilePicker
  /// UI)، تا بتوان آن را در تست واحد بدون نیاز به تعامل کاربر فراخوانی
  /// کرد. تمام منطق واقعی Validation/Atomicity این‌جا متمرکز است؛
  /// "importFromPickedFile" فقط یک Wrapper نازک روی همین متد برای مسیر UI
  /// است - رفتار برای کاربر نهایی هیچ تغییری نکرده است.
  Future<void> importBackupFile(File file,
      {bool replaceExisting = false, String? password}) async {
    final content = await file.readAsString();
    final Map<String, dynamic> raw;
    try {
      raw = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      throw BackupValidationException('فایل انتخاب‌شده یک JSON معتبر نیست.');
    }

    // اگر فایل با رمز عبور رمزنگاری شده (envelope با کلید نشان‌گر)، ابتدا
    // باید رمزگشایی شود؛ بدون رمز عبور، سیگنال BackupPasswordRequiredException
    // پرتاب می‌شود تا لایه UI آن را از کاربر بپرسد. فایل‌های پشتیبان قدیمی
    // (بدون رمز) اصلاً این کلید را ندارند و مثل قبل مستقیم پردازش می‌شوند.
    Map<String, dynamic> data = raw;
    if (BackupCrypto.isEncryptedEnvelope(raw)) {
      if (password == null || password.isEmpty) {
        throw BackupPasswordRequiredException();
      }
      final decryptedJson = BackupCrypto.decrypt(raw, password);
      try {
        data = jsonDecode(decryptedJson) as Map<String, dynamic>;
      } catch (_) {
        throw BackupValidationException('محتوای رمزگشایی‌شده این فایل پشتیبان یک JSON معتبر نیست.');
      }
    }

    // اعتبارسنجی کامل پیش از هرگونه تغییر در دیتابیس - چه در حالت
    // replaceExisting چه در حالت Append.
    _validateBackupStructure(data);

    if (replaceExisting) {
      // کل عملیات (پاک‌سازی + Import همه بخش‌ها) داخل یک Transaction واقعی.
      final db = await _db.database;
      await db.transaction((txn) async {
        await _db.wipeAll(txn);
        await _importInto(data, txn);
      });
    } else {
      // حالت Append: طبق دستور صریح، semantics فعلی (Import تدریجی بدون
      // پاک‌سازی) بدون دلیل تغییر نکرد؛ اما همان اعتبارسنجی پیشین بالا
      // (ساختار + توازن) اکنون قبل از این حالت هم اجرا می‌شود.
      await _importInto(data, null);
    }
  }

  /// هسته مشترک Import - با executor داده‌شده (یک Transaction برای حالت
  /// Atomic، یا null برای حالت Append قبلی که هرکدام تراکنش خودشان را باز
  /// می‌کنند).
  Future<void> _importInto(Map<String, dynamic> data, DatabaseExecutor? executor) async {
    final Map<int, int> counterpartyIdMap = {};
    for (final c in (data['counterparties'] as List? ?? [])) {
      final map = Map<String, dynamic>.from(c);
      final rolesRaw = map['roles'] as List? ?? [];
      final roles = rolesRaw.map((r) => r.toString()).toList();
      final counterparty = CounterpartyModel.fromMap(map, roles: roles);
      final newId = await _db.insertCounterparty(counterparty, executor);
      counterpartyIdMap[counterparty.id ?? -1] = newId;
    }

    final Map<int, int> projectIdMap = {};
    for (final p in (data['projects'] as List? ?? [])) {
      final map = Map<String, dynamic>.from(p);
      // پشتیبان‌های این مرحله به بعد لیست کامل projectTypes را دارند؛
      // پشتیبان‌های قدیمی‌تر فقط ستون تکی projectType را داشتند - در آن
      // حالت همان یک مقدار به‌عنوان تنها نوع پروژه در نظر گرفته می‌شود تا
      // هیچ داده‌ای گم نشود.
      final typesRaw = map['projectTypes'] as List?;
      final types = typesRaw != null
          ? typesRaw.map((t) => t.toString()).toList()
          : [if ((map['projectType'] as String?)?.isNotEmpty ?? false) map['projectType'] as String];
      final project = ProjectModel.fromMap(map, projectTypes: types);
      final mappedCounterpartyId =
          counterpartyIdMap[project.counterpartyId] ?? project.counterpartyId;
      final newId = await _db.insertProject(
          project.copyWith(counterpartyId: mappedCounterpartyId), executor);
      projectIdMap[project.id ?? -1] = newId;
    }

    for (final pe in (data['projectPriceEvents'] as List? ?? [])) {
      final event = ProjectPriceEventModel.fromMap(Map<String, dynamic>.from(pe));
      final mappedProjectId = projectIdMap[event.projectId] ?? event.projectId;
      await _db.insertProjectPriceEventRaw(
        ProjectPriceEventModel(
          projectId: mappedProjectId,
          type: event.type,
          amount: event.amount,
          reason: event.reason,
          date: event.date,
          createdAt: event.createdAt,
        ),
        executor,
      );
    }

    // حساب‌ها: حساب‌های سیستمی هرگز دوباره ساخته نمی‌شوند - همیشه به حساب
    // سیستمی موجود روی دستگاه مقصد Map می‌شوند (اولویت ۲ این مرحله).
    // اولویت تطبیق: systemKey (شناسه پایدار و صحیح) → در صورت غیاب آن
    // (فایل پشتیبان بسیار قدیمی)، fallback به نام+نوع. این تطبیق هیچ
    // وابستگی ترتیبی ندارد (چیزی درج نمی‌شود، فقط Map می‌شود).
    final Map<int, int> accountIdMap = {};
    final existingAccounts = await _db.getAccounts(executor: executor);
    final rawAccounts = (data['accounts'] as List? ?? [])
        .map((a) => AccountModel.fromMap(Map<String, dynamic>.from(a)))
        .toList();

    final nonSystemAccounts = <AccountModel>[];
    for (final account in rawAccounts) {
      if (account.isSystem) {
        AccountModel? match;
        if (account.systemKey != null) {
          final bySystemKey =
              existingAccounts.where((x) => x.isSystem && x.systemKey == account.systemKey);
          if (bySystemKey.isNotEmpty) match = bySystemKey.first;
        }
        // Fallback فقط برای Backupهای قدیمی فاقد systemKey - هرگز مسیر
        // اصلی نیست، فقط وقتی systemKey غایب یا در دستگاه مقصد یافت نشود.
        match ??= existingAccounts
            .where((x) => x.isSystem && x.name == account.name && x.type == account.type)
            .firstOrNullSafe();
        if (match != null) {
          accountIdMap[account.id ?? -1] = match.id!;
          continue;
        }
      }
      nonSystemAccounts.add(account);
    }

    // چند-پاسی و مقاوم به ترتیب: فایل‌های پشتیبان قدیمی‌تر از رفع این باگ
    // ممکن است زیرحساب را قبل از والدش فهرست کرده باشند (collectBackupData
    // قبلاً حساب‌ها را با ترتیب نمایشی type/code صادر می‌کرد که برای
    // زیرحساب‌های بدون کد والد را بعد از فرزند می‌آورد). به‌جای این‌که به
    // ترتیب ورودی فایل اعتماد شود (و در نبود Map شدنِ والد، به id قدیمی و
    // بی‌ربط سند بزند - FOREIGN KEY constraint)، هر پاس فقط حساب‌هایی را
    // درج می‌کند که والدشان (اگر دارند) از قبل Map شده؛ تا وقتی پیشرفتی
    // حاصل شود تکرار می‌شود.
    var remaining = nonSystemAccounts;
    while (remaining.isNotEmpty) {
      final nextRemaining = <AccountModel>[];
      var progressed = false;
      for (final account in remaining) {
        final parentUnresolved =
            account.parentId != null && !accountIdMap.containsKey(account.parentId);
        if (parentUnresolved) {
          nextRemaining.add(account);
          continue;
        }
        progressed = true;
        final mappedParentId =
            account.parentId != null ? accountIdMap[account.parentId] : null;
        final newId = await _db.insertAccount(
          account.copyWith(
            parentId: mappedParentId,
            clearParent: mappedParentId == null,
            isSystem: false,
          ),
          executor,
        );
        accountIdMap[account.id ?? -1] = newId;
      }
      if (!progressed) {
        // زنجیره غیرقابل‌حل واقعی (parentId اشاره به چیزی که اصلاً در فایل
        // نیست، نه صرفاً ترتیب اشتباه) - به‌جای شکست کل Restore به‌خاطر
        // چند رکورد خراب، بدون والد درج می‌شوند.
        for (final account in nextRemaining) {
          final newId = await _db.insertAccount(
            account.copyWith(clearParent: true, isSystem: false),
            executor,
          );
          accountIdMap[account.id ?? -1] = newId;
        }
        break;
      }
      remaining = nextRemaining;
    }

    for (final e in (data['journalEntries'] as List? ?? [])) {
      final map = Map<String, dynamic>.from(e);
      final linesRaw = (map['lines'] as List? ?? []);
      final lines = linesRaw.map((l) {
        final lm = Map<String, dynamic>.from(l);
        final originalAccountId = lm['accountId'] as int;
        final mappedAccountId = accountIdMap[originalAccountId] ?? originalAccountId;
        final originalProjectId = lm['projectId'] as int?;
        final mappedProjectId =
            originalProjectId != null ? (projectIdMap[originalProjectId] ?? originalProjectId) : null;
        final originalCounterpartyId = lm['counterpartyId'] as int?;
        final mappedCounterpartyId = originalCounterpartyId != null
            ? (counterpartyIdMap[originalCounterpartyId] ?? originalCounterpartyId)
            : null;
        return JournalLineModel(
          accountId: mappedAccountId,
          debit: (lm['debit'] as num).round(),
          credit: (lm['credit'] as num).round(),
          description: lm['description'] as String?,
          projectId: mappedProjectId,
          counterpartyId: mappedCounterpartyId,
        );
      }).toList();

      final entry = JournalEntryModel(
        date: map['date'] as String,
        description: map['description'] as String?,
        createdAt: map['createdAt'] as String? ?? map['date'] as String,
        lines: lines,
        // اگر فایل پشتیبان قدیمی‌تر از افزودن این فیلد باشد، map['source']
        // به‌طور طبیعی غایب/NULL است - که طبق semantics جدید یعنی
        // legacy/محافظت‌شده (نه این‌که حدس زده شود «دستی» بوده)؛ اگر فایل
        // پشتیبان جدید باشد، مقدار واقعی (system/manual) عیناً حفظ می‌شود.
        source: map['source'] as String?,
      );
      // توازن هر سند از قبل در _validateBackupStructure برای کل فایل تأیید
      // شده؛ این بررسی دوم صرفاً محافظتی است (Defense in Depth) و اگر با
      // خطا مواجه شود (که نباید)، در حالت Atomic باعث Rollback کل Restore
      // می‌شود، نه نادیده‌گرفتن بی‌سروصدا.
      if (!entry.isBalanced) {
        throw BackupValidationException('سند حسابداری «${entry.description ?? entry.date}» نامتوازن است.');
      }
      await _db.insertJournalEntry(entry, executor);
    }

    // تنظیمات برنامه (سال مالی، پیامک بانکی و...) - تنظیمات امنیتی/حساس
    // (pin_hash و...) حتی اگر به هر دلیلی در فایل پشتیبان حضور داشته
    // باشند، توسط DatabaseHelper.setAllSettings به‌صورت دفاعی نادیده
    // گرفته می‌شوند (رجوع به kSecuritySettingKeys) - یعنی قفل امنیتی
    // فعلی دستگاه مقصد هرگز توسط Restore تغییر نمی‌کند.
    final settingsRaw = data['settings'];
    if (settingsRaw is Map) {
      final settings = settingsRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
      await _db.setAllSettings(settings, executor);
    }
  }
}

extension _FirstOrNullSafe<T> on Iterable<T> {
  T? firstOrNullSafe() => isEmpty ? null : first;
}
