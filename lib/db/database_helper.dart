import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../models/client.dart';
import '../models/project.dart';
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
    final path = join(dbPath, 'daftaryar_v6.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
      onConfigure: (db) async {
        // بدون این، قیدهای ON DELETE CASCADE / SET NULL در جداول عملاً نادیده گرفته
        // می‌شدند و حذف کارفرما/پروژه باعث باقی‌ماندن رکوردهای یتیم می‌شد
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE clients (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT,
        nationalId TEXT,
        address TEXT,
        notes TEXT,
        relationType TEXT NOT NULL DEFAULT 'کارفرما',
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE projects (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        clientId INTEGER NOT NULL,
        projectType TEXT NOT NULL,
        status TEXT NOT NULL,
        startDate TEXT NOT NULL,
        agreedAmount REAL NOT NULL DEFAULT 0,
        description TEXT,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (clientId) REFERENCES clients (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE accounts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        code TEXT,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        parentId INTEGER,
        isSystem INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (parentId) REFERENCES accounts (id) ON DELETE SET NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE journal_entries (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        description TEXT,
        createdAt TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE journal_lines (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        entryId INTEGER NOT NULL,
        accountId INTEGER NOT NULL,
        debit INTEGER NOT NULL DEFAULT 0,
        credit INTEGER NOT NULL DEFAULT 0,
        description TEXT,
        projectId INTEGER,
        clientId INTEGER,
        FOREIGN KEY (entryId) REFERENCES journal_entries (id) ON DELETE CASCADE,
        FOREIGN KEY (accountId) REFERENCES accounts (id),
        FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE SET NULL,
        FOREIGN KEY (clientId) REFERENCES clients (id) ON DELETE SET NULL,
        CHECK (debit >= 0 AND credit >= 0),
        CHECK (NOT (debit > 0 AND credit > 0)),
        CHECK (NOT (debit = 0 AND credit = 0))
      )
    ''');

    await db.execute('CREATE INDEX idx_journal_lines_entryId ON journal_lines (entryId)');
    await db.execute('CREATE INDEX idx_journal_lines_accountId ON journal_lines (accountId)');

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

  Future<void> _seedDefaultAccounts(Database db) async {
    final now = DateTime.now().toIso8601String();
    Future<int> add(String code, String name, String type, {int? parentId}) {
      return db.insert('accounts', {
        'code': code,
        'name': name,
        'type': type,
        'parentId': parentId,
        'isSystem': 1,
        'createdAt': now,
      });
    }

    // دارایی
    await add('1000', 'صندوق', kAccountAsset);
    await add('1010', 'بانک', kAccountAsset);
    await add('1100', 'حساب‌های دریافتنی', kAccountAsset);

    // بدهی
    await add('2000', 'حساب‌های پرداختنی', kAccountLiability);

    // حقوق صاحبان سرمایه
    await add('3000', 'سرمایه', kAccountEquity);

    // درآمد
    await add('4000', 'درآمد نقشه‌برداری', kAccountIncome);
    await add('4010', 'درآمد پیگیری ثبتی', kAccountIncome);
    await add('4090', 'سایر درآمدها', kAccountIncome);

    // هزینه
    await add('5000', 'هزینه‌های دفتر', kAccountExpense);
    await add('5010', 'هزینه‌های ثبتی/اداری پروژه', kAccountExpense);
    await add('5020', 'حقوق و دستمزد', kAccountExpense);
    await add('5030', 'هزینه‌های نقشه‌برداری', kAccountExpense);
    await add('5040', 'حمل و نقل', kAccountExpense);
    await add('5090', 'سایر هزینه‌های عمومی', kAccountExpense);
  }

  // ---------------- Clients ----------------
  Future<int> insertClient(ClientModel c) async {
    final db = await database;
    return db.insert('clients', c.toMap()..remove('id'));
  }

  Future<int> updateClient(ClientModel c) async {
    final db = await database;
    return db.update('clients', c.toMap(), where: 'id = ?', whereArgs: [c.id]);
  }

  Future<int> deleteClient(int id) async {
    final db = await database;
    return db.delete('clients', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ClientModel>> getClients({String? query}) async {
    final db = await database;
    final maps = query == null || query.isEmpty
        ? await db.query('clients', orderBy: 'name ASC')
        : await db.query('clients',
            where: 'name LIKE ? OR phone LIKE ?',
            whereArgs: ['%$query%', '%$query%'],
            orderBy: 'name ASC');
    return maps.map((m) => ClientModel.fromMap(m)).toList();
  }

  Future<ClientModel?> getClient(int id) async {
    final db = await database;
    final maps = await db.query('clients', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return ClientModel.fromMap(maps.first);
  }

  // ---------------- Projects ----------------
  Future<int> insertProject(ProjectModel p) async {
    final db = await database;
    return db.insert('projects', p.toMap()..remove('id'));
  }

  Future<int> updateProject(ProjectModel p) async {
    final db = await database;
    return db.update('projects', p.toMap(), where: 'id = ?', whereArgs: [p.id]);
  }

  Future<int> deleteProject(int id) async {
    final db = await database;
    return db.delete('projects', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ProjectModel>> getProjects({int? clientId, String? query}) async {
    final db = await database;
    String? where;
    List<Object?> args = [];
    if (clientId != null) {
      where = 'clientId = ?';
      args.add(clientId);
    }
    if (query != null && query.isNotEmpty) {
      where = where == null ? 'title LIKE ?' : '$where AND title LIKE ?';
      args.add('%$query%');
    }
    final maps = await db.query('projects',
        where: where, whereArgs: args.isEmpty ? null : args, orderBy: 'id DESC');
    return maps.map((m) => ProjectModel.fromMap(m)).toList();
  }

  Future<ProjectModel?> getProject(int id) async {
    final db = await database;
    final maps = await db.query('projects', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return ProjectModel.fromMap(maps.first);
  }

  // ---------------- Accounts ----------------
  Future<int> insertAccount(AccountModel a) async {
    final db = await database;
    return db.insert('accounts', a.toMap()..remove('id'));
  }

  Future<int> updateAccount(AccountModel a) async {
    final db = await database;
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

  Future<List<AccountModel>> getAccounts({String? type}) async {
    final db = await database;
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

  Future<AccountModel?> getAccount(int id) async {
    final db = await database;
    final maps = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return AccountModel.fromMap(maps.first);
  }

  // ---------------- Journal (اسناد حسابداری) ----------------
  /// نقطه مرکزی و تنها مسیر مجاز برای ثبت سند حسابداری در کل برنامه.
  /// تمام قوانین پایه Double-Entry اینجا enforce می‌شوند تا هیچ مسیر دیگری
  /// (فرم سریع، سند دستی، بازیابی پشتیبان، پیش‌نویس پیامکی) نتواند آن‌ها را
  /// دور بزند.
  Future<int> insertJournalEntry(JournalEntryModel entry) async {
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

    final db = await database;

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

    // ثبت اتمیک: هدر سند و همه سطرهایش در یک تراکنش دیتابیس - در صورت بروز
    // هر خطا (مثلاً نقض یکی از CHECK constraint های سطح دیتابیس)، کل عملیات
    // rollback می‌شود و نه هدر ناقص باقی می‌ماند و نه سطر یتیم.
    return db.transaction((txn) async {
      final entryId = await txn.insert('journal_entries', entry.toMap()..remove('id'));
      for (final line in entry.lines) {
        final map = line.toMap()
          ..remove('id')
          ..['entryId'] = entryId;
        await txn.insert('journal_lines', map);
      }
      return entryId;
    });
  }

  Future<void> deleteJournalEntry(int id) async {
    final db = await database;
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
  Future<Map<String, double>> projectFinancials(int projectId) async {
    final db = await database;
    final receivedResult = await db.rawQuery('''
      SELECT COALESCE(SUM(l.credit),0) as total
      FROM journal_lines l JOIN accounts a ON a.id = l.accountId
      WHERE l.projectId = ? AND a.type = ?
    ''', [projectId, kAccountIncome]);
    final spentResult = await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit),0) as total
      FROM journal_lines l JOIN accounts a ON a.id = l.accountId
      WHERE l.projectId = ? AND a.type = ?
    ''', [projectId, kAccountExpense]);
    return {
      'received': (receivedResult.first['total'] as num).toDouble(),
      'spent': (spentResult.first['total'] as num).toDouble(),
    };
  }

  /// دریافتی/پرداختی یک شخص — هم از راه پروژه‌های او، هم از سندهایی که
  /// مستقیم (بدون پروژه) به او برچسب خورده‌اند
  Future<Map<String, double>> clientFinancials(int clientId) async {
    final db = await database;
    final receivedResult = await db.rawQuery('''
      SELECT COALESCE(SUM(l.credit),0) as total
      FROM journal_lines l JOIN accounts a ON a.id = l.accountId
      WHERE a.type = ? AND (l.clientId = ? OR l.projectId IN (SELECT id FROM projects WHERE clientId = ?))
    ''', [kAccountIncome, clientId, clientId]);
    final spentResult = await db.rawQuery('''
      SELECT COALESCE(SUM(l.debit),0) as total
      FROM journal_lines l JOIN accounts a ON a.id = l.accountId
      WHERE a.type = ? AND (l.clientId = ? OR l.projectId IN (SELECT id FROM projects WHERE clientId = ?))
    ''', [kAccountExpense, clientId, clientId]);
    return {
      'received': (receivedResult.first['total'] as num).toDouble(),
      'spent': (spentResult.first['total'] as num).toDouble(),
    };
  }

  /// اسناد ثبت‌شده مستقیم برای یک شخص (بدون واسطه پروژه)
  Future<List<JournalEntryModel>> getDirectClientEntries(int clientId) async {
    final db = await database;
    final entryMaps = await db.rawQuery('''
      SELECT DISTINCT e.* FROM journal_entries e
      JOIN journal_lines l ON l.entryId = e.id
      WHERE l.clientId = ?
      ORDER BY e.date DESC, e.id DESC
    ''', [clientId]);
    final entries = <JournalEntryModel>[];
    for (final em in entryMaps) {
      final lineMaps = await db.query('journal_lines',
          where: 'entryId = ?', whereArgs: [em['id']], orderBy: 'id ASC');
      final lines = lineMaps.map((m) => JournalLineModel.fromMap(m)).toList();
      entries.add(JournalEntryModel.fromMap(em, lines: lines));
    }
    return entries;
  }

  /// خلاصه دریافتی/پرداختی همه اشخاص، برای گزارش «مطالبات و بدهی‌ها»
  Future<List<Map<String, dynamic>>> allClientsFinancialSummary() async {
    final clients = await getClients();
    final result = <Map<String, dynamic>>[];
    for (final c in clients) {
      final fin = await clientFinancials(c.id!);
      result.add({'client': c, 'received': fin['received']!, 'spent': fin['spent']!});
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
  Future<void> setSetting(String key, String value) async {
    final db = await database;
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

  Future<void> setAllSettings(Map<String, String> settings) async {
    for (final entry in settings.entries) {
      await setSetting(entry.key, entry.value);
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

  Future<void> wipeAll() async {
    final db = await database;
    await db.delete('journal_lines');
    await db.delete('journal_entries');
    await db.delete('projects');
    await db.delete('clients');
    await db.delete('accounts');
    await db.delete('sms_drafts');
    await _seedDefaultAccounts(db);
  }
}
