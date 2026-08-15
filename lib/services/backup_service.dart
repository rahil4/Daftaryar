import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/client.dart';
import '../models/project.dart';
import '../models/project_transaction.dart';
import '../models/office_expense.dart';

class BackupService {
  final _db = DatabaseHelper.instance;

  Future<String> exportToFile() async {
    final clients = await _db.getClients();
    final projects = await _db.getProjects();
    final transactions = await _db.getTransactions();
    final expenses = await _db.getExpenses();

    final data = {
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'clients': clients.map((e) => e.toMap()).toList(),
      'projects': projects.map((e) => e.toMap()).toList(),
      'transactions': transactions.map((e) => e.toMap()).toList(),
      'expenses': expenses.map((e) => e.toMap()).toList(),
    };

    final dir = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/daftaryar_backup_$stamp.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));

    await Share.shareXFiles([XFile(file.path)], text: 'پشتیبان دفتریار');
    return file.path;
  }

  /// بازیابی از فایل انتخابی؛ در صورت replaceExisting=true ابتدا داده‌های فعلی پاک می‌شود
  Future<void> importFromPickedFile({bool replaceExisting = false}) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result == null || result.files.single.path == null) return;

    final file = File(result.files.single.path!);
    final content = await file.readAsString();
    final Map<String, dynamic> data = jsonDecode(content);

    if (replaceExisting) {
      await _db.wipeAll();
    }

    final Map<int, int> clientIdMap = {};
    for (final c in (data['clients'] as List)) {
      final client = ClientModel.fromMap(Map<String, dynamic>.from(c));
      final newId = await _db.insertClient(client);
      clientIdMap[client.id ?? -1] = newId;
    }

    final Map<int, int> projectIdMap = {};
    for (final p in (data['projects'] as List)) {
      final project = ProjectModel.fromMap(Map<String, dynamic>.from(p));
      final mappedClientId = clientIdMap[project.clientId] ?? project.clientId;
      final newId = await _db.insertProject(project.copyWith(clientId: mappedClientId));
      projectIdMap[project.id ?? -1] = newId;
    }

    for (final t in (data['transactions'] as List)) {
      final tx = ProjectTransactionModel.fromMap(Map<String, dynamic>.from(t));
      final mappedProjectId = projectIdMap[tx.projectId] ?? tx.projectId;
      await _db.insertTransaction(ProjectTransactionModel(
        projectId: mappedProjectId,
        type: tx.type,
        amount: tx.amount,
        date: tx.date,
        category: tx.category,
        description: tx.description,
      ));
    }

    for (final e in (data['expenses'] as List)) {
      final expense = OfficeExpenseModel.fromMap(Map<String, dynamic>.from(e));
      await _db.insertExpense(expense);
    }
  }
}
