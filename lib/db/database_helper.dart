import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../models/counterparty.dart';
import '../models/project.dart';
import '../models/project_price_event.dart';
import '../models/account.dart';
import '../models/journal_entry.dart';
import '../models/sms_draft.dart';
import '../utils/formatters.dart';

class DatabaseHelper {
  DatabaseHelper._internal();
  static final DatabaseHelper instance = DatabaseHelper._internal();

  static Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'daftaryar_v9.db');
    return openDatabase(
      path,
      version: 3,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      onConfigure: (db) async {
        // بدون این، قیدهای ON DELETE CASCADE / SET NULL در جداول عملاً نادیده گرفته
        // می‌شدند و حذف کارفرما/پروژه باعث باقی‌ماندن رکوردهای یتیم می‌شد
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  /// Migration واقعی و Backward-Compatible - برخلاف رویه قبلی این پروژه (که
  /// با تغییر نام فایل دیتابیس عملاً داده‌های قبلی را رها می‌کرد)، از این
  /// نسخه به بعد تغییرات Schema باید از همین مسیر (نه تغییر نام فایل) انجام
  /// شوند تا داده مالی موجود کاربران حفظ شود.
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // ستون منشأ سند - برای تشخیص Journalهای System-generated (مورد ۴)
      await db.execute('ALTER TABLE journal_entries ADD COLUMN source TEXT');

      // قید یکتایی روی systemKey - قبل از ایجاد قید، duplicate احتمالی را
      // بررسی می‌کنیم؛ اگر duplicate واقعی پیدا شود، به‌جای silent-rewrite
      // دادهٔ مالی، فقط از ایجاد قید صرف‌نظر می‌کنیم (خرابی داده موجود
      // ترجیح داده نمی‌شود بر عدم وجود قید).
      final duplicates = await db.rawQuery('''
        SELECT systemKey, COUNT(*) as cnt FROM accounts
        WHERE systemKey IS NOT NULL
        GROUP BY systemKey HAVING COUNT(*) > 1
      ''');
      if (duplicates.isEmpty) {
        await db.execute(
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_accounts_systemKey_unique ON accounts (systemKey) WHERE systemKey IS NOT NULL');
      }
      // در صورت وجود duplicate، این مورد باید در گزارش نهایی به‌صراحت اعلام
      // شود (نه silently نادیده گرفته شود) - رجوع کنید به گزارش نهایی این مرحله.
    }
    if (oldVersion < 3) {
      // مورد «Account Hierarchy — گزینه A»: تفکیک Leaf-Lock از Identity
      // Protection. پیش‌فرض ستون برای همه سطرهای موجود 0 (Leaf-Locked)
      // است - محافظه‌کارانه‌ترین حالت برای داده مالی موجود؛ سپس فقط برای
      // حساب‌های سیستمی‌ای که واقعاً باید بتوانند زیرحساب بگیرند (صندوق/بانک
      // + همهٔ حساب‌های سیستمی بدون systemKey که هیچ منطق داخلی به هویتشان
      // وابسته نیست + هزینه مستقیم پروژه که systemKey‌اش عملاً بلااستفاده
      // است)، صریحاً به 1 تغییر داده می‌شود. حساب‌های کنترلی واقعی
      // (AR/AP/پیش‌دریافت/بستانکاری/درآمد پروژه‌ها/سربار/تخفیف) عمداً از
      // این لیست کنار گذاشته شده‌اند تا Leaf-Locked باقی بمانند - این
      // تصمیم بر اساس Code Usage واقعی گرفته شد، نه حدس (رجوع به گزارش
      // تحلیل معماری حساب‌ها).
      await db.execute('ALTER TABLE accounts ADD COLUMN allowChildren INTEGER NOT NULL DEFAULT 0');
      const hierarchySafeSystemKeys = [kSystemKeyCash, kSystemKeyBank, kSystemKeyDirectProjectCost];
      await db.execute('''
        UPDATE accounts SET allowChildren = 1
        WHERE isSystem = 1 AND (systemKey IS NULL OR systemKey IN (${hierarchySafeSystemKeys.map((_) => '?').join(',')}))
      ''', hierarchySafeSystemKeys);
    }
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE counterparties (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        nationalId TEXT,
        notes TEXT,
        isActive INTEGER NOT NULL DEFAULT 1,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');

    // نقش‌ها به‌صورت جدول مستقل (نه فیلد ثابت روی خودِ طرف حساب) تا افزودن
    // نقش جدید در آینده نیازی به تغییر ساختار اصلی نداشته باشد.
    await db.execute('''
      CREATE TABLE counterparty_roles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      )
    ''');

    await db.execute('''
      CREATE TABLE counterparty_role_assignments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        counterpartyId INTEGER NOT NULL,
        roleId INTEGER NOT NULL,
        FOREIGN KEY (counterpartyId) REFERENCES counterparties (id) ON DELETE CASCADE,
        FOREIGN KEY (roleId) REFERENCES counterparty_roles (id) ON DELETE CASCADE,
        UNIQUE (counterpartyId, roleId)
      )
    ''');

    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        counterpartyId INTEGER NOT NULL,
        projectType TEXT NOT NULL,
        status TEXT NOT NULL,
        startDate TEXT NOT NULL,
        agreedAmount REAL NOT NULL DEFAULT 0,
        description TEXT,
        createdAt TEXT NOT NULL,
        finalAmount REAL,
        finalizedDate TEXT,
        finalizedNote TEXT,
        FOREIGN KEY (counterpartyId) REFERENCES counterparties (id) ON DELETE CASCADE
      )
    ''');

    // تاریخچه تغییرات مبلغ پروژه - رکورد اصلی هرگز overwrite نمی‌شود؛ هر
    // تغییر (پیش یا پس از Finalization) یک ردیف مستقل و همیشگی است.
    await db.execute('''
      CREATE TABLE project_price_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        projectId INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        reason TEXT,
        date TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_price_events_projectId ON project_price_events (projectId)');

    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        parentId INTEGER,
        isSystem INTEGER NOT NULL DEFAULT 0,
        systemKey TEXT,
        allowChildren INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (parentId) REFERENCES accounts (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        description TEXT,
        source TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute(
        'CREATE UNIQUE INDEX idx_accounts_systemKey_unique ON accounts (systemKey) WHERE systemKey IS NOT NULL');

    await db.execute('''
      CREATE TABLE journal_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entryId INTEGER NOT NULL,
        accountId INTEGER NOT NULL,
        debit INTEGER NOT NULL DEFAULT 0,
        credit INTEGER NOT NULL DEFAULT 0,
        description TEXT,
        projectId INTEGER,
        counterpartyId INTEGER,
        FOREIGN KEY (entryId) REFERENCES journal_entries (id) ON DELETE CASCADE,
        FOREIGN KEY (accountId) REFERENCES accounts (id),
        FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE SET NULL,
        FOREIGN KEY (counterpartyId) REFERENCES counterparties (id) ON DELETE SET NULL,
        CHECK (debit >= 0 AND credit >= 0),
        CHECK (NOT (debit > 0 AND credit > 0)),
        CHECK (NOT (debit = 0 AND credit = 0))
      )
    ''');

    await db.execute('CREATE INDEX idx_journal_lines_entryId ON journal_lines (entryId)');
    await db.execute('CREATE INDEX idx_journal_lines_accountId ON journal_lines (accountId)');
    await db.execute('CREATE INDEX idx_projects_counterpartyId ON projects (counterpartyId)');
    await db.execute(
        'CREATE INDEX idx_role_assignments_counterpartyId ON counterparty_role_assignments (counterpartyId)');

    for (final roleName in kDefaultCounterpartyRoles) {
      await db.insert('counterparty_roles', {'name': roleName});
    }

    await db.execute('''
      CREATE TABLE app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE sms_drafts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        rawBody TEXT NOT NULL,
        sender TEXT,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        date TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        createdAt TEXT NOT NULL
      )
    ''');

    await _seedDefaultAccounts(db);
  }

  Future<void> _seedDefaultAccounts(DatabaseExecutor db) async {
    final now = DateTime.now().toIso8601String();
    Future<int> add(String code, String name, String type,
        {int? parentId, String? systemKey, bool allowChildren = false}) {
      return db.insert('accounts', {
        'code': code,
        'name': name,
        'type': type,
        'parentId': parentId,
        'isSystem': 1,
        'systemKey': systemKey,
        'allowChildren': allowChildren ? 1 : 0,
        'createdAt': now,
      });
    }

    // دارایی - صندوق/بانک فقط نقطه شروع سلسله‌مراتب‌اند (مثل «بانک ملی» زیر
    // «بانک»)؛ کد مصرف‌کننده (getCashAccounts/_isCashOrBankAccount) از قبل
    // با پیمایش زنجیره والد برای همین سناریو طراحی شده بود.
    await add('1000', 'صندوق', kAccountAsset, systemKey: kSystemKeyCash, allowChildren: true);
    await add('1010', 'بانک', kAccountAsset, systemKey: kSystemKeyBank, allowChildren: true);
    // حساب‌های دریافتنی: Control Account واقعی - منطق داخلی (finalizeProject و...)
    // مستقیم روی id همین حساب سند می‌زند؛ اگر زیرحساب بگیرد، آن سندها با
    // خطای «حساب دارای زیرحساب است» شکست می‌خورند. هرگز نباید Parent شود.
    await add('1100', 'حساب‌های دریافتنی', kAccountAsset, systemKey: kSystemKeyReceivable);

    // بدهی
    await add('2000', 'حساب‌های پرداختنی', kAccountLiability, systemKey: kSystemKeyPayable);
    await add('2010', 'پیش‌دریافت مشتری', kAccountLiability, systemKey: kSystemKeyCustomerAdvance);
    await add('2020', 'بستانکاری مشتری (مازاد دریافتی)', kAccountLiability,
        systemKey: kSystemKeyCustomerCredit);

    // حقوق صاحبان سرمایه - فقط یک حساب پیش‌فرض، هیچ منطقی به هویتش وابسته نیست
    await add('3000', 'سرمایه', kAccountEquity, allowChildren: true);

    // درآمد - «درآمد پروژه‌ها» تنها Control Account واقعی این گروه است
    // (finalizeProject/recordFinalAdjustment مستقیم روی آن سند می‌زنند)؛
    // بقیه صرفاً پیش‌فرض‌های راحتی‌اند و هیچ کدی به هویتشان وابسته نیست.
    await add('4000', 'درآمد نقشه‌برداری', kAccountIncome, allowChildren: true);
    await add('4010', 'درآمد پیگیری ثبتی', kAccountIncome, allowChildren: true);
    await add('4020', 'درآمد پروژه‌ها', kAccountIncome, systemKey: kSystemKeyProjectRevenue);
    await add('4090', 'سایر درآمدها', kAccountIncome, allowChildren: true);

    // هزینه - سربار پروژه‌ها و تخفیف خدمات Control Account واقعی‌اند
    // (officeOverheadTotal/officeExpenseTotal با تطبیق دقیق id جمع می‌بندند
    // یا مستثنی می‌کنند؛ recordProjectDiscount مستقیم به تخفیف سند می‌زند).
    // «هزینه مستقیم پروژه» با وجود داشتن systemKey، در عمل توسط هیچ کدی با
    // آن شناسه مستقیم جست‌وجو/سند نمی‌شود (Direct Cost بر مبنای نوع حساب +
    // projectId محاسبه می‌شود، نه این id خاص) - بنابراین زیرحساب گرفتنش
    // بی‌خطر است.
    await add('5000', 'هزینه‌های دفتر', kAccountExpense, allowChildren: true);
    await add('5010', 'هزینه‌های ثبتی/اداری پروژه', kAccountExpense, allowChildren: true);
    await add('5020', 'حقوق و دستمزد', kAccountExpense, allowChildren: true);
    await add('5030', 'هزینه‌های نقشه‌برداری', kAccountExpense, allowChildren: true);
    await add('5040', 'حمل و نقل', kAccountExpense, allowChildren: true);
    await add('5050', 'هزینه مستقیم پروژه', kAccountExpense,
        systemKey: kSystemKeyDirectProjectCost, allowChildren: true);
    await add('5060', 'سربار عمومی پروژه‌ها', kAccountExpense, systemKey: kSystemKeyProjectOverhead);
    await add('5070', 'تخفیف خدمات', kAccountExpense, systemKey: kSystemKeyServiceDiscount);
    await add('5090', 'سایر هزینه‌های عمومی', kAccountExpense, allowChildren: true);
  }

  // ---------------- Counterparties (طرف حساب) ----------------

  Future<int> insertCounterparty(CounterpartyModel c, [DatabaseExecutor? executor]) async {
    final db = executor ?? await database;
    final id = await db.insert(
        'counterparties',
        c.toMap()
          ..remove('id')
          ..remove('roles'));
    if (c.roles.isNotEmpty) {
      await setCounterpartyRoles(id, c.roles, executor);
    }
    return id;
  }

  Future<int> updateCounterparty(CounterpartyModel c) async {
    final db = await database;
    final result = await db.update(
        'counterparties',
        c.toMap()
          ..remove('roles'),
        where: 'id = ?', whereArgs: [c.id]);
    await setCounterpartyRoles(c.id!, c.roles);
    return result;
  }

  /// حذف فیزیکی فقط وقتی مجاز است که هیچ پروژه یا سند مالی به این طرف حساب
  /// اشاره نکرده باشد؛ در غیر این صورت خطا می‌دهد و باید غیرفعال شود.
  Future<void> deleteCounterparty(int id) async {
    final db = await database;
    final projectRows =
        await db.query('projects', where: 'counterpartyId = ?', whereArgs: [id], limit: 1);
    if (projectRows.isNotEmpty) {
      throw Exception('این طرف حساب پروژه ثبت‌شده دارد و قابل حذف فیزیکی نیست؛ آن را غیرفعال کنید.');
    }
    final lineRows = await db.query('journal_lines',
        where: 'counterpartyId = ?', whereArgs: [id], limit: 1);
    if (lineRows.isNotEmpty) {
      throw Exception('این طرف حساب در اسناد حسابداری استفاده شده و قابل حذف فیزیکی نیست؛ آن را غیرفعال کنید.');
    }
    await db.delete('counterparty_role_assignments', where: 'counterpartyId = ?', whereArgs: [id]);
    await db.delete('counterparties', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> setCounterpartyActive(int id, bool isActive) async {
    final db = await database;
    await db.update('counterparties', {'isActive': isActive ? 1 : 0, 'updatedAt': todayJalaliString()},
        where: 'id = ?', whereArgs: [id]);
  }

  Future<List<String>> _rolesForCounterparty(Database db, int counterpartyId) async {
    final rows = await db.rawQuery('''
      SELECT r.name as name FROM counterparty_roles r
      JOIN counterparty_role_assignments a ON a.roleId = r.id
      WHERE a.counterpartyId = ?
      ORDER BY r.name ASC
    ''', [counterpartyId]);
    return rows.map((r) => r['name'] as String).toList();
  }

  /// مجموعه نقش‌های یک طرف حساب را با مجموعه داده‌شده جایگزین می‌کند (نه اضافه)
  Future<void> setCounterpartyRoles(int counterpartyId, List<String> roleNames,
      [DatabaseExecutor? executor]) async {
    Future<void> body(DatabaseExecutor txn) async {
      await txn.delete('counterparty_role_assignments',
          where: 'counterpartyId = ?', whereArgs: [counterpartyId]);
      for (final roleName in roleNames) {
        var roleRows =
            await txn.query('counterparty_roles', where: 'name = ?', whereArgs: [roleName]);
        int roleId;
        if (roleRows.isEmpty) {
          roleId = await txn.insert('counterparty_roles', {'name': roleName});
        } else {
          roleId = roleRows.first['id'] as int;
        }
        await txn.insert('counterparty_role_assignments',
            {'counterpartyId': counterpartyId, 'roleId': roleId});
      }
    }

    if (executor != null) {
      await body(executor);
      return;
    }
    final db = await database;
    await db.transaction((txn) => body(txn));
  }

  Future<List<CounterpartyRoleModel>> getAllRoles() async {
    final db = await database;
    final maps = await db.query('counterparty_roles', orderBy: 'name ASC');
    return maps.map((m) => CounterpartyRoleModel.fromMap(m)).toList();
  }

  /// طرف‌های حساب؛ پیش‌فرض فقط فعال‌ها (برای انتخاب‌گرهای UI)، مگر این‌که
  /// includeInactive=true باشد (برای لیست کامل مدیریتی یا نمایش رکورد قدیمی)
  Future<List<CounterpartyModel>> getCounterparties({
    String? query,
    bool includeInactive = false,
  }) async {
    final db = await database;
    String? where = includeInactive ? null : 'isActive = 1';
    List<Object?> args = [];
    if (query != null && query.isNotEmpty) {
      final searchClause = '(name LIKE ? OR phone LIKE ?)';
      where = where == null ? searchClause : '$where AND $searchClause';
      args = ['%$query%', '%$query%'];
    }
    final maps = await db.query('counterparties',
        where: where, whereArgs: args.isEmpty ? null : args, orderBy: 'name ASC');
    final result = <CounterpartyModel>[];
    for (final m in maps) {
      final roles = await _rolesForCounterparty(db, m['id'] as int);
      result.add(CounterpartyModel.fromMap(m, roles: roles));
    }
    return result;
  }

  Future<CounterpartyModel?> getCounterparty(int id) async {
    final db = await database;
    final maps = await db.query('counterparties', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    final roles = await _rolesForCounterparty(db, id);
    return CounterpartyModel.fromMap(maps.first, roles: roles);
  }

  /// بررسی نرم و غیرمسدودکننده تکراری بودن - بر اساس تطابق کد ملی (در صورت
  /// وجود) یا تطابق دقیق نام؛ فقط برای هشدار به کاربر، نه رد خودکار
  Future<CounterpartyModel?> findPossibleDuplicateCounterparty({
    required String name,
    String? nationalId,
    int? excludeId,
  }) async {
    final db = await database;
    if (nationalId != null && nationalId.trim().isNotEmpty) {
      final where = excludeId != null ? 'nationalId = ? AND id != ?' : 'nationalId = ?';
      final args = excludeId != null ? [nationalId.trim(), excludeId] : [nationalId.trim()];
      final rows = await db.query('counterparties', where: where, whereArgs: args);
      if (rows.isNotEmpty) return CounterpartyModel.fromMap(rows.first);
    }
    final nameWhere = excludeId != null ? 'LOWER(name) = ? AND id != ?' : 'LOWER(name) = ?';
    final nameArgs = excludeId != null
        ? [name.trim().toLowerCase(), excludeId]
        : [name.trim().toLowerCase()];
    final rows = await db.query('counterparties', where: nameWhere, whereArgs: nameArgs);
    if (rows.isNotEmpty) return CounterpartyModel.fromMap(rows.first);
    return null;
  }

  // ---------------- Projects ----------------
  Future<int> insertProject(ProjectModel p, [DatabaseExecutor? executor]) async {
    final db = executor ?? await database;
    return db.insert('projects', p.toMap()..remove('id'));
  }

  /// آیا این پروژه هرگونه سابقه مالی دارد؟ (سند حسابداری یا رویداد تغییر
  /// قیمت - حتی پیش از Finalization، مثل یک پیش‌دریافت یا ADDITION ساده).
  /// این تعریف عمداً محافظه‌کارانه است: هر ردی که این پروژه را به یک رویداد
  /// مالی واقعی وصل می‌کند، کافی است تا Counterparty دیگر تغییرناپذیر شود.
  Future<bool> projectHasFinancialHistory(int projectId) async {
    final db = await database;
    final lines =
        await db.query('journal_lines', where: 'projectId = ?', whereArgs: [projectId], limit: 1);
    if (lines.isNotEmpty) return true;
    final events = await db.query('project_price_events',
        where: 'projectId = ?', whereArgs: [projectId], limit: 1);
    return events.isNotEmpty;
  }

  /// نقطه مرکزی ویرایش پروژه - یک CRUD کور نیست؛ پیش از نوشتن، وضعیت فعلی
  /// خوانده و تغییرات حساس enforce می‌شود. این محافظت مستقل از UI است تا
  /// هیچ Caller داخلی (نه فقط ProjectFormScreen) نتواند آن را دور بزند.
  Future<int> updateProject(ProjectModel p) async {
    final db = await database;
    final existing = await getProject(p.id!);
    if (existing == null) {
      throw Exception('پروژه یافت نشد.');
    }

    // پروژه Finalized: کل بسته اطلاعات Finalization (و به‌تبع آن Counterparty،
    // چون Ledger موجود به همان Counterparty اشاره دارد) فقط از طریق
    // Workflow اختصاصی (finalizeProject/recordFinalAdjustment) قابل تغییر
    // است، نه از مسیر ویرایش عمومی.
    if (existing.isFinalized) {
      if (p.finalAmount != existing.finalAmount ||
          p.finalizedDate != existing.finalizedDate ||
          p.finalizedNote != existing.finalizedNote) {
        throw Exception(
            'این پروژه نهایی شده؛ اطلاعات نهایی‌سازی فقط از طریق عملیات اختصاصی آن قابل تغییر است.');
      }
      if (p.status != existing.status) {
        throw Exception('وضعیت یک پروژه نهایی‌شده از مسیر ویرایش عمومی قابل تغییر نیست.');
      }
      if (p.counterpartyId != existing.counterpartyId) {
        throw Exception('طرف حساب یک پروژه نهایی‌شده قابل تغییر نیست.');
      }
    }

    // صرف‌نظر از Finalized بودن یا نه: اگر پروژه هرگونه سابقه مالی دارد
    // (حتی یک پیش‌دریافت ساده پیش از Finalization)، Counterparty تغییرناپذیر
    // است - چون Ledger موجود همچنان به Counterparty قبلی اشاره دارد.
    if (p.counterpartyId != existing.counterpartyId) {
      final hasHistory = await projectHasFinancialHistory(p.id!);
      if (hasHistory) {
        throw Exception(
            'این پروژه دارای سابقه مالی (سند حسابداری یا تغییر مبلغ ثبت‌شده) است؛ طرف حساب آن قابل تغییر نیست.');
      }
    }

    // status نباید از مسیر ویرایش عمومی مستقیماً به «نهایی‌شده» یا «لغوشده»
    // تبدیل شود؛ این دو وضعیت باید محصول یک Workflow اختصاصی و صریح باشند
    // (finalizeProject / cancelProject)، نه یک فیلد آزاد در فرم عمومی -
    // دقیقاً طبق اصل «State transition باید Explicit باشد».
    if (p.status != existing.status && p.status == kProjectStatusFinalized) {
      throw Exception('وضعیت «نهایی‌شده» فقط از طریق عملیات نهایی‌سازی پروژه قابل تنظیم است.');
    }
    if (p.status != existing.status && p.status == kProjectStatusCancelled) {
      throw Exception('وضعیت «لغوشده» فقط از طریق عملیات لغو پروژه قابل تنظیم است.');
    }

    // یک پروژه Finalized (بالاتر رد شد) هرگز نباید هم‌زمان Cancelled شود؛
    // این‌جا دوباره برای پروژه‌ای که همین لحظه Finalized نیست ولی درخواست
    // تغییر هم‌زمان finalAmount و status=Cancelled دارد، محافظت می‌شود.
    if (p.status == kProjectStatusCancelled && p.finalAmount != null) {
      throw Exception('یک پروژه نمی‌تواند هم‌زمان لغوشده و دارای مبلغ نهایی باشد.');
    }

    return db.update('projects', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }

  /// Workflow اختصاصی و صریح برای لغو پروژه - state transition به Cancelled
  /// هرگز نباید از یک فراخوانی عمومی updateProject با status دلخواه ایجاد
  /// شود؛ این تابع تنها مسیر مجاز است (مشابه finalizeProject برای Finalized).
  /// طبق معماری موجود (مرحله قبل)، لغو پروژه هیچ اثر مالی‌ای ندارد - فقط
  /// وضعیت عملیاتی تغییر می‌کند؛ اسناد/رویدادهای قیمت قبلی دست‌نخورده می‌مانند.
  Future<int> cancelProject(int projectId) async {
    final existing = await getProject(projectId);
    if (existing == null) throw Exception('پروژه یافت نشد.');
    if (existing.isFinalized) {
      throw Exception('پروژه نهایی‌شده قابل لغو نیست.');
    }
    if (existing.status == kProjectStatusCancelled) {
      return 0; // Idempotent: از قبل لغو شده، نیازی به نوشتن دوباره نیست
    }
    final db = await database;
    return db.update(
      'projects',
      existing.copyWith(status: kProjectStatusCancelled).toMap(),
      where: 'id = ?',
      whereArgs: [projectId],
    );
  }

  /// حذف فیزیکی پروژه فقط وقتی مجاز است که هیچ سند مالی یا رویداد تغییر
  /// قیمتی نداشته باشد؛ چون Price Event و اسناد مالی هرگز نباید Hard Delete
  /// شوند (طبق اصل حفظ تاریخچه مالی).
  Future<int> deleteProject(int id) async {
    final db = await database;
    final lineRows =
        await db.query('journal_lines', where: 'projectId = ?', whereArgs: [id], limit: 1);
    if (lineRows.isNotEmpty) {
      throw Exception(
          'این پروژه اسناد حسابداری ثبت‌شده دارد و برای حفظ سوابق مالی، قابل حذف فیزیکی نیست.');
    }
    final eventRows =
        await db.query('project_price_events', where: 'projectId = ?', whereArgs: [id], limit: 1);
    if (eventRows.isNotEmpty) {
      throw Exception(
          'این پروژه تاریخچه تغییر مبلغ دارد و برای حفظ سوابق مالی، قابل حذف فیزیکی نیست.');
    }
    return db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ProjectModel>> getProjects({int? counterpartyId, String? query}) async {
    final db = await database;
    String? where;
    List<Object?> args = [];
    if (counterpartyId != null) {
      where = 'counterpartyId = ?';
      args.add(counterpartyId);
    }
    if (query != null && query.isNotEmpty) {
      where = where == null ? 'title LIKE ?' : '$where AND title LIKE ?';
      args.add('%$query%');
    }
    final maps = await db.query('projects',
        where: where, whereArgs: args.isEmpty ? null : args, orderBy: 'id DESC');
    return maps.map((m) => ProjectModel.fromMap(m)).toList();
  }

  Future<ProjectModel?> getProject(int id, [DatabaseExecutor? executor]) async {
    final db = executor ?? await database;
    final maps = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return ProjectModel.fromMap(maps.first);
  }

  // ---------------- Accounts ----------------
  /// یک حساب کنترلی سیستمی هرگز نباید زیرحساب بگیرد - اگر بگیرد، دیگر
  /// «قابل ثبت» (Postable) نخواهد بود و تمام Workflowهای مالی که مستقیم به
  /// آن می‌نویسند (Finalization، Discount، Receipt و...) می‌شکنند. این
  /// بررسی مستقل از این‌که خودِ حساب سیستمی است یا نه اجرا می‌شود، چون خطر
  /// از سمت «حساب دیگری که این را به‌عنوان والد انتخاب می‌کند» هم می‌آید.
  Future<void> _rejectSystemAccountAsParent(int? parentId, [DatabaseExecutor? executor]) async {
    if (parentId == null) return;
    final parent = await getAccount(parentId, executor);
    if (parent != null && parent.isSystem && !parent.allowChildren) {
      throw Exception(
          'حساب «${parent.name}» یک حساب کنترلی سیستمی است و نمی‌تواند والد حساب دیگری باشد.');
    }
  }

  Future<int> insertAccount(AccountModel a, [DatabaseExecutor? executor]) async {
    await _rejectSystemAccountAsParent(a.parentId, executor);
    final db = executor ?? await database;
    return db.insert('accounts', a.toMap()..remove('id'));
  }

  /// محافظت لایه دیتابیس (نه فقط UI) برای حساب‌های سیستمی: صرف‌نظر از
  /// این‌که فراخوانی‌کننده چه مقداری پاس داده، برای یک حساب سیستمی موجود
  /// این فیلدها همیشه از مقدار فعلی دیتابیس حفظ می‌شوند: systemKey، isSystem،
  /// type (تغییر نوع، نقش سیستمی حساب را با ماهیت حسابداری‌اش ناسازگار
  /// می‌کند) و parentId (یک حساب کنترلی سیستمی هرگز نباید زیرمجموعه چیز
  /// دیگری شود).
  Future<int> updateAccount(AccountModel a) async {
    final db = await database;
    final existing = await getAccount(a.id!);
    if (existing != null && existing.isSystem) {
      final protectedMap = a.toMap()
        ..['systemKey'] = existing.systemKey
        ..['isSystem'] = 1
        ..['type'] = existing.type
        ..['parentId'] = existing.parentId
        ..['allowChildren'] = existing.allowChildren ? 1 : 0;
      return db.update('accounts', protectedMap, where: 'id = ?', whereArgs: [a.id]);
    }
    // حساب معمولی: اگر والد جدید یک حساب سیستمی Leaf-Locked باشد، رد
    // می‌شود (تا آن حساب سیستمی به‌طور ناخواسته non-postable نشود)
    await _rejectSystemAccountAsParent(a.parentId);
    return db.update('accounts', a.toMap(), where: 'id = ?', whereArgs: [a.id]);
  }

  /// حذف حساب؛ در صورت سیستمی بودن، داشتن زیرحساب یا داشتن سطر سند، خطا می‌دهد
  Future<void> deleteAccount(int id) async {
    final db = await database;
    final acc = await getAccount(id);
    if (acc == null) return;
    if (acc.isSystem) {
      throw Exception('این حساب پیش‌فرض سیستم است و قابل حذف نیست.');
    }
    final children = await db.query('accounts', where: 'parentId = ?', whereArgs: [id]);
    if (children.isNotEmpty) {
      throw Exception('ابتدا زیرحساب‌های این حساب را حذف یا منتقل کنید.');
    }
    final lines = await db.query('journal_lines', where: 'accountId = ?', whereArgs: [id], limit: 1);
    if (lines.isNotEmpty) {
      throw Exception('این حساب در اسناد حسابداری استفاده شده و قابل حذف نیست.');
    }
    await db.delete('accounts', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<AccountModel>> getAccounts({String? type, DatabaseExecutor? executor}) async {
    final db = executor ?? await database;
    final maps = type == null
        ? await db.query('accounts', orderBy: 'type ASC, code ASC')
        : await db.query('accounts',
            where: 'type = ?', whereArgs: [type], orderBy: 'code ASC');
    return maps.map((m) => AccountModel.fromMap(m)).toList();
  }

  /// حساب‌های «قابل ثبت» (بدون زیرحساب) — تنها این‌ها مطابق قانون مرکزی
  /// insertJournalEntry اجازه استفاده مستقیم در سند حسابداری را دارند.
  /// همه فرم‌های انتخاب حساب برای ثبت سند باید از همین متد استفاده کنند،
  /// نه از getAccounts خام، تا حساب‌های والد/گروه هرگز پیشنهاد نشوند.
  Future<List<AccountModel>> getPostableAccounts({String? type}) async {
    final all = await getAccounts(type: type);
    return all.where((a) => !all.any((x) => x.parentId == a.id)).toList();
  }

  Future<AccountModel?> getAccount(int id, [DatabaseExecutor? executor]) async {
    final db = executor ?? await database;
    final maps = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return AccountModel.fromMap(maps.first);
  }

  // ---------------- Journal (اسناد حسابداری) ----------------
  /// همه قوانین پایه Double-Entry + قوانین کسب‌وکار حساس (Overpayment سطح
  /// طرف‌حساب و سطح پروژه) را بررسی می‌کند و در صورت نقض Exception می‌دهد؛
  /// هیچ نوشتنی در دیتابیس انجام نمی‌دهد. با executor اختیاری، می‌تواند از
  /// داخل یک تراکنش بازِ دیگر (مثل finalizeProject) صدا زده شود.
  Future<void> _validateJournalEntry(JournalEntryModel entry, [DatabaseExecutor? executor]) async {
    // قانون ۴: حداقل دو سطر
    if (entry.lines.length < 2) {
      throw Exception('سند حسابداری باید حداقل دو سطر داشته باشد.');
    }

    // قانون ۲ و ۳: هر سطر دقیقاً یک طرف داشته باشد و منفی نباشد
    for (final line in entry.lines) {
      if (line.debit < 0 || line.credit < 0) {
        throw Exception('مبلغ بدهکار یا بستانکار نمی‌تواند منفی باشد.');
      }
      final hasDebit = line.debit > 0;
      final hasCredit = line.credit > 0;
      if (hasDebit && hasCredit) {
        throw Exception('هر سطر سند باید فقط یک طرف (بدهکار یا بستانکار) داشته باشد، نه هر دو.');
      }
      if (!hasDebit && !hasCredit) {
        throw Exception('هر سطر سند باید مبلغ بدهکار یا بستانکار معتبر (بزرگ‌تر از صفر) داشته باشد.');
      }
    }

    // قانون ۱ و ۵: توازن کل سند و رد سند صفر
    if (!entry.isBalanced) {
      if (entry.totalDebit == 0 && entry.totalCredit == 0) {
        throw Exception('سند حسابداری نمی‌تواند صفر باشد.');
      }
      throw Exception('سند حسابداری باید متوازن باشد (جمع بدهکار = جمع بستانکار).');
    }

    final db = executor ?? await database;

    // قانون ۶: هر حساب باید معتبر و «قابل ثبت» باشد (بدون زیرحساب)
    for (final line in entry.lines) {
      final accountRows =
          await db.query('accounts', where: 'id = ?', whereArgs: [line.accountId]);
      if (accountRows.isEmpty) {
        throw Exception('حساب انتخاب‌شده معتبر نیست.');
      }
      final childRows = await db.query('accounts',
          where: 'parentId = ?', whereArgs: [line.accountId], limit: 1);
      if (childRows.isNotEmpty) {
        throw Exception(
            'امکان ثبت سند مستقیم روی حساب «${accountRows.first['name']}» وجود ندارد، چون این حساب دارای زیرحساب است. لطفاً یک زیرحساب مشخص را انتخاب کنید.');
      }
    }

    // مرحله ۳.۲ - جلوگیری تجمیعی (نه تک‌سطری) از Overpayment در تسویه AR/AP
    // در سطح طرف‌حساب: چون یک سند می‌تواند چند سطر برای همان طرف حساب روی
    // همان حساب AR/AP داشته باشد، باید مجموع کاهش AR/AP همان سند برای هر
    // طرف حساب با مانده فعلی‌اش مقایسه شود؛ نه هر سطر به‌تنهایی.
    final arAccount = await getReceivableAccount(executor);
    final apAccount = await getPayableAccount(executor);

    final Map<int, int> arReductionByCounterparty = {};
    final Map<int, int> apReductionByCounterparty = {};
    // مرحله جدید (Financial Data Integrity Hardening، مورد ۸) - کنترل
    // Overpayment در سطح Project نیز؛ چون کنترل سطح طرف‌حساب به‌تنهایی کافی
    // نیست: اگر پروژه A مانده طلب ۱۰۰ دارد و پروژه B (همان طرف‌حساب) مانده
    // صفر، کنترل سطح طرف‌حساب اجازه می‌دهد ۵۰ از پروژه B دریافت شود (چون
    // ۵۰ ≤ ۱۰۰ مجموع طرف‌حساب)، در حالی که AR پروژه B باید مستقلاً بررسی و
    // رد شود. هر دو کنترل هم‌زمان و مستقل اعمال می‌شوند.
    final Map<int, int> arReductionByProject = {};
    final Map<int, int> apReductionByProject = {};
    for (final line in entry.lines) {
      if (arAccount != null && line.accountId == arAccount.id && line.credit > 0) {
        if (line.counterpartyId != null) {
          arReductionByCounterparty[line.counterpartyId!] =
              (arReductionByCounterparty[line.counterpartyId!] ?? 0) + line.credit;
        }
        if (line.projectId != null) {
          arReductionByProject[line.projectId!] =
              (arReductionByProject[line.projectId!] ?? 0) + line.credit;
        }
      }
      if (apAccount != null && line.accountId == apAccount.id && line.debit > 0) {
        if (line.counterpartyId != null) {
          apReductionByCounterparty[line.counterpartyId!] =
              (apReductionByCounterparty[line.counterpartyId!] ?? 0) + line.debit;
        }
        if (line.projectId != null) {
          apReductionByProject[line.projectId!] =
              (apReductionByProject[line.projectId!] ?? 0) + line.debit;
        }
      }
    }

    for (final counterpartyId in arReductionByCounterparty.keys) {
      final totalReduction = arReductionByCounterparty[counterpartyId]!;
      final currentBalance = await receivableBalance(counterpartyId, executor);
      if (totalReduction > currentBalance) {
        throw Exception(
            'مجموع مبلغ دریافت (${formatMoney(totalReduction)}) از مانده طلب فعلی این طرف حساب (${formatMoney(currentBalance)}) بیشتر است؛ عملیات ثبت نشد.');
      }
    }
    for (final counterpartyId in apReductionByCounterparty.keys) {
      final totalReduction = apReductionByCounterparty[counterpartyId]!;
      final currentBalance = await payableBalance(counterpartyId, executor);
      if (totalReduction > currentBalance) {
        throw Exception(
            'مجموع مبلغ پرداخت (${formatMoney(totalReduction)}) از مانده بدهی فعلی این طرف حساب (${formatMoney(currentBalance)}) بیشتر است؛ عملیات ثبت نشد.');
      }
    }
    for (final projectId in arReductionByProject.keys) {
      final totalReduction = arReductionByProject[projectId]!;
      final currentBalance = await projectReceivableBalance(projectId, executor);
      if (totalReduction > currentBalance) {
        throw Exception(
            'مجموع مبلغ دریافت (${formatMoney(totalReduction)}) از مانده طلب فعلی این پروژه (${formatMoney(currentBalance)}) بیشتر است؛ عملیات ثبت نشد.');
      }
    }
    for (final projectId in apReductionByProject.keys) {
      final totalReduction = apReductionByProject[projectId]!;
      final currentBalance = await projectPayableBalance(projectId, executor);
      if (totalReduction > currentBalance) {
        throw Exception(
            'مجموع مبلغ پرداخت (${formatMoney(totalReduction)}) از مانده بدهی فعلی این پروژه (${formatMoney(currentBalance)}) بیشتر است؛ عملیات ثبت نشد.');
      }
    }
  }

  /// درج خام هدر سند و سطرهایش - بدون هیچ اعتبارسنجی (باید قبلش با
  /// _validateJournalEntry بررسی شده باشد). executor باید یک Transaction باز
  /// باشد تا اتمیک بودن واقعی چند سند/عملیات مرتبط تضمین شود.
  Future<int> _writeJournalEntryRaw(DatabaseExecutor executor, JournalEntryModel entry) async {
    final entryId = await executor.insert('journal_entries', entry.toMap()..remove('id'));
    for (final line in entry.lines) {
      final map = line.toMap()
        ..remove('id')
        ..['entryId'] = entryId;
      await executor.insert('journal_lines', map);
    }
    return entryId;
  }

  /// نقطه مرکزی و تنها مسیر مجاز برای ثبت سند حسابداری در کل برنامه.
  /// تمام قوانین پایه Double-Entry اینجا enforce می‌شوند تا هیچ مسیر دیگری
  /// (فرم سریع، سند دستی، بازیابی پشتیبان، پیش‌نویس پیامکی) نتواند آن‌ها را
  /// دور بزند.
  Future<int> insertJournalEntry(JournalEntryModel entry, [DatabaseExecutor? executor]) async {
    await _validateJournalEntry(entry, executor);
    if (executor != null) {
      // یک تراکنش والد (مثلاً Restore اتمیک) از قبل باز است؛ نباید تراکنش
      // تودرتوی جدید باز کنیم (باعث Deadlock در sqflite می‌شود) - مستقیم
      // با همان executor بنویس.
      return _writeJournalEntryRaw(executor, entry);
    }
    // ثبت اتمیک: هدر سند و همه سطرهایش در یک تراکنش دیتابیس - در صورت بروز
    // هر خطا (مثلاً نقض یکی از CHECK constraint های سطح دیتابیس)، کل عملیات
    // rollback می‌شود و نه هدر ناقص باقی می‌ماند و نه سطر یتیم.
    final db = await database;
    return db.transaction((txn) => _writeJournalEntryRaw(txn, entry));
  }

  /// wrapper صریح برای ثبت سند دستی/فرم سریع معمولی - صرف‌نظر از این‌که
  /// entry ورودی چه source ای داشته باشد، همیشه kJournalSourceManual را
  /// enforce می‌کند. هدف: جلوگیری از فراموشی تصادفی تنظیم source که باعث
  /// می‌شد یک سند دستی به‌جای «قابل حذف»، به‌اشتباه «legacy/محافظت‌شده»
  /// طبقه‌بندی شود (طبق semantics جدید NULL=محافظت‌شده).
  Future<int> createManualJournal(JournalEntryModel entry) {
    return insertJournalEntry(JournalEntryModel(
      date: entry.date,
      description: entry.description,
      createdAt: entry.createdAt,
      lines: entry.lines,
      source: kJournalSourceManual,
    ));
  }

  /// wrapper صریح برای ثبت سند سیستمی - صرف‌نظر از source ورودی، همیشه
  /// kJournalSourceSystem را enforce می‌کند. برای Workflowهای مالی
  /// ساختاریافته (Finalization/Discount/Final Adjustment/Project Payment)
  /// که خودشان با _validateJournalEntry/_writeJournalEntryRaw داخل یک
  /// Transaction عمل می‌کنند، همین enforcement مستقیماً روی JournalEntryModel
  /// ساخته‌شده اعمال شده (رجوع به finalizeProject و مشابه)؛ این wrapper برای
  /// مسیرهای احتمالی آینده‌ای است که مستقیم از insertJournalEntry عبور کنند.
  Future<int> createSystemJournal(JournalEntryModel entry) {
    return insertJournalEntry(JournalEntryModel(
      date: entry.date,
      description: entry.description,
      createdAt: entry.createdAt,
      lines: entry.lines,
      source: kJournalSourceSystem,
    ));
  }

  /// حذف فیزیکی سند حسابداری. طبق الزام Financial Data Integrity، فقط
  /// سندی که صراحتاً source == manual دارد قابل حذف است. سندهای system و
  /// همچنین سندهای با source نامشخص/NULL (که ممکن است سندهای قدیمی‌تر از
  /// افزودن این مکانیزم و واقعاً System-generated بوده باشند) محافظه‌کارانه
  /// غیرقابل‌حذف تلقی می‌شوند - حدس زده نمی‌شود. برای اصلاح چنین سندی، راه
  /// صحیح ثبت یک سند اصلاحی/معکوس مستقل است، نه حذف.
  Future<void> deleteJournalEntry(int id) async {
    final db = await database;
    final rows = await db.query('journal_entries', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) return;
    final entry = JournalEntryModel.fromMap(rows.first);
    if (!entry.isDeletable) {
      throw Exception(entry.isSystemGenerated
          ? 'این سند توسط یک عملیات مالی ساختاریافته سیستم ایجاد شده و برای حفظ یکپارچگی حساب‌ها قابل حذف نیست. برای اصلاح، از ثبت یک سند اصلاحی مستقل استفاده کنید.'
          : 'منشأ این سند به‌صراحت مشخص نیست (احتمالاً سندی قدیمی)؛ برای حفظ یکپارچگی حساب‌ها، محافظه‌کارانه قابل حذف نیست. برای اصلاح، از ثبت یک سند اصلاحی مستقل استفاده کنید.');
    }
    await db.transaction((txn) async {
      await txn.delete('journal_lines', where: 'entryId = ?', whereArgs: [id]);
      await txn.delete('journal_entries', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<JournalEntryModel>> getJournalEntries({
    int? projectId,
    int? accountId,
    String? fromDate,
    String? toDate,
  }) async {
    final db = await database;
    String where = '1=1';
    List<Object?> args = [];
    if (fromDate != null) {
      where += ' AND date >= ?';
      args.add(fromDate);
    }
    if (toDate != null) {
      where += ' AND date <= ?';
      args.add(toDate);
    }
    if (projectId != null || accountId != null) {
      String lineWhere = 'entryId = journal_entries.id';
      if (projectId != null) {
        lineWhere += ' AND projectId = ?';
        args.add(projectId);
      }
      if (accountId != null) {
        lineWhere += ' AND accountId = ?';
        args.add(accountId);
      }
      where += ' AND EXISTS (SELECT 1 FROM journal_lines WHERE $lineWhere)';
    }
    final entryMaps = await db.query('journal_entries',
        where: where, whereArgs: args, orderBy: 'date DESC, id DESC');

    final entries = <JournalEntryModel>[];
    for (final em in entryMaps) {
      final lineMaps = await db.query('journal_lines',
          where: 'entryId = ?', whereArgs: [em['id']], orderBy: 'id ASC');
      final lines = lineMaps.map((m) => JournalLineModel.fromMap(m)).toList();
      entries.add(JournalEntryModel.fromMap(em, lines: lines));
    }
    return entries;
  }

  Future<JournalEntryModel?> getJournalEntry(int id) async {
    final db = await database;
    final maps = await db.query('journal_entries', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    final lineMaps =
        await db.query('journal_lines', where: 'entryId = ?', whereArgs: [id], orderBy: 'id ASC');
    final lines = lineMaps.map((m) => JournalLineModel.fromMap(m)).toList();
    return JournalEntryModel.fromMap(maps.first, lines: lines);
  }

  /// سطرهای دفتر یک حساب به همراه تاریخ و شرح سند، برای نمایش دفتر معین/کل
  Future<List<Map<String, dynamic>>> getLedgerLines(int accountId,
      {String? fromDate, String? toDate}) async {
    final db = await database;
    String where = 'l.accountId = ?';
    List<Object?> args = [accountId];
    if (fromDate != null) {
      where += ' AND e.date >= ?';
      args.add(fromDate);
    }
    if (toDate != null) {
      where += ' AND e.date <= ?';
      args.add(toDate);
    }
    return db.rawQuery('''
      SELECT l.id as lineId, l.debit, l.credit, l.description as lineDescription,
             e.id as entryId, e.date, e.description as entryDescription, l.projectId
      FROM journal_lines l
      JOIN journal_entries e ON e.id = l.entryId
      WHERE $where
      ORDER BY e.date ASC, e.id ASC, l.id ASC
    ''', args);
  }

  /// مانده هر حساب: {debit, credit, balance} — balance با توجه به نوع حساب محاسبه می‌شود
  Future<Map<String, double>> accountBalance(int accountId,
      {String? fromDate, String? toDate}) async {
    final db = await database;
    String where = 'accountId = ?';
    List<Object?> args = [accountId];
    if (fromDate != null) {
      where +=
          ' AND entryId IN (SELECT id FROM journal_entries WHERE date >= ?)';
      args.add(fromDate);
    }
    if (toDate != null) {
      where += ' AND entryId IN (SELECT id FROM journal_entries WHERE date <= ?)';
      args.add(toDate);
    }
    final result = await db.rawQuery(
        'SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c FROM journal_lines WHERE $where',
        args);
    final d = (result.first['d'] as num).toDouble();
    final c = (result.first['c'] as num).toDouble();
    final account = await getAccount(accountId);
    final debitNormal = account == null ? true : isDebitNormal(account.type);
    return {
      'debit': d,
      'credit': c,
      'balance': debitNormal ? d - c : c - d,
    };
  }

  /// تراز آزمایشی همه حساب‌ها
  Future<List<Map<String, dynamic>>> trialBalance({String? fromDate, String? toDate}) async {
    final accounts = await getAccounts();
    final result = <Map<String, dynamic>>[];
    for (final acc in accounts) {
      final bal = await accountBalance(acc.id!, fromDate: fromDate, toDate: toDate);
      result.add({'account': acc, ...bal});
    }
    return result;
  }

  /// دریافتی/هزینه یک پروژه بر اساس سطرهای برچسب‌خورده به آن
  /// دریافتی/پرداختی واقعی یک پروژه — بر اساس حرکت واقعی وجه نقد تگ‌خورده با
  /// همان پروژه، نه شناسایی درآمد/هزینه. مرحله ۳.۱ (اصلاح ۴): مثلاً «ایجاد
  /// طلب ۱۰۰ میلیونی» برای پروژه باعث می‌شود received=۰ بماند تا زمانی که
  /// واقعاً دریافتی ثبت شود؛ فیلتر بر اساس projectId مستقل از Counterparty
  /// باقی می‌ماند - تراکنشی که فقط به طرف حساب برچسب خورده و پروژه ندارد،
  /// به هیچ پروژه‌ای نسبت داده نمی‌شود.
  Future<Map<String, double>> projectFinancials(int projectId) async {
    final db = await database;
    final cashAccounts = await getCashAccounts();
    if (cashAccounts.isEmpty) return {'received': 0, 'spent': 0};

    final placeholders = List.filled(cashAccounts.length, '?').join(',');
    final cashIds = cashAccounts.map((a) => a.id).toList();

    final receivedResult = await db.rawQuery('''
      SELECT COALESCE(SUM(debit),0) as total
      FROM journal_lines WHERE projectId = ? AND accountId IN ($placeholders)
    ''', [projectId, ...cashIds]);
    final spentResult = await db.rawQuery('''
      SELECT COALESCE(SUM(credit),0) as total
      FROM journal_lines WHERE projectId = ? AND accountId IN ($placeholders)
    ''', [projectId, ...cashIds]);
    return {
      'received': (receivedResult.first['total'] as num).toDouble(),
      'spent': (spentResult.first['total'] as num).toDouble(),
    };
  }

  // ---------------- Accounts Receivable / Accounts Payable (مرحله ۳) ----------------

  /// حساب کنترلی «حساب‌های دریافتنی» را از روی شناسه پایدار systemKey می‌یابد
  /// (نه جستجوی نام که شکننده است) - از حساب‌های پیش‌فرض seed‌شده استفاده
  /// می‌شود؛ حساب جدید ساخته نمی‌شود. پارامتر executor اختیاری: وقتی این
  /// متد از داخل یک تراکنش دیتابیس دیگر (مثل finalizeProject) صدا زده
  /// می‌شود، باید از همان Transaction استفاده کند، نه یک اتصال مستقل جدید -
  /// در غیر این صورت SQLite/sqflite در تراکنش تودرتو قفل می‌کند.
  Future<AccountModel?> getReceivableAccount([DatabaseExecutor? executor]) async {
    final db = executor ?? await database;
    final maps =
        await db.query('accounts', where: 'systemKey = ?', whereArgs: [kSystemKeyReceivable]);
    if (maps.isEmpty) return null;
    return AccountModel.fromMap(maps.first);
  }

  /// حساب کنترلی «حساب‌های پرداختنی» از روی شناسه پایدار systemKey
  Future<AccountModel?> getPayableAccount([DatabaseExecutor? executor]) async {
    final db = executor ?? await database;
    final maps = await db.query('accounts', where: 'systemKey = ?', whereArgs: [kSystemKeyPayable]);
    if (maps.isEmpty) return null;
    return AccountModel.fromMap(maps.first);
  }

  Future<AccountModel?> _accountBySystemKey(String key, [DatabaseExecutor? executor]) async {
    final db = executor ?? await database;
    final maps = await db.query('accounts', where: 'systemKey = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return AccountModel.fromMap(maps.first);
  }

  Future<AccountModel?> getCustomerAdvanceAccount([DatabaseExecutor? executor]) =>
      _accountBySystemKey(kSystemKeyCustomerAdvance, executor);
  Future<AccountModel?> getCustomerCreditAccount([DatabaseExecutor? executor]) =>
      _accountBySystemKey(kSystemKeyCustomerCredit, executor);
  Future<AccountModel?> getProjectRevenueAccount([DatabaseExecutor? executor]) =>
      _accountBySystemKey(kSystemKeyProjectRevenue, executor);
  Future<AccountModel?> getProjectOverheadAccount([DatabaseExecutor? executor]) =>
      _accountBySystemKey(kSystemKeyProjectOverhead, executor);
  Future<AccountModel?> getDirectProjectCostAccount([DatabaseExecutor? executor]) =>
      _accountBySystemKey(kSystemKeyDirectProjectCost, executor);
  Future<AccountModel?> getServiceDiscountAccount([DatabaseExecutor? executor]) =>
      _accountBySystemKey(kSystemKeyServiceDiscount, executor);

  /// ساخت سطرهای بستانکار برای اعمال مبلغی به AR یک پروژه مشخص، با محافظت
  /// در برابر Overpayment: اگر مبلغ از مانده فعلی AR همان پروژه بیشتر باشد
  /// (مثلاً چون پیش‌دریافت یا دریافت مستقیم بیشتر از طلب واقعی بوده)، فقط
  /// به‌اندازه مانده به AR اعمال می‌شود و مازاد به‌جای منفی‌کردن AR، به حساب
  /// «بستانکاری مشتری (مازاد دریافتی)» می‌رود - ماهیت این مازاد را کاربر
  /// بعداً به‌صورت صریح مشخص می‌کند، سیستم آن را حدس نمی‌زند.
  Future<List<JournalLineModel>> _creditArWithOverflowGuard({
    required int projectId,
    required int counterpartyId,
    required int arAccountId,
    required double amount,
    DatabaseExecutor? executor,
  }) async {
    final currentAr = await projectReceivableBalance(projectId, executor);
    final toAr = amount <= currentAr ? amount : currentAr;
    final excess = amount - toAr;
    final lines = <JournalLineModel>[];
    if (toAr > 0) {
      lines.add(JournalLineModel(
          accountId: arAccountId,
          credit: toAr.round(),
          projectId: projectId,
          counterpartyId: counterpartyId));
    }
    if (excess > 0) {
      final creditAccount = await getCustomerCreditAccount(executor);
      if (creditAccount == null) {
        throw Exception('حساب «بستانکاری مشتری» برای ثبت مازاد دریافتی یافت نشد.');
      }
      lines.add(JournalLineModel(
          accountId: creditAccount.id!,
          credit: excess.round(),
          projectId: projectId,
          counterpartyId: counterpartyId));
    }
    return lines;
  }

  /// مانده یک حساب کنترلی (AR/Advance/...) برای یک پروژه مشخص - مستقیم از
  /// Ledger، با فیلتر projectId (نه counterpartyId) چون هدف مانده مختص همین
  /// پروژه است، نه کل طرف حساب.
  Future<double> _projectControlAccountBalance(int projectId, AccountModel? account,
      {required bool debitNormal, DatabaseExecutor? executor}) async {
    if (account == null) return 0;
    final db = executor ?? await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c
      FROM journal_lines WHERE accountId = ? AND projectId = ?
    ''', [account.id, projectId]);
    final d = (result.first['d'] as num).toDouble();
    final c = (result.first['c'] as num).toDouble();
    return debitNormal ? d - c : c - d;
  }

  /// مانده مطالبات (AR) مختص یک پروژه خاص (نه کل طرف حساب)
  Future<double> projectReceivableBalance(int projectId, [DatabaseExecutor? executor]) async {
    return _projectControlAccountBalance(projectId, await getReceivableAccount(executor),
        debitNormal: true, executor: executor);
  }

  /// مانده پیش‌دریافت (Customer Advance) مختص یک پروژه خاص
  Future<double> projectAdvanceBalance(int projectId, [DatabaseExecutor? executor]) async {
    return _projectControlAccountBalance(projectId, await getCustomerAdvanceAccount(executor),
        debitNormal: false, executor: executor);
  }

  /// مانده بستانکاری مشتری (مازاد دریافتی ناشی از Overpayment) مختص یک پروژه
  Future<double> projectCustomerCreditBalance(int projectId, [DatabaseExecutor? executor]) async {
    return _projectControlAccountBalance(projectId, await getCustomerCreditAccount(executor),
        debitNormal: false, executor: executor);
  }

  /// مانده بدهی (AP) مختص یک پروژه خاص (نه کل طرف حساب) - برای کنترل
  /// Overpayment سطح پروژه در پرداخت بدهی مرتبط با یک پروژه مشخص
  Future<double> projectPayableBalance(int projectId, [DatabaseExecutor? executor]) async {
    return _projectControlAccountBalance(projectId, await getPayableAccount(executor),
        debitNormal: false, executor: executor);
  }

  /// مانده واقعی حساب «درآمد پروژه‌ها» مختص یک پروژه - برای Reconciliation
  /// (مقایسه با مقدار محاسبه‌شده از finalAmount + FINAL_ADJUSTMENTها)
  Future<double> projectRevenueLedgerBalance(int projectId) async {
    return _projectControlAccountBalance(projectId, await getProjectRevenueAccount(),
        debitNormal: false);
  }

  /// آیا این حساب یا یکی از والدینش (تا هر عمقی) صندوق/بانک است؟ با این
  /// پیمایش، زیرحساب‌های سفارشی بانک (مثل «بانک ملت») هم بدون نیاز به
  /// تگ‌گذاری صریح جداگانه، به‌درستی نقدی/بانکی شناسایی می‌شوند.
  bool _isCashOrBankAccount(AccountModel account, List<AccountModel> allInType) {
    AccountModel? current = account;
    while (current != null) {
      if (current.systemKey == kSystemKeyCash || current.systemKey == kSystemKeyBank) return true;
      if (current.parentId == null) return false;
      final parentId = current.parentId;
      final matches = allInType.where((a) => a.id == parentId);
      current = matches.isNotEmpty ? matches.first : null;
    }
    return false;
  }

  /// حساب‌های واقعاً نقد/بانکی برای انتخاب‌گر دریافت/پرداخت وجه - نه هر
  /// حساب دارایی. بر پایه شناسه پایدار systemKey (cash/bank) به‌همراه پیمایش
  /// زنجیره والدین است، نه فهرست سیاه یک حساب خاص؛ این‌طوری دارایی‌های
  /// دیگری که بعداً اضافه شوند (سرقفلی، تجهیزات، سپرده، پیش‌پرداخت و...)
  /// به‌طور پیش‌فرض نقدی/بانکی محسوب نمی‌شوند مگر واقعاً زیرمجموعه صندوق/بانک باشند.
  Future<List<AccountModel>> getCashAccounts() async {
    final allAssets = await getAccounts(type: kAccountAsset); // برای پیمایش زنجیره والد لازم است
    final postable = allAssets.where((a) => !allAssets.any((x) => x.parentId == a.id)).toList();
    return postable.where((a) => _isCashOrBankAccount(a, allAssets)).toList();
  }

  /// مانده مطالبات (AR) یک طرف حساب خاص - همیشه مستقیم از Ledger محاسبه
  /// می‌شود (بدون هیچ مقدار ذخیره‌شده جداگانه)؛ طبق ماهیت بدهکار حساب دارایی:
  /// جمع بدهکارها منهای جمع بستانکارهای همان حساب برای همان طرف حساب.
  Future<double> receivableBalance(int counterpartyId, [DatabaseExecutor? executor]) async {
    final arAccount = await getReceivableAccount(executor);
    if (arAccount == null) return 0;
    final db = executor ?? await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c
      FROM journal_lines WHERE accountId = ? AND counterpartyId = ?
    ''', [arAccount.id, counterpartyId]);
    final d = (result.first['d'] as num).toDouble();
    final c = (result.first['c'] as num).toDouble();
    return d - c;
  }

  /// مانده بدهی (AP) یک طرف حساب خاص - طبق ماهیت بستانکار حساب بدهی:
  /// جمع بستانکارها منهای جمع بدهکارهای همان حساب برای همان طرف حساب.
  Future<double> payableBalance(int counterpartyId, [DatabaseExecutor? executor]) async {
    final apAccount = await getPayableAccount(executor);
    if (apAccount == null) return 0;
    final db = executor ?? await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c
      FROM journal_lines WHERE accountId = ? AND counterpartyId = ?
    ''', [apAccount.id, counterpartyId]);
    final d = (result.first['d'] as num).toDouble();
    final c = (result.first['c'] as num).toDouble();
    return c - d;
  }

  /// مانده پیش‌دریافت یک طرف حساب در کل (نه فقط یک پروژه خاص) - شامل هر
  /// سطری که مستقیم با این طرف حساب مرتبط باشد، صرف‌نظر از این‌که به پروژه
  /// خاصی تگ خورده باشد یا نه.
  Future<double> counterpartyAdvanceBalance(int counterpartyId) async {
    final account = await getCustomerAdvanceAccount();
    if (account == null) return 0;
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c
      FROM journal_lines WHERE accountId = ? AND counterpartyId = ?
    ''', [account.id, counterpartyId]);
    final d = (result.first['d'] as num).toDouble();
    final c = (result.first['c'] as num).toDouble();
    return c - d;
  }

  /// مانده بستانکاری مشتری (مازاد دریافتی) یک طرف حساب در کل - شامل هر
  /// سطری که مستقیم با این طرف حساب مرتبط باشد، حتی اگر به پروژه خاصی
  /// تگ نخورده باشد (بر خلاف نسخه سطح-پروژه که فقط projectId فیلتر می‌کند).
  Future<double> counterpartyCustomerCreditBalance(int counterpartyId) async {
    final account = await getCustomerCreditAccount();
    if (account == null) return 0;
    final db = await database;
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c
      FROM journal_lines WHERE accountId = ? AND counterpartyId = ?
    ''', [account.id, counterpartyId]);
    final d = (result.first['d'] as num).toDouble();
    final c = (result.first['c'] as num).toDouble();
    return c - d;
  }

  /// دریافتی/پرداختی یک طرف حساب — هم از راه پروژه‌های او، هم از سندهایی که
  /// مستقیم (بدون پروژه) به او برچسب خورده‌اند
  /// دریافتی/پرداختی واقعی یک طرف حساب — بر اساس حرکت واقعی وجه نقد (بدهکار/
  /// بستانکار شدن حساب‌های نقد/بانکی)، نه شناسایی درآمد/هزینه. مرحله ۳.۱
  /// (اصلاح ۳): Revenue ≠ Received و Expense ≠ Paid. برای مثال «ایجاد طلب»
  /// اصلاً به این حساب‌ها دست نمی‌زند (Received=0)، فقط «دریافت طلب» یا
  /// «فروش نقدی» که واقعاً پول به صندوق/بانک می‌آورند در Received می‌آیند.
  Future<Map<String, double>> counterpartyFinancials(int counterpartyId) async {
    final db = await database;
    final cashAccounts = await getCashAccounts();
    if (cashAccounts.isEmpty) return {'received': 0, 'spent': 0};

    final placeholders = List.filled(cashAccounts.length, '?').join(',');
    final cashIds = cashAccounts.map((a) => a.id).toList();

    final receivedResult = await db.rawQuery('''
      SELECT COALESCE(SUM(debit),0) as total
      FROM journal_lines
      WHERE accountId IN ($placeholders) AND (counterpartyId = ? OR projectId IN (SELECT id FROM projects WHERE counterpartyId = ?))
    ''', [...cashIds, counterpartyId, counterpartyId]);
    final spentResult = await db.rawQuery('''
      SELECT COALESCE(SUM(credit),0) as total
      FROM journal_lines
      WHERE accountId IN ($placeholders) AND (counterpartyId = ? OR projectId IN (SELECT id FROM projects WHERE counterpartyId = ?))
    ''', [...cashIds, counterpartyId, counterpartyId]);
    return {
      'received': (receivedResult.first['total'] as num).toDouble(),
      'spent': (spentResult.first['total'] as num).toDouble(),
    };
  }

  /// اسناد ثبت‌شده مستقیم برای یک طرف حساب (بدون واسطه پروژه)
  Future<List<JournalEntryModel>> getDirectCounterpartyEntries(int counterpartyId) async {
    final db = await database;
    final entryMaps = await db.rawQuery('''
      SELECT DISTINCT e.* FROM journal_entries e
      JOIN journal_lines l ON l.entryId = e.id
      WHERE l.counterpartyId = ?
      ORDER BY e.date DESC, e.id DESC
    ''', [counterpartyId]);
    final entries = <JournalEntryModel>[];
    for (final em in entryMaps) {
      final lineMaps = await db.query('journal_lines',
          where: 'entryId = ?', whereArgs: [em['id']], orderBy: 'id ASC');
      final lines = lineMaps.map((m) => JournalLineModel.fromMap(m)).toList();
      entries.add(JournalEntryModel.fromMap(em, lines: lines));
    }
    return entries;
  }

  /// خلاصه دریافتی/پرداختی همه طرف‌های حساب، برای گزارش «مطالبات و بدهی‌ها»
  Future<List<Map<String, dynamic>>> allCounterpartiesFinancialSummary() async {
    final counterparties = await getCounterparties(includeInactive: true);
    final result = <Map<String, dynamic>>[];
    for (final c in counterparties) {
      final fin = await counterpartyFinancials(c.id!);
      result.add({'counterparty': c, 'received': fin['received']!, 'spent': fin['spent']!});
    }
    return result;
  }

  /// خلاصه داشبورد
  Future<Map<String, double>> dashboardSummary() async {
    final db = await database;

    Future<double> sumByType(String type, bool debitNormal) async {
      final result = await db.rawQuery('''
        SELECT COALESCE(SUM(l.debit),0) as d, COALESCE(SUM(l.credit),0) as c
        FROM journal_lines l JOIN accounts a ON a.id = l.accountId
        WHERE a.type = ?
      ''', [type]);
      final d = (result.first['d'] as num).toDouble();
      final c = (result.first['c'] as num).toDouble();
      return debitNormal ? d - c : c - d;
    }

    final assetBalance = await sumByType(kAccountAsset, true);
    final liabilityBalance = await sumByType(kAccountLiability, false);
    final equityBalance = await sumByType(kAccountEquity, false);
    final income = await sumByType(kAccountIncome, false);
    final expense = await sumByType(kAccountExpense, true);

    return {
      'assetBalance': assetBalance,
      'liabilityBalance': liabilityBalance,
      'equityBalance': equityBalance,
      'netWorth': assetBalance - liabilityBalance,
      'income': income,
      'expense': expense,
      'netProfit': income - expense,
    };
  }

  /// توزیع مانده حساب‌های هزینه (برای نمودار)، در بازه تاریخ اختیاری
  Future<Map<String, double>> expenseBreakdown({String? fromDate, String? toDate}) {
    return accountTypeBreakdown(kAccountExpense, fromDate: fromDate, toDate: toDate);
  }

  /// مانده هر حساب یک نوع خاص در بازه تاریخ اختیاری، برای فهرست‌کردن ردیف‌های
  /// صورت سود و زیان (درآمدها/هزینه‌ها). توجه: accountBalance فقط سطرهای متصل
  /// مستقیم به همان حساب را جمع می‌زند، پس شامل کردن حساب‌های والد هم امن است
  /// و باعث نمی‌شود مبلغی دوبار شمرده شود.
  Future<Map<String, double>> accountTypeBreakdown(
    String type, {
    String? fromDate,
    String? toDate,
    bool includeZero = false,
  }) async {
    final typeAccounts = await getAccounts(type: type);
    final Map<String, double> breakdown = {};
    for (final acc in typeAccounts) {
      final bal = await accountBalance(acc.id!, fromDate: fromDate, toDate: toDate);
      final balance = bal['balance']!;
      if (balance != 0 || includeZero) breakdown[acc.name] = balance;
    }
    return breakdown;
  }

  /// موجودی بانک‌ها به تفکیک زیرحساب: اگر حساب «بانک» زیرحساب داشته باشد
  /// (مثلاً بانک ملی، بانک صادرات)، هرکدام جداگانه برگردانده می‌شود؛
  /// در غیر این صورت خود حساب «بانک» به‌عنوان یک ردیف برگردانده می‌شود.
  Future<List<Map<String, dynamic>>> bankBalances() async {
    final assetAccounts = await getAccounts(type: kAccountAsset);
    final bankRoots = assetAccounts.where((a) => a.parentId == null && a.name.contains('بانک'));
    final result = <Map<String, dynamic>>[];
    for (final root in bankRoots) {
      final children = assetAccounts.where((a) => a.parentId == root.id).toList();
      if (children.isEmpty) {
        final bal = await accountBalance(root.id!);
        result.add({'name': root.name, 'balance': bal['balance']!});
      } else {
        for (final c in children) {
          final bal = await accountBalance(c.id!);
          result.add({'name': c.name, 'balance': bal['balance']!});
        }
      }
    }
    return result;
  }

  /// مانده حساب‌های دارایی که نام‌شان شامل کلمه کلیدی است (مثلاً «بانک» یا «صندوق»)
  /// برای جمع کردن چند حساب بانکی/صندوق احتمالی
  Future<double> assetBalanceByKeyword(String keyword) async {
    final accounts = await getAccounts(type: kAccountAsset);
    final matches = accounts.where((a) => a.name.contains(keyword));
    double total = 0;
    for (final a in matches) {
      final bal = await accountBalance(a.id!);
      total += bal['balance']!;
    }
    return total;
  }

  /// جمع مانده تمام حساب‌های یک نوع در بازه تاریخ اختیاری (برای درآمد/هزینه امروز یا هفته)
  Future<double> totalAccountTypeBalance(String type, {String? fromDate, String? toDate}) async {
    final accounts = await getAccounts(type: type);
    double total = 0;
    for (final a in accounts) {
      final bal = await accountBalance(a.id!, fromDate: fromDate, toDate: toDate);
      total += bal['balance']!;
    }
    return total;
  }

  /// سود/زیان خالص یک بازه تاریخ (درآمد منهای هزینه)
  Future<double> netProfitForRange({String? fromDate, String? toDate}) async {
    final income = await totalAccountTypeBalance(kAccountIncome, fromDate: fromDate, toDate: toDate);
    final expense = await totalAccountTypeBalance(kAccountExpense, fromDate: fromDate, toDate: toDate);
    return income - expense;
  }

  // ---------------- تنظیمات برنامه (کلید-مقدار) ----------------
  Future<void> setSetting(String key, String value, [DatabaseExecutor? executor]) async {
    final db = executor ?? await database;
    await db.insert('app_settings', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final maps = await db.query('app_settings', where: 'key = ?', whereArgs: [key]);
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }

  /// همه تنظیمات کلید-مقدار (سال مالی، قفل امنیتی، پیامک بانکی و...) —
  /// برای گنجاندن در فایل پشتیبان کامل
  Future<Map<String, String>> getAllSettings() async {
    final db = await database;
    final maps = await db.query('app_settings');
    return {for (final m in maps) m['key'] as String: m['value'] as String? ?? ''};
  }

  /// کلیدهای تنظیمات با ماهیت امنیتی/حساس - این‌ها هرگز نباید در فایل
  /// پشتیبان عادی صادر شوند (رجوع به BackupService.exportToFile) و حتی اگر
  /// به هر دلیلی (فایل پشتیبان قدیمی یا دستکاری‌شده) در ورودی Restore
  /// حضور داشته باشند، به‌صورت دفاعی این‌جا هم نادیده گرفته می‌شوند تا
  /// Restore هرگز نتواند قفل امنیتی فعلی دستگاه مقصد را تغییر دهد.
  static const List<String> kSecuritySettingKeys = ['pin_hash', 'lock_enabled', 'biometric_enabled'];

  Future<void> setAllSettings(Map<String, String> settings, [DatabaseExecutor? executor]) async {
    for (final entry in settings.entries) {
      if (kSecuritySettingKeys.contains(entry.key)) continue;
      await setSetting(entry.key, entry.value, executor);
    }
  }

  // ---------------- سال مالی ----------------
  Future<bool> isFiscalYearConfigured() async {
    return (await getSetting('fy_start_month')) != null;
  }

  Future<void> setFiscalYearStart(int month, int day) async {
    await setSetting('fy_start_month', month.toString());
    await setSetting('fy_start_day', day.toString());
  }

  /// روز و ماه شروع سال مالی (پیش‌فرض ۱ فروردین تا زمانی که کاربر تنظیم نکرده)
  Future<Map<String, int>> getFiscalYearStart() async {
    final m = await getSetting('fy_start_month');
    final d = await getSetting('fy_start_day');
    return {
      'month': m != null ? int.parse(m) : 1,
      'day': d != null ? int.parse(d) : 1,
    };
  }

  // ---------------- فرستنده‌های مجاز پیامک بانکی (چند بانک) ----------------
  Future<List<String>> getAllowedSmsSenders() async {
    // سازگاری با نسخه قبلی که فقط یک فرستنده تک ذخیره می‌کرد
    final legacy = await getSetting('sms_allowed_sender');
    final value = await getSetting('sms_allowed_senders');
    if (value == null || value.trim().isEmpty) {
      if (legacy != null && legacy.trim().isNotEmpty) return [legacy.trim()];
      return [];
    }
    return value.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  }

  Future<void> setAllowedSmsSenders(List<String> senders) async {
    await setSetting('sms_allowed_senders', senders.join('|'));
  }

  // ---------------- تحلیل و روند ----------------

  /// روند درآمد/هزینه/سود ماه به ماه برای N ماه اخیر (شامل ماه جاری تا امروز)
  Future<List<Map<String, dynamic>>> monthlyTrend(int months) async {
    final today = Jalali.now();
    final result = <Map<String, dynamic>>[];
    for (int i = months - 1; i >= 0; i--) {
      var y = today.year;
      var m = today.month - i;
      while (m < 1) {
        m += 12;
        y -= 1;
      }
      final monthStart = Jalali(y, m, 1);
      final isCurrentMonth = (y == today.year && m == today.month);
      final monthEnd = isCurrentMonth ? today : Jalali(y, m, monthStart.monthLength);
      final income = await totalAccountTypeBalance(kAccountIncome,
          fromDate: jalaliToString(monthStart), toDate: jalaliToString(monthEnd));
      final expense = await totalAccountTypeBalance(kAccountExpense,
          fromDate: jalaliToString(monthStart), toDate: jalaliToString(monthEnd));
      result.add({
        'year': y,
        'month': m,
        'income': income,
        'expense': expense,
        'profit': income - expense,
      });
    }
    return result;
  }

  /// مقایسه درآمد/هزینه/سود «از اول ماه جاری تا امروز» با «همان تعداد روز از ماه قبل»
  Future<Map<String, double>> monthOverMonthComparison() async {
    final today = Jalali.now();
    final thisStart = Jalali(today.year, today.month, 1);

    var prevYear = today.year;
    var prevMonth = today.month - 1;
    if (prevMonth < 1) {
      prevMonth = 12;
      prevYear -= 1;
    }
    final prevStart = Jalali(prevYear, prevMonth, 1);
    final prevMonthLen = prevStart.monthLength;
    final dayNum = today.day > prevMonthLen ? prevMonthLen : today.day;
    final prevEnd = Jalali(prevYear, prevMonth, dayNum);

    final thisIncome = await totalAccountTypeBalance(kAccountIncome,
        fromDate: jalaliToString(thisStart), toDate: jalaliToString(today));
    final thisExpense = await totalAccountTypeBalance(kAccountExpense,
        fromDate: jalaliToString(thisStart), toDate: jalaliToString(today));
    final prevIncome = await totalAccountTypeBalance(kAccountIncome,
        fromDate: jalaliToString(prevStart), toDate: jalaliToString(prevEnd));
    final prevExpense = await totalAccountTypeBalance(kAccountExpense,
        fromDate: jalaliToString(prevStart), toDate: jalaliToString(prevEnd));

    return {
      'thisIncome': thisIncome,
      'thisExpense': thisExpense,
      'thisProfit': thisIncome - thisExpense,
      'prevIncome': prevIncome,
      'prevExpense': prevExpense,
      'prevProfit': prevIncome - prevExpense,
    };
  }

  /// مانده حساب‌هایی که دقیقاً با یکی از نام‌های داده‌شده مطابقت دارند (برای هزینه‌های ثابت دفتر)
  Future<double> accountsBalanceByNames(List<String> names,
      {String? fromDate, String? toDate}) async {
    final allAccounts = await getAccounts();
    double total = 0;
    for (final name in names) {
      for (final a in allAccounts.where((x) => x.name == name)) {
        final bal = await accountBalance(a.id!, fromDate: fromDate, toDate: toDate);
        total += bal['balance']!;
      }
    }
    return total;
  }

  /// میانگین هزینه‌های نسبتاً ثابت دفتر (هزینه‌های دفتر + حقوق و دستمزد) در N ماه اخیر
  /// به‌عنوان تقریبی از نقطه سربه‌سر ماهانه
  Future<double> avgMonthlyFixedCost(int months) async {
    final today = Jalali.now();
    double total = 0;
    for (int i = 0; i < months; i++) {
      var y = today.year;
      var m = today.month - i;
      while (m < 1) {
        m += 12;
        y -= 1;
      }
      final monthStart = Jalali(y, m, 1);
      final isCurrentMonth = (y == today.year && m == today.month);
      final monthEnd = isCurrentMonth ? today : Jalali(y, m, monthStart.monthLength);
      final cost = await accountsBalanceByNames(
        ['هزینه‌های دفتر', 'حقوق و دستمزد'],
        fromDate: jalaliToString(monthStart),
        toDate: jalaliToString(monthEnd),
      );
      total += cost;
    }
    return months == 0 ? 0 : total / months;
  }

  /// میانگین دریافتی هر پروژه، فقط در بین پروژه‌هایی که دریافتی ثبت‌شده دارند
  Future<double> avgRevenuePerProject() async {
    final projects = await getProjects();
    double total = 0;
    int count = 0;
    for (final p in projects) {
      final fin = await projectFinancials(p.id!);
      if (fin['received']! > 0) {
        total += fin['received']!;
        count++;
      }
    }
    return count == 0 ? 0 : total / count;
  }

  // ---------------- پیش‌نویس‌های پیامک بانکی ----------------
  Future<int> insertSmsDraft(SmsDraftModel d) async {
    final db = await database;
    return db.insert('sms_drafts', d.toMap()..remove('id'));
  }

  Future<List<SmsDraftModel>> getSmsDrafts({String status = kSmsDraftPending}) async {
    final db = await database;
    final maps = await db.query('sms_drafts',
        where: 'status = ?', whereArgs: [status], orderBy: 'id DESC');
    return maps.map((m) => SmsDraftModel.fromMap(m)).toList();
  }

  Future<int> countPendingSmsDrafts() async {
    final db = await database;
    final result = await db.rawQuery(
        "SELECT COUNT(*) as c FROM sms_drafts WHERE status = ?", [kSmsDraftPending]);
    return (result.first['c'] as int?) ?? 0;
  }

  Future<void> updateSmsDraftStatus(int id, String status) async {
    final db = await database;
    await db.update('sms_drafts', {'status': status}, where: 'id = ?', whereArgs: [id]);
  }

  /// جلوگیری از ثبت پیش‌نویس تکراری برای همان پیامک
  Future<bool> smsDraftExists(String rawBody) async {
    final db = await database;
    final maps =
        await db.query('sms_drafts', where: 'rawBody = ?', whereArgs: [rawBody], limit: 1);
    return maps.isNotEmpty;
  }

  // ---------------- جریان مالی پروژه (Price Events / Finalization / Discount) ----------------

  /// ثبت رویداد تغییر مبلغ برآوردی پروژه (پیش از Finalization). این رویداد
  /// فقط تاریخچه است و Journal تولید نمی‌کند - مبلغ پروژه هنوز قطعی نیست.
  Future<int> addProjectPriceEvent({
    required int projectId,
    required String type,
    required double amount,
    String? reason,
    required String date,
    DatabaseExecutor? executor,
  }) async {
    final project = await getProject(projectId, executor);
    if (project != null && project.isFinalized && type != kPriceEventFinalAdjustment && type != kPriceEventDiscount) {
      throw Exception('این پروژه نهایی شده؛ تغییر مبلغ برآوردی دیگر امکان‌پذیر نیست.');
    }
    final db = executor ?? await database;
    return db.insert('project_price_events', {
      'projectId': projectId,
      'type': type,
      'amount': amount,
      'reason': reason,
      'date': date,
      'createdAt': todayJalaliString(),
    });
  }

  /// درج خام رویداد قیمت بدون اعتبارسنجی/Journal اضافه - فقط برای بازیابی
  /// پشتیبان که خودِ اسناد حسابداری متناظر را جداگانه وارد می‌کند
  Future<int> insertProjectPriceEventRaw(ProjectPriceEventModel e, [DatabaseExecutor? executor]) async {
    final db = executor ?? await database;
    return db.insert('project_price_events', e.toMap()..remove('id'));
  }

  Future<List<ProjectPriceEventModel>> getProjectPriceEvents(int projectId) async {
    final db = await database;
    final maps = await db.query('project_price_events',
        where: 'projectId = ?', whereArgs: [projectId], orderBy: 'id ASC');
    return maps.map((m) => ProjectPriceEventModel.fromMap(m)).toList();
  }

  /// رویدادهای تغییر قیمت همه پروژه‌ها در یک بازه تاریخ - تنها READ API
  /// جدید لایه تحلیل عملکرد عملیاتی؛ چون API موجود (getProjectPriceEvents)
  /// فقط سطح یک پروژه است و هیچ مسیر سراسری با فیلتر بازه برای تحلیل دوره‌ای
  /// قیمت/تخفیف در کل دفتر وجود نداشت. فیلتر بر مبنای ProjectPriceEvent.date
  /// است (طبق قاعده رسمی این نوع Metric)، نه تاریخ ایجاد یا Finalize پروژه.
  Future<List<ProjectPriceEventModel>> getAllPriceEventsInRange({String? fromDate, String? toDate}) async {
    final db = await database;
    String? where;
    List<Object?> args = [];
    if (fromDate != null) {
      where = 'date >= ?';
      args.add(fromDate);
    }
    if (toDate != null) {
      where = where == null ? 'date <= ?' : '$where AND date <= ?';
      args.add(toDate);
    }
    final maps = await db.query('project_price_events',
        where: where, whereArgs: args.isEmpty ? null : args, orderBy: 'date ASC');
    return maps.map((m) => ProjectPriceEventModel.fromMap(m)).toList();
  }

  /// مبلغ مورد انتظار فعلی پروژه = برآورد اولیه + مجموع رویدادهای پیش از
  /// Finalization (ADDITION/REDUCTION/ADJUSTMENT). بعد از Finalization دیگر
  /// معنا ندارد؛ در آن حالت finalAmount + FINAL_ADJUSTMENTها ملاک است.
  Future<double> currentExpectedAmount(int projectId) async {
    final project = await getProject(projectId);
    if (project == null) return 0;
    final events = await getProjectPriceEvents(projectId);
    final preFinalSum = events
        .where((e) => e.type == kPriceEventAddition ||
            e.type == kPriceEventReduction ||
            e.type == kPriceEventAdjustment)
        .fold<double>(0, (s, e) => s + e.amount);
    return project.agreedAmount + preFinalSum;
  }

  /// مجموع اصلاحات پس از Finalization (FINAL_ADJUSTMENT) - علامت‌دار
  Future<double> _finalAdjustmentsTotal(int projectId) async {
    final events = await getProjectPriceEvents(projectId);
    return events
        .where((e) => e.type == kPriceEventFinalAdjustment)
        .fold<double>(0, (s, e) => s + e.amount);
  }

  /// مجموع تخفیف‌های ثبت‌شده (همیشه به‌صورت مقدار مثبت گزارش می‌شود)
  Future<double> _totalDiscount(int projectId) async {
    final events = await getProjectPriceEvents(projectId);
    final sum = events.where((e) => e.type == kPriceEventDiscount).fold<double>(0, (s, e) => s + e.amount);
    return sum.abs();
  }

  /// نهایی‌سازی پروژه (Finalization): مبلغ نهایی ثبت می‌شود (هرگز overwrite
  /// نمی‌شود)، درآمد پروژه شناسایی می‌شود، و مانده پیش‌دریافت موجود این پروژه
  /// به‌طور خودکار به حساب دریافتنی منتقل می‌شود.
  /// نهایی‌سازی پروژه - کاملاً Atomic از طریق یک Transaction واقعی دیتابیس
  /// (نه الگوی جبرانیِ قبلی که با delete دستی rollback می‌کرد). اگر هر
  /// مرحله (اعتبارسنجی سند دوم، یا حتی بروزرسانی نهایی پروژه) شکست بخورد،
  /// SQLite کل تراکنش را rollback می‌کند و هیچ سند یا تغییری باقی نمی‌ماند.
  Future<void> finalizeProject({
    required int projectId,
    required double finalAmount,
    required String date,
    String? note,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final project = await getProject(projectId, txn);
      if (project == null) throw Exception('پروژه یافت نشد.');
      if (project.isFinalized) {
        // Idempotency: نهایی‌سازی تکراری هرگز نباید سند دوم بسازد
        throw Exception('این پروژه قبلاً نهایی شده است.');
      }
      if (project.status == kProjectStatusCancelled) {
        // تکمیل همان Invariant که در updateProject تعریف شده: یک پروژه
        // نمی‌تواند هم‌زمان لغوشده و نهایی‌شده باشد؛ این ترکیب حالت باید
        // از هر دو مسیر (ویرایش عمومی و Workflow نهایی‌سازی) مسدود شود.
        throw Exception('پروژه لغوشده قابل نهایی‌سازی نیست.');
      }
      final arAccount = await getReceivableAccount(txn);
      final revenueAccount = await getProjectRevenueAccount(txn);
      final advanceAccount = await getCustomerAdvanceAccount(txn);
      if (arAccount == null || revenueAccount == null || advanceAccount == null) {
        throw Exception('حساب‌های کنترلی موردنیاز (دریافتنی/درآمد پروژه/پیش‌دریافت) یافت نشدند.');
      }

      final revenueEntry = JournalEntryModel(
        date: date,
        description: 'نهایی‌سازی پروژه «${project.title}» - شناسایی درآمد',
        createdAt: todayJalaliString(),
        source: kJournalSourceSystem,
        lines: [
          JournalLineModel(
              accountId: arAccount.id!,
              debit: finalAmount.round(),
              projectId: projectId,
              counterpartyId: project.counterpartyId),
          JournalLineModel(
              accountId: revenueAccount.id!,
              credit: finalAmount.round(),
              projectId: projectId,
              counterpartyId: project.counterpartyId),
        ],
      );
      await _validateJournalEntry(revenueEntry, txn);
      await _writeJournalEntryRaw(txn, revenueEntry);

      // انتقال مانده پیش‌دریافت موجود همین پروژه به حساب دریافتنی - با
      // محافظت Overpayment: اگر پیش‌دریافت از مبلغ نهایی بیشتر باشد، مازاد
      // به AR منفی تبدیل نمی‌شود، بلکه به «بستانکاری مشتری» می‌رود. مانده
      // پیش‌دریافت از همین Transaction خوانده می‌شود، نه اتصال مستقل.
      final advanceBalance = await projectAdvanceBalance(projectId, txn);
      if (advanceBalance > 0) {
        final creditLines = await _creditArWithOverflowGuard(
          projectId: projectId,
          counterpartyId: project.counterpartyId,
          arAccountId: arAccount.id!,
          amount: advanceBalance,
          executor: txn,
        );
        final advanceEntry = JournalEntryModel(
          date: date,
          description: 'انتقال پیش‌دریافت به حساب دریافتنی - پروژه «${project.title}»',
          createdAt: todayJalaliString(),
          source: kJournalSourceSystem,
          lines: [
            JournalLineModel(
                accountId: advanceAccount.id!,
                debit: advanceBalance.round(),
                projectId: projectId,
                counterpartyId: project.counterpartyId),
            ...creditLines,
          ],
        );
        await _validateJournalEntry(advanceEntry, txn);
        await _writeJournalEntryRaw(txn, advanceEntry);
      }

      final updatedProject = project.copyWith(
        finalAmount: finalAmount,
        finalizedDate: date,
        finalizedNote: note,
        status: kProjectStatusFinalized,
      );
      await txn.update('projects', updatedProject.toMap(), where: 'id = ?', whereArgs: [projectId]);
    });
  }

  /// ثبت تخفیف نهایی - فقط پس از Finalization مجاز است. تخفیف مبلغ نهایی
  /// اصلی را overwrite نمی‌کند؛ به‌صورت رویداد مستقل ذخیره و Journal می‌شود.
  Future<void> recordProjectDiscount({
    required int projectId,
    required double amount,
    String? reason,
    required String date,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      final project = await getProject(projectId, txn);
      if (project == null || !project.isFinalized) {
        throw Exception('تخفیف فقط پس از نهایی‌سازی پروژه قابل ثبت است.');
      }
      final arAccount = await getReceivableAccount(txn);
      final discountAccount = await getServiceDiscountAccount(txn);
      if (arAccount == null || discountAccount == null) {
        throw Exception('حساب‌های کنترلی موردنیاز یافت نشدند.');
      }
      // تخفیف یک تصمیم عمدی کاربر است (نه دریافت پول از بیرون که باید جایی
      // پارک شود)؛ پس اگر از مانده طلب بیشتر باشد، به‌جای مسیر دادن به یک
      // حساب دیگر، به‌صراحت رد می‌شود تا کاربر عدد را اصلاح کند.
      final currentAr = await projectReceivableBalance(projectId, txn);
      if (amount > currentAr) {
        throw Exception(
            'مبلغ تخفیف (${formatMoney(amount)}) از مانده طلب فعلی این پروژه (${formatMoney(currentAr)}) بیشتر است.');
      }
      final entry = JournalEntryModel(
        date: date,
        description: reason?.isNotEmpty == true ? 'تخفیف: $reason' : 'تخفیف نهایی پروژه',
        createdAt: todayJalaliString(),
        source: kJournalSourceSystem,
        lines: [
          JournalLineModel(
              accountId: discountAccount.id!,
              debit: amount.round(),
              projectId: projectId,
              counterpartyId: project.counterpartyId),
          JournalLineModel(
              accountId: arAccount.id!,
              credit: amount.round(),
              projectId: projectId,
              counterpartyId: project.counterpartyId),
        ],
      );
      await _validateJournalEntry(entry, txn);
      await _writeJournalEntryRaw(txn, entry);
      await addProjectPriceEvent(
        projectId: projectId,
        type: kPriceEventDiscount,
        amount: -amount,
        reason: reason,
        date: date,
        executor: txn,
      );
    });
  }

  /// اصلاح مبلغ نهایی پس از Finalization (مثبت یا منفی) - Finalization قبلی
  /// را overwrite نمی‌کند، یک رویداد و یک سند اصلاحی مستقل ایجاد می‌کند.
  Future<void> recordFinalAdjustment({
    required int projectId,
    required double amount, // علامت‌دار: مثبت=افزایش درآمد، منفی=کاهش
    String? reason,
    required String date,
  }) async {
    if (amount == 0) return;
    final db = await database;
    await db.transaction((txn) async {
      final project = await getProject(projectId, txn);
      if (project == null || !project.isFinalized) {
        throw Exception('اصلاح مبلغ نهایی فقط پس از نهایی‌سازی پروژه ممکن است.');
      }
      final arAccount = await getReceivableAccount(txn);
      final revenueAccount = await getProjectRevenueAccount(txn);
      if (arAccount == null || revenueAccount == null) {
        throw Exception('حساب‌های کنترلی موردنیاز یافت نشدند.');
      }
      final magnitude = amount.abs().round();
      // اصلاح کاهشی، AR را بستانکار (کاهش) می‌دهد؛ اگر از مانده فعلی بیشتر
      // باشد، به‌جای منفی‌کردن AR، به‌صراحت رد می‌شود.
      if (amount < 0) {
        final currentAr = await projectReceivableBalance(projectId, txn);
        if (magnitude > currentAr) {
          throw Exception(
              'مقدار کاهش (${formatMoney(magnitude)}) از مانده طلب فعلی این پروژه (${formatMoney(currentAr)}) بیشتر است.');
        }
      }
      final entry = JournalEntryModel(
        date: date,
        description: reason?.isNotEmpty == true ? 'اصلاح مبلغ نهایی: $reason' : 'اصلاح مبلغ نهایی پروژه',
        createdAt: todayJalaliString(),
        source: kJournalSourceSystem,
        lines: amount > 0
            ? [
                JournalLineModel(
                    accountId: arAccount.id!,
                    debit: magnitude,
                    projectId: projectId,
                    counterpartyId: project.counterpartyId),
                JournalLineModel(
                    accountId: revenueAccount.id!,
                    credit: magnitude,
                    projectId: projectId,
                    counterpartyId: project.counterpartyId),
              ]
            : [
                JournalLineModel(
                    accountId: revenueAccount.id!,
                    debit: magnitude,
                    projectId: projectId,
                    counterpartyId: project.counterpartyId),
                JournalLineModel(
                    accountId: arAccount.id!,
                    credit: magnitude,
                    projectId: projectId,
                    counterpartyId: project.counterpartyId),
              ],
      );
      await _validateJournalEntry(entry, txn);
      await _writeJournalEntryRaw(txn, entry);
      await addProjectPriceEvent(
        projectId: projectId,
        type: kPriceEventFinalAdjustment,
        amount: amount,
        reason: reason,
        date: date,
        executor: txn,
      );
    });
  }

  /// دریافت وجه برای یک پروژه مشخص - مقصد بستانکار به‌صورت هوشمند تعیین
  /// می‌شود: پیش از Finalization همیشه «پیش‌دریافت مشتری» (هرگز درآمد)،
  /// پس از آن «حساب‌های دریافتنی» (تسویه طلب، نه درآمد جدید).
  Future<void> receiveProjectPayment({
    required int projectId,
    required int cashAccountId,
    required double amount,
    required String date,
    String? description,
  }) async {
    final project = await getProject(projectId);
    if (project == null) throw Exception('پروژه یافت نشد.');
    final targetAccount = project.isFinalized
        ? await getReceivableAccount()
        : await getCustomerAdvanceAccount();
    if (targetAccount == null) {
      throw Exception('حساب کنترلی موردنیاز یافت نشد.');
    }

    // پیش از Finalization، پیش‌دریافت باز و بدون سقف است (چون برآورد قطعی
    // نیست)؛ پس از Finalization، دریافت مازاد بر مانده طلب باید به‌جای
    // منفی‌کردن AR، به «بستانکاری مشتری» برود.
    final creditLines = project.isFinalized
        ? await _creditArWithOverflowGuard(
            projectId: projectId,
            counterpartyId: project.counterpartyId,
            arAccountId: targetAccount.id!,
            amount: amount,
          )
        : [
            JournalLineModel(
                accountId: targetAccount.id!,
                credit: amount.round(),
                projectId: projectId,
                counterpartyId: project.counterpartyId),
          ];

    await insertJournalEntry(JournalEntryModel(
      date: date,
      description: description?.isNotEmpty == true
          ? description!
          : (project.isFinalized ? 'دریافت طلب پروژه' : 'پیش‌دریافت پروژه'),
      createdAt: todayJalaliString(),
      source: kJournalSourceSystem,
      lines: [
        JournalLineModel(
            accountId: cashAccountId,
            debit: amount.round(),
            projectId: projectId,
            counterpartyId: project.counterpartyId),
        ...creditLines,
      ],
    ));
  }

  /// آیا پروژه از نظر مالی تسویه‌شده است؟ (مستقل از Finalized بودن) -
  /// هرگز cache نمی‌شود، همیشه زنده از Ledger محاسبه می‌شود.
  /// طبق تعریف رسمی: Settled فقط یعنی isFinalized + بدون مانده طلب/پیش‌دریافت.
  /// Customer Credit یک بستانکاری/تعهد مستقل نسبت به مشتری است و در این
  /// فرمول دخالت نمی‌کند - ممکن است پروژه‌ای Settled باشد ولی هنوز
  /// Customer Credit باز داشته باشد؛ این دو مفهوم هرگز در یک Boolean ادغام
  /// نمی‌شوند (وضعیت Credit جداگانه در ProjectFinancialReport گزارش می‌شود).
  Future<bool> isProjectSettled(int projectId) async {
    final project = await getProject(projectId);
    if (project == null || !project.isFinalized) return false;
    final advance = await projectAdvanceBalance(projectId);
    final receivable = await projectReceivableBalance(projectId);
    return advance == 0 && receivable == 0;
  }

  /// خلاصه کامل مالی پروژه - همه اعداد مستقیم از Ledger و رویدادهای قیمتی
  /// محاسبه می‌شوند، هیچ‌کدام cache نشده‌اند.
  /// هزینه مستقیم پروژه: مجموع سطرهای نوع هزینه که به همین پروژه تگ خورده‌اند،
  /// به‌جز حساب «تخفیف خدمات» که هرچند برای سادگی نوعش هزینه است، مفهوماً
  /// کاهنده درآمد (Contra-Revenue) است، نه یک هزینه واقعی پروژه. این متد
  /// عمومی است تا هم projectFinancialSummary و هم FinancialMetricsService از
  /// همین یک منبع استفاده کنند، نه دو فرمول موازی.
  Future<double> projectDirectCost(int projectId) async {
    final db = await database;
    final discountAccount = await getServiceDiscountAccount();
    final directCostResult = await db.rawQuery("""
      SELECT COALESCE(SUM(l.debit),0) - COALESCE(SUM(l.credit),0) as total
      FROM journal_lines l JOIN accounts a ON a.id = l.accountId
      WHERE l.projectId = ? AND a.type = ? AND (a.id != ? OR ? IS NULL)
    """, [projectId, kAccountExpense, discountAccount?.id ?? -1, discountAccount?.id]);
    return (directCostResult.first['total'] as num).toDouble();
  }

  Future<Map<String, dynamic>> projectFinancialSummary(int projectId) async {
    final project = await getProject(projectId);
    if (project == null) throw Exception('پروژه یافت نشد.');

    final initialEstimate = project.agreedAmount;
    final currentExpected = await currentExpectedAmount(projectId);
    final discount = await _totalDiscount(projectId);
    final finalAdjustments = await _finalAdjustmentsTotal(projectId);
    final grossFinalAmount =
        project.isFinalized ? (project.finalAmount! + finalAdjustments) : null;
    final netRevenue = grossFinalAmount != null ? grossFinalAmount - discount : null;

    final cashFlow = await projectFinancials(projectId); // received/spent واقعی نقدی
    final totalReceived = cashFlow['received']!;
    final advanceBalance = await projectAdvanceBalance(projectId);
    final receivableBalance = await projectReceivableBalance(projectId);
    final customerCreditBalance = await projectCustomerCreditBalance(projectId);

    final directCost = await projectDirectCost(projectId);

    final contribution = netRevenue != null ? netRevenue - directCost : null;
    final margin = (contribution != null && netRevenue != null && netRevenue > 0)
        ? (contribution / netRevenue) * 100
        : null;

    final settled = await isProjectSettled(projectId);

    return {
      'initialEstimate': initialEstimate,
      'currentExpectedAmount': currentExpected,
      'isFinalized': project.isFinalized,
      'grossFinalAmount': grossFinalAmount,
      'discount': discount,
      'netRevenue': netRevenue,
      'totalReceived': totalReceived,
      'customerAdvance': advanceBalance,
      'receivable': receivableBalance,
      'customerCredit': customerCreditBalance,
      'directProjectCost': directCost,
      'projectContribution': contribution,
      'projectMargin': margin,
      'isSettled': settled,
    };
  }

  // ---------------- Financial Metrics Layer - توابع کمکی سطح دفتر ----------------
  // این توابع صرفاً Ledger موجود را با فیلتر بازه تاریخ جمع می‌زنند؛ منطق
  // موازی یا مانده جدیدی نمی‌سازند - فقط برای مصرف توسط FinancialMetricsService.

  /// درآمد ناخالص دفتر (حساب درآمد پروژه‌ها) در بازه دلخواه
  Future<double> officeGrossRevenue({String? fromDate, String? toDate}) async {
    final account = await getProjectRevenueAccount();
    if (account == null) return 0;
    final bal = await accountBalance(account.id!, fromDate: fromDate, toDate: toDate);
    return bal['balance']!;
  }

  /// مجموع تخفیف در بازه دلخواه
  Future<double> officeDiscountTotal({String? fromDate, String? toDate}) async {
    final account = await getServiceDiscountAccount();
    if (account == null) return 0;
    final bal = await accountBalance(account.id!, fromDate: fromDate, toDate: toDate);
    return bal['balance']!;
  }

  /// مجموع سربار عمومی پروژه‌ها در بازه دلخواه
  Future<double> officeOverheadTotal({String? fromDate, String? toDate}) async {
    final account = await getProjectOverheadAccount();
    if (account == null) return 0;
    final bal = await accountBalance(account.id!, fromDate: fromDate, toDate: toDate);
    return bal['balance']!;
  }

  /// مجموع هزینه مستقیم همه پروژه‌ها (نه یک پروژه خاص) در بازه دلخواه -
  /// همان قاعده projectDirectCost: نوع هزینه + projectId غیرخالی + بدون تخفیف
  Future<double> officeDirectCostTotal({String? fromDate, String? toDate}) async {
    final db = await database;
    final discountAccount = await getServiceDiscountAccount();
    String where = 'a.type = ? AND l.projectId IS NOT NULL AND (a.id != ? OR ? IS NULL)';
    List<Object?> args = [kAccountExpense, discountAccount?.id ?? -1, discountAccount?.id];
    if (fromDate != null) {
      where += ' AND l.entryId IN (SELECT id FROM journal_entries WHERE date >= ?)';
      args.add(fromDate);
    }
    if (toDate != null) {
      where += ' AND l.entryId IN (SELECT id FROM journal_entries WHERE date <= ?)';
      args.add(toDate);
    }
    final result = await db.rawQuery(
        'SELECT COALESCE(SUM(l.debit),0)-COALESCE(SUM(l.credit),0) as total FROM journal_lines l JOIN accounts a ON a.id=l.accountId WHERE $where',
        args);
    return (result.first['total'] as num).toDouble();
  }

  /// هزینه‌های دفتر: طبق قرارداد صریح این پروژه (چون systemKey اختصاصی
  /// «office_expense» در معماری فعلی وجود ندارد) — هر سطر نوع «هزینه» که
  /// projectId ندارد و به حساب سربار پروژه‌ها یا تخفیف هم ثبت نشده باشد.
  /// یعنی هزینه‌های عمومی دفتر (اجاره، حقوق، آب و برق، اداری) که برخلاف
  /// Direct Cost به پروژه خاصی وصل نیستند و برخلاف Overhead هم برای
  /// «پیشبرد پروژه‌ها» به‌طور خاص علامت‌گذاری نشده‌اند.
  Future<double> officeExpenseTotal({String? fromDate, String? toDate}) async {
    final db = await database;
    final overheadAccount = await getProjectOverheadAccount();
    final discountAccount = await getServiceDiscountAccount();
    String where =
        'a.type = ? AND l.projectId IS NULL AND (a.id != ? OR ? IS NULL) AND (a.id != ? OR ? IS NULL)';
    List<Object?> args = [
      kAccountExpense,
      overheadAccount?.id ?? -1,
      overheadAccount?.id,
      discountAccount?.id ?? -1,
      discountAccount?.id,
    ];
    if (fromDate != null) {
      where += ' AND l.entryId IN (SELECT id FROM journal_entries WHERE date >= ?)';
      args.add(fromDate);
    }
    if (toDate != null) {
      where += ' AND l.entryId IN (SELECT id FROM journal_entries WHERE date <= ?)';
      args.add(toDate);
    }
    final result = await db.rawQuery(
        'SELECT COALESCE(SUM(l.debit),0)-COALESCE(SUM(l.credit),0) as total FROM journal_lines l JOIN accounts a ON a.id=l.accountId WHERE $where',
        args);
    return (result.first['total'] as num).toDouble();
  }

  /// موجودی نقد/بانک تا پایان یک تاریخ مشخص (شامل همان روز) - برای Closing Cash
  Future<double> cashBalanceThrough({String? throughDate}) async {
    final cashAccounts = await getCashAccounts();
    double total = 0;
    for (final acc in cashAccounts) {
      final bal = await accountBalance(acc.id!, toDate: throughDate);
      total += bal['balance']!;
    }
    return total;
  }

  /// موجودی نقد/بانک دقیقاً پیش از یک تاریخ مشخص (بدون احتساب همان روز) -
  /// برای Opening Cash یک بازه
  Future<double> cashBalanceBefore(String date) async {
    final db = await database;
    final cashAccounts = await getCashAccounts();
    if (cashAccounts.isEmpty) return 0;
    final ids = cashAccounts.map((a) => a.id).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    final result = await db.rawQuery('''
      SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c
      FROM journal_lines WHERE accountId IN ($placeholders)
        AND entryId IN (SELECT id FROM journal_entries WHERE date < ?)
    ''', [...ids, date]);
    final d = (result.first['d'] as num).toDouble();
    final c = (result.first['c'] as num).toDouble();
    return d - c;
  }

  /// طبقه‌بندی حرکت نقدی یک بازه به ۶ دسته Cash Flow. محدودیت مستند: فقط
  /// اسناد دقیقاً دوسطری قابل طبقه‌بندی دقیق‌اند (که تمام مسیرهای خودکار
  /// برنامه چنین‌اند)؛ سندهای دستی چندسطری در «سایر» قرار می‌گیرند.
  Future<Map<String, double>> classifyCashFlow({String? fromDate, String? toDate}) async {
    final cashAccounts = await getCashAccounts();
    if (cashAccounts.isEmpty) {
      return {
        'customerReceipts': 0,
        'otherCashInflows': 0,
        'projectPayments': 0,
        'projectOverheadPayments': 0,
        'officePayments': 0,
        'otherCashOutflows': 0,
      };
    }
    final db = await database;
    final cashIds = cashAccounts.map((a) => a.id).toList();
    final placeholders = List.filled(cashIds.length, '?').join(',');

    String dateWhere = '';
    List<Object?> dateArgs = [];
    if (fromDate != null) {
      dateWhere += ' AND je.date >= ?';
      dateArgs.add(fromDate);
    }
    if (toDate != null) {
      dateWhere += ' AND je.date <= ?';
      dateArgs.add(toDate);
    }

    final rows = await db.rawQuery('''
      SELECT cl.debit as cashDebit, cl.credit as cashCredit, cl.projectId as projectId,
             cl.counterpartyId as counterpartyId, otherAcc.type as otherType,
             otherAcc.systemKey as otherSystemKey
      FROM journal_lines cl
      JOIN journal_entries je ON je.id = cl.entryId
      JOIN journal_lines other ON other.entryId = cl.entryId AND other.id != cl.id
      JOIN accounts otherAcc ON otherAcc.id = other.accountId
      WHERE cl.accountId IN ($placeholders)
        AND (SELECT COUNT(*) FROM journal_lines x WHERE x.entryId = cl.entryId) = 2
        $dateWhere
    ''', [...cashIds, ...dateArgs]);

    double customerReceipts = 0, otherIn = 0, projectPay = 0, overheadPay = 0, officePay = 0, otherOut = 0;
    for (final row in rows) {
      final debit = (row['cashDebit'] as num).toDouble();
      final credit = (row['cashCredit'] as num).toDouble();
      final projectId = row['projectId'] as int?;
      final counterpartyId = row['counterpartyId'] as int?;
      final otherType = row['otherType'] as String?;
      final otherSystemKey = row['otherSystemKey'] as String?;

      if (debit > 0) {
        if (counterpartyId != null) {
          customerReceipts += debit;
        } else {
          otherIn += debit;
        }
      }
      if (credit > 0) {
        if (otherSystemKey == kSystemKeyProjectOverhead) {
          overheadPay += credit;
        } else if (projectId != null &&
            otherType == kAccountExpense &&
            otherSystemKey != kSystemKeyServiceDiscount) {
          projectPay += credit;
        } else if (otherType == kAccountExpense &&
            projectId == null &&
            otherSystemKey != kSystemKeyProjectOverhead &&
            otherSystemKey != kSystemKeyServiceDiscount) {
          officePay += credit;
        } else {
          otherOut += credit;
        }
      }
    }

    // سطرهای نقدی متعلق به اسناد غیر-دقیقاً-دوسطری (مثلاً یک سند دستی
    // چندسطری) با Self-Join بالا قابل طبقه‌بندی دقیق نیستند؛ اما برای
    // این‌که جمع کل شش سبد همیشه دقیقاً با تغییر موجودی واقعی (Closing-
    // Opening) یکی باشد - نه کمتر - این سطرها حذف نمی‌شوند، بلکه کامل در
    // سبد «سایر» قرار می‌گیرند.
    String otherEntriesDateWhere = '';
    List<Object?> otherEntriesDateArgs = [];
    if (fromDate != null) {
      otherEntriesDateWhere += ' AND je.date >= ?';
      otherEntriesDateArgs.add(fromDate);
    }
    if (toDate != null) {
      otherEntriesDateWhere += ' AND je.date <= ?';
      otherEntriesDateArgs.add(toDate);
    }
    final unclassifiedRows = await db.rawQuery('''
      SELECT COALESCE(SUM(cl.debit),0) as d, COALESCE(SUM(cl.credit),0) as c
      FROM journal_lines cl
      JOIN journal_entries je ON je.id = cl.entryId
      WHERE cl.accountId IN ($placeholders)
        AND (SELECT COUNT(*) FROM journal_lines x WHERE x.entryId = cl.entryId) != 2
        $otherEntriesDateWhere
    ''', [...cashIds, ...otherEntriesDateArgs]);
    otherIn += (unclassifiedRows.first['d'] as num).toDouble();
    otherOut += (unclassifiedRows.first['c'] as num).toDouble();

    return {
      'customerReceipts': customerReceipts,
      'otherCashInflows': otherIn,
      'projectPayments': projectPay,
      'projectOverheadPayments': overheadPay,
      'officePayments': officePay,
      'otherCashOutflows': otherOut,
    };
  }

  // ---------------- Financial Reporting Layer - Movement & Reconciliation ----------------

  /// مانده یک حساب با فیلترهای دلخواه (پروژه و/یا بازه تاریخ)؛ پایه مشترک
  /// Movement Reportها - منطق موازی نیست، فقط تعمیم همان الگوی accountBalance.
  Future<double> _filteredAccountBalance({
    required int accountId,
    required bool debitNormal,
    int? projectId,
    String? fromDate,
    String? toDate,
    bool exclusiveToDate = false,
  }) async {
    final db = await database;
    String where = 'accountId = ?';
    List<Object?> args = [accountId];
    if (projectId != null) {
      where += ' AND projectId = ?';
      args.add(projectId);
    }
    if (fromDate != null) {
      where += ' AND entryId IN (SELECT id FROM journal_entries WHERE date >= ?)';
      args.add(fromDate);
    }
    if (toDate != null) {
      where +=
          ' AND entryId IN (SELECT id FROM journal_entries WHERE date ${exclusiveToDate ? '<' : '<='} ?)';
      args.add(toDate);
    }
    final result = await db.rawQuery(
        'SELECT COALESCE(SUM(debit),0) as d, COALESCE(SUM(credit),0) as c FROM journal_lines WHERE $where',
        args);
    final d = (result.first['d'] as num).toDouble();
    final c = (result.first['c'] as num).toDouble();
    return debitNormal ? d - c : c - d;
  }

  /// طبقه‌بندی حرکت یک حساب کنترلی (AR/Advance/CustomerCredit) در یک بازه،
  /// با پیداکردن حساب طرف‌مقابل هر سطر (Self-Join روی entryId). محدودیت
  /// مستند: فقط اسناد دقیقاً دوسطری قابل طبقه‌بندی دقیق‌اند (که تمام مسیرهای
  /// خودکار برنامه چنین‌اند)؛ سطرهای اسناد دستی چندسطری در دسته «سایر»
  /// قرار می‌گیرند، نه این‌که حدس زده شوند.
  /// آیا حساب با شناسه داده‌شده، خودش یا یکی از اجدادش (تا هر عمقی)
  /// Cash/Bank است؟ دقیقاً همان منطق _isCashOrBankAccount ولی بر مبنای
  /// نگاشت id→حساب (برای استفاده در طبقه‌بندی Movement که فقط id/parentId/
  /// systemKey طرف‌مقابل سند را از Query دارد، نه لیست همان نوع حساب).
  /// این تابع برای رفع اثر جانبی allowChildren=true روی صندوق/بانک لازم
  /// شد: بدون آن، وصولی مستقیم به یک زیرحساب بانکی (مثل «بانک ملی») به
  /// اشتباه «سایر» طبقه‌بندی می‌شد، نه «وصولی نقدی».
  bool _isCashOrBankById(int? accountId, Map<int, AccountModel> byId) {
    var current = accountId != null ? byId[accountId] : null;
    while (current != null) {
      if (current.systemKey == kSystemKeyCash || current.systemKey == kSystemKeyBank) return true;
      if (current.parentId == null) return false;
      current = byId[current.parentId];
    }
    return false;
  }

  Future<Map<String, double>> _classifyControlAccountMovement({
    required int accountId,
    required bool debitNormal,
    int? projectId,
    String? fromDate,
    String? toDate,
  }) async {
    final db = await database;
    // برای پیمایش زنجیره والد طرف‌مقابل سند (تشخیص صحیح Cash/Bank حتی اگر
    // مستقیم به یک زیرحساب بانکی سند خورده باشد، نه خودِ حساب «بانک»).
    final allAccounts = await getAccounts();
    final accountsById = {for (final a in allAccounts) if (a.id != null) a.id!: a};
    String dateWhere = '';
    List<Object?> dateArgs = [];
    if (fromDate != null) {
      dateWhere += ' AND je.date >= ?';
      dateArgs.add(fromDate);
    }
    if (toDate != null) {
      dateWhere += ' AND je.date <= ?';
      dateArgs.add(toDate);
    }
    String projectWhere = '';
    List<Object?> projectArgs = [];
    if (projectId != null) {
      projectWhere = ' AND cl.projectId = ?';
      projectArgs.add(projectId);
    }

    final rows = await db.rawQuery('''
      SELECT cl.debit as d, cl.credit as c, otherAcc.id as otherAccountId,
             otherAcc.systemKey as otherSystemKey
      FROM journal_lines cl
      JOIN journal_entries je ON je.id = cl.entryId
      JOIN journal_lines other ON other.entryId = cl.entryId AND other.id != cl.id
      JOIN accounts otherAcc ON otherAcc.id = other.accountId
      WHERE cl.accountId = ?
        AND (SELECT COUNT(*) FROM journal_lines x WHERE x.entryId = cl.entryId) = 2
        $projectWhere $dateWhere
    ''', [accountId, ...projectArgs, ...dateArgs]);

    // برای AR: افزایش (بدهکار) طرف‌مقابل Revenue => رکورد جدید طلب.
    // کاهش (بستانکار) طرف‌مقابل Cash/Bank (یا هر زیرحساب آن، مثل «بانک
    // ملی») => وصولی واقعی.
    // کاهش طرف‌مقابل Discount یا Revenue (اصلاح منفی) => اصلاحیه.
    // بقیه (مثلاً انتقال پیش‌دریافت) => «سایر»، با علامت افزایش/کاهش جدا
    // نگه‌داشته می‌شود (نه جمع بدون علامت) تا Identity ریاضی
    // opening + increase + otherIncrease - decreaseByCash -
    // decreaseByAdjustment - otherDecrease = closing همیشه دقیقاً برقرار
    // بماند و بدون حدس‌زدن قابل تست باشد.
    double increase = 0, decreaseByCash = 0, decreaseByAdjustment = 0;
    double otherIncrease = 0, otherDecrease = 0;
    for (final row in rows) {
      final d = (row['d'] as num).toDouble();
      final c = (row['c'] as num).toDouble();
      final otherKey = row['otherSystemKey'] as String?;
      final otherAccountId = row['otherAccountId'] as int?;
      final amount = debitNormal ? d : c; // مقداری که این حساب را افزایش می‌دهد
      final reduceAmount = debitNormal ? c : d; // مقداری که این حساب را کاهش می‌دهد

      if (amount > 0) {
        if (otherKey == kSystemKeyProjectRevenue || otherKey == kSystemKeyCustomerAdvance) {
          increase += amount;
        } else {
          otherIncrease += amount;
        }
      }
      if (reduceAmount > 0) {
        if (_isCashOrBankById(otherAccountId, accountsById)) {
          decreaseByCash += reduceAmount;
        } else if (otherKey == kSystemKeyServiceDiscount || otherKey == kSystemKeyProjectRevenue) {
          decreaseByAdjustment += reduceAmount;
        } else {
          otherDecrease += reduceAmount;
        }
      }
    }

    // سطرهای متعلق به اسناد غیر-دقیقاً-دوسطری (مثلاً یک سند دستی سه‌سطری) با
    // Self-Join بالا قابل طبقه‌بندی دقیق نیستند؛ اما دقیقاً طبق همان اصلاحی
    // که قبلاً برای classifyCashFlow انجام شد، این سطرها نباید کامل از
    // محاسبه حذف شوند (وگرنه Identity می‌شکند) - به‌جایش کامل و با علامت
    // صحیح در «سایر» لحاظ می‌شوند.
    final unclassified = await db.rawQuery('''
      SELECT COALESCE(SUM(cl.debit),0) as d, COALESCE(SUM(cl.credit),0) as c
      FROM journal_lines cl
      JOIN journal_entries je ON je.id = cl.entryId
      WHERE cl.accountId = ?
        AND (SELECT COUNT(*) FROM journal_lines x WHERE x.entryId = cl.entryId) != 2
        $projectWhere $dateWhere
    ''', [accountId, ...projectArgs, ...dateArgs]);
    final unclassifiedD = (unclassified.first['d'] as num).toDouble();
    final unclassifiedC = (unclassified.first['c'] as num).toDouble();
    otherIncrease += debitNormal ? unclassifiedD : unclassifiedC;
    otherDecrease += debitNormal ? unclassifiedC : unclassifiedD;

    return {
      'increase': increase,
      'decreaseByCash': decreaseByCash,
      'decreaseByAdjustment': decreaseByAdjustment,
      'otherIncrease': otherIncrease,
      'otherDecrease': otherDecrease,
    };
  }

  /// حرکت مانده حساب دریافتنی (AR) در یک بازه - Opening/Closing مستقیماً از
  /// Ledger؛ تفکیک increase/collections/adjustments با محدودیت مستندشده بالا.
  /// Identity قابل‌تست: opening + newReceivables - collections - adjustments
  /// + other = closing (که "other" علامت‌دار است: افزایش‌های نامشخص منهای
  /// کاهش‌های نامشخص، نه جمع بی‌علامت آن‌ها).
  Future<Map<String, double>> arMovement({String? fromDate, String? toDate, int? projectId}) async {
    final account = await getReceivableAccount();
    if (account == null) {
      return {
        'opening': 0,
        'newReceivables': 0,
        'collections': 0,
        'adjustments': 0,
        'other': 0,
        'closing': 0
      };
    }
    final opening = fromDate != null
        ? await _filteredAccountBalance(
            accountId: account.id!,
            debitNormal: true,
            projectId: projectId,
            toDate: fromDate,
            exclusiveToDate: true)
        : 0.0;
    final closing = await _filteredAccountBalance(
        accountId: account.id!, debitNormal: true, projectId: projectId, toDate: toDate);
    final movement = await _classifyControlAccountMovement(
        accountId: account.id!,
        debitNormal: true,
        projectId: projectId,
        fromDate: fromDate,
        toDate: toDate);
    return {
      'opening': opening,
      'newReceivables': movement['increase']!,
      'collections': movement['decreaseByCash']!,
      'adjustments': movement['decreaseByAdjustment']!,
      // علامت‌دار: افزایش‌های نامشخص منهای کاهش‌های نامشخص - این‌طوری
      // Identity جمع‌وتفریق همیشه دقیقاً برقرار می‌ماند، نه فقط تقریبی.
      'other': movement['otherIncrease']! - movement['otherDecrease']!,
      'closing': closing,
    };
  }

  /// حرکت مانده پیش‌دریافت (Customer Advance) در یک بازه. Identity قابل‌تست:
  /// opening + newAdvances - advanceApplied + other = closing (که "other"
  /// علامت‌دار است، نه جمع بی‌علامت افزایش/کاهش‌های نامشخص).
  Future<Map<String, double>> advanceMovement({String? fromDate, String? toDate, int? projectId}) async {
    final account = await getCustomerAdvanceAccount();
    if (account == null) {
      return {'opening': 0, 'newAdvances': 0, 'advanceApplied': 0, 'other': 0, 'closing': 0};
    }
    final opening = fromDate != null
        ? await _filteredAccountBalance(
            accountId: account.id!,
            debitNormal: false,
            projectId: projectId,
            toDate: fromDate,
            exclusiveToDate: true)
        : 0.0;
    final closing = await _filteredAccountBalance(
        accountId: account.id!, debitNormal: false, projectId: projectId, toDate: toDate);
    // برای Advance: افزایش (بستانکار) با طرف‌مقابل Cash => پیش‌دریافت جدید.
    // کاهش (بدهکار) با طرف‌مقابل AR => اعمال‌شده در تسویه (انتقال به AR در Finalization).
    final db = await database;
    // برای پیمایش زنجیره والد طرف‌مقابل سند (تشخیص صحیح Cash/Bank حتی اگر
    // مستقیم به یک زیرحساب بانکی سند خورده باشد).
    final allAccounts = await getAccounts();
    final accountsById = {for (final a in allAccounts) if (a.id != null) a.id!: a};
    String dateWhere = '';
    List<Object?> dateArgs = [];
    if (fromDate != null) {
      dateWhere += ' AND je.date >= ?';
      dateArgs.add(fromDate);
    }
    if (toDate != null) {
      dateWhere += ' AND je.date <= ?';
      dateArgs.add(toDate);
    }
    String projectWhere = '';
    List<Object?> projectArgs = [];
    if (projectId != null) {
      projectWhere = ' AND cl.projectId = ?';
      projectArgs.add(projectId);
    }
    final rows = await db.rawQuery('''
      SELECT cl.debit as d, cl.credit as c, otherAcc.id as otherAccountId,
             otherAcc.systemKey as otherSystemKey
      FROM journal_lines cl
      JOIN journal_entries je ON je.id = cl.entryId
      JOIN journal_lines other ON other.entryId = cl.entryId AND other.id != cl.id
      JOIN accounts otherAcc ON otherAcc.id = other.accountId
      WHERE cl.accountId = ?
        AND (SELECT COUNT(*) FROM journal_lines x WHERE x.entryId = cl.entryId) = 2
        $projectWhere $dateWhere
    ''', [account.id, ...projectArgs, ...dateArgs]);
    double newAdvances = 0, applied = 0, otherIncrease = 0, otherDecrease = 0;
    for (final row in rows) {
      final d = (row['d'] as num).toDouble();
      final c = (row['c'] as num).toDouble();
      final otherKey = row['otherSystemKey'] as String?;
      final otherAccountId = row['otherAccountId'] as int?;
      if (c > 0) {
        if (_isCashOrBankById(otherAccountId, accountsById)) {
          newAdvances += c;
        } else {
          otherIncrease += c;
        }
      }
      if (d > 0) {
        if (otherKey == kSystemKeyReceivable) {
          applied += d;
        } else {
          otherDecrease += d;
        }
      }
    }

    // همان اصلاح classifyCashFlow/arMovement: سطرهای متعلق به اسناد
    // غیر-دقیقاً-دوسطری نباید کامل از محاسبه حذف شوند - در «سایر» با علامت
    // صحیح لحاظ می‌شوند.
    final unclassified = await db.rawQuery('''
      SELECT COALESCE(SUM(cl.debit),0) as d, COALESCE(SUM(cl.credit),0) as c
      FROM journal_lines cl
      JOIN journal_entries je ON je.id = cl.entryId
      WHERE cl.accountId = ?
        AND (SELECT COUNT(*) FROM journal_lines x WHERE x.entryId = cl.entryId) != 2
        $projectWhere $dateWhere
    ''', [account.id, ...projectArgs, ...dateArgs]);
    otherIncrease += (unclassified.first['c'] as num).toDouble();
    otherDecrease += (unclassified.first['d'] as num).toDouble();

    return {
      'opening': opening,
      'newAdvances': newAdvances,
      'advanceApplied': applied,
      'other': otherIncrease - otherDecrease,
      'closing': closing,
    };
  }

  /// حرکت مانده بستانکاری مشتری (Customer Credit) در یک بازه. محدودیت
  /// مستند: در معماری فعلی هیچ مسیری برای «مصرف» این بستانکاری (usedCredit)
  /// وجود ندارد (طبق طراحی عمدی این پروژه، ماهیت مازاد باید توسط کاربر و
  /// از طریق سند دستی مشخص شود)؛ پس usedCredit را حدس نمی‌زنیم و فقط
  /// Opening/Closing/newCredit را با اطمینان گزارش می‌کنیم.
  Future<Map<String, double>> customerCreditMovement(
      {String? fromDate, String? toDate, int? projectId}) async {
    final account = await getCustomerCreditAccount();
    if (account == null) {
      return {'opening': 0, 'newCredit': 0, 'closing': 0};
    }
    final opening = fromDate != null
        ? await _filteredAccountBalance(
            accountId: account.id!,
            debitNormal: false,
            projectId: projectId,
            toDate: fromDate,
            exclusiveToDate: true)
        : 0.0;
    final closing = await _filteredAccountBalance(
        accountId: account.id!, debitNormal: false, projectId: projectId, toDate: toDate);
    return {
      'opening': opening,
      'newCredit': closing - opening, // چون usedCredit قابل تشخیص نیست، فقط خالص تغییر گزارش می‌شود
      'closing': closing,
    };
  }

  Future<void> wipeAll([DatabaseExecutor? executor]) async {
    final db = executor ?? await database;
    await db.delete('journal_lines');
    await db.delete('journal_entries');
    await db.delete('projects');
    await db.delete('counterparty_role_assignments');
    await db.delete('counterparties');
    await db.delete('accounts');
    await db.delete('sms_drafts');
    await _seedDefaultAccounts(db);
  }
}
