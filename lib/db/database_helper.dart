import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/client.dart';
import '../models/project.dart';
import '../models/account.dart';
import '../models/journal_entry.dart';

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
    final path = join(dbPath, 'daftaryar_v2.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: _onCreate,
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
        debit REAL NOT NULL DEFAULT 0,
        credit REAL NOT NULL DEFAULT 0,
        description TEXT,
        projectId INTEGER,
        FOREIGN KEY (entryId) REFERENCES journal_entries (id) ON DELETE CASCADE,
        FOREIGN KEY (accountId) REFERENCES accounts (id),
        FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE SET NULL
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

    await add('1000', 'صندوق', kAccountAsset);
    await add('1010', 'بانک', kAccountAsset);
    await add('1100', 'حساب‌های دریافتنی (بدهکاران)', kAccountAsset);

    await add('2000', 'حساب‌های پرداختنی (بستانکاران)', kAccountLiability);

    await add('3000', 'سرمایه', kAccountEquity);

    await add('4000', 'درآمد خدمات نقشه‌برداری و ثبتی', kAccountIncome);

    final officeGroupId = await add('5000', 'هزینه‌های عمومی دفتر', kAccountExpense);
    await add('5001', 'اجاره', kAccountExpense, parentId: officeGroupId);
    await add('5002', 'حقوق و دستمزد', kAccountExpense, parentId: officeGroupId);
    await add('5003', 'قبوض و انشعابات', kAccountExpense, parentId: officeGroupId);
    await add('5004', 'تجهیزات و نرم‌افزار', kAccountExpense, parentId: officeGroupId);
    await add('5005', 'حمل و نقل', kAccountExpense, parentId: officeGroupId);
    await add('5006', 'پذیرایی و اداری', kAccountExpense, parentId: officeGroupId);
    await add('5007', 'سایر هزینه‌های عمومی', kAccountExpense, parentId: officeGroupId);

    final projectGroupId = await add('5100', 'هزینه‌های مستقیم پروژه', kAccountExpense);
    await add('5101', 'حق‌الزحمه همکار', kAccountExpense, parentId: projectGroupId);
    await add('5102', 'هزینه نقشه‌برداری میدانی', kAccountExpense, parentId: projectGroupId);
    await add('5103', 'هزینه اداری/ثبتی پروژه', kAccountExpense, parentId: projectGroupId);
    await add('5104', 'سایر هزینه‌های پروژه', kAccountExpense, parentId: projectGroupId);
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

  Future<AccountModel?> getAccount(int id) async {
    final db = await database;
    final maps = await db.query('accounts', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return AccountModel.fromMap(maps.first);
  }

  // ---------------- Journal (اسناد حسابداری) ----------------
  Future<int> insertJournalEntry(JournalEntryModel entry) async {
    if (!entry.isBalanced) {
      throw Exception('سند حسابداری باید متوازن باشد (جمع بدهکار = جمع بستانکار).');
    }
    final db = await database;
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
      if (projectId != null) lineWhere += ' AND projectId = ${projectId}';
      if (accountId != null) lineWhere += ' AND accountId = ${accountId}';
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
  Future<Map<String, double>> expenseBreakdown({String? fromDate, String? toDate}) async {
    final expenseAccounts = await getAccounts(type: kAccountExpense);
    final Map<String, double> breakdown = {};
    for (final acc in expenseAccounts) {
      // فقط حساب‌های برگ (بدون زیرحساب) را برای جلوگیری از شمارش دوباره لحاظ می‌کنیم
      final hasChildren = expenseAccounts.any((a) => a.parentId == acc.id);
      if (hasChildren) continue;
      final bal = await accountBalance(acc.id!, fromDate: fromDate, toDate: toDate);
      final balance = bal['balance']!;
      if (balance != 0) breakdown[acc.name] = balance;
    }
    return breakdown;
  }

  Future<void> wipeAll() async {
    final db = await database;
    await db.delete('journal_lines');
    await db.delete('journal_entries');
    await db.delete('projects');
    await db.delete('clients');
    await db.delete('accounts');
    await _seedDefaultAccounts(db);
  }
}
