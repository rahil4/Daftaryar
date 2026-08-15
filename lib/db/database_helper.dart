import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

import '../models/client.dart';
import '../models/project.dart';
import '../models/project_transaction.dart';
import '../models/office_expense.dart';

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
    final path = join(dbPath, 'daftaryar.db');
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
      CREATE TABLE project_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        projectId INTEGER NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        category TEXT NOT NULL,
        description TEXT,
        FOREIGN KEY (projectId) REFERENCES projects (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE office_expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        category TEXT NOT NULL,
        amount REAL NOT NULL,
        date TEXT NOT NULL,
        description TEXT
      )
    ''');
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

  // ---------------- Project Transactions ----------------
  Future<int> insertTransaction(ProjectTransactionModel t) async {
    final db = await database;
    return db.insert('project_transactions', t.toMap()..remove('id'));
  }

  Future<int> deleteTransaction(int id) async {
    final db = await database;
    return db.delete('project_transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<ProjectTransactionModel>> getTransactions({int? projectId}) async {
    final db = await database;
    final maps = projectId == null
        ? await db.query('project_transactions', orderBy: 'id DESC')
        : await db.query('project_transactions',
            where: 'projectId = ?', whereArgs: [projectId], orderBy: 'id DESC');
    return maps.map((m) => ProjectTransactionModel.fromMap(m)).toList();
  }

  // ---------------- Office Expenses ----------------
  Future<int> insertExpense(OfficeExpenseModel e) async {
    final db = await database;
    return db.insert('office_expenses', e.toMap()..remove('id'));
  }

  Future<int> deleteExpense(int id) async {
    final db = await database;
    return db.delete('office_expenses', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<OfficeExpenseModel>> getExpenses() async {
    final db = await database;
    final maps = await db.query('office_expenses', orderBy: 'id DESC');
    return maps.map((m) => OfficeExpenseModel.fromMap(m)).toList();
  }

  // ---------------- Aggregates ----------------
  Future<double> sumProjectTransactions(int projectId, String type) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) as total FROM project_transactions WHERE projectId = ? AND type = ?',
        [projectId, type]);
    return (result.first['total'] as num).toDouble();
  }

  Future<double> sumAllTransactionsByType(String type) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) as total FROM project_transactions WHERE type = ?',
        [type]);
    return (result.first['total'] as num).toDouble();
  }

  Future<double> sumAllExpenses() async {
    final db = await database;
    final result = await db
        .rawQuery('SELECT COALESCE(SUM(amount), 0) as total FROM office_expenses');
    return (result.first['total'] as num).toDouble();
  }

  Future<Map<String, double>> expensesByCategory() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT category, COALESCE(SUM(amount),0) as total FROM office_expenses GROUP BY category');
    return {for (final row in result) row['category'] as String: (row['total'] as num).toDouble()};
  }

  Future<void> wipeAll() async {
    final db = await database;
    await db.delete('project_transactions');
    await db.delete('office_expenses');
    await db.delete('projects');
    await db.delete('clients');
  }
}
