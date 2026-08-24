import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/client.dart';
import '../models/project.dart';
import '../models/account.dart';
import '../models/journal_entry.dart';

class BackupService {
  final _db = DatabaseHelper.instance;

  Future<String> exportToFile() async {
    final clients = await _db.getClients();
    final projects = await _db.getProjects();
    final accounts = await _db.getAccounts();
    final entries = await _db.getJournalEntries();
    final settings = await _db.getAllSettings();

    final data = {
      'version': 3,
      'exportedAt': DateTime.now().toIso8601String(),
      'clients': clients.map((e) => e.toMap()).toList(),
      'projects': projects.map((e) => e.toMap()).toList(),
      'accounts': accounts.map((e) => e.toMap()).toList(),
      'journalEntries': entries
          .map((e) => {
                ...e.toMap(),
                'lines': e.lines.map((l) => l.toMap()).toList(),
              })
          .toList(),
      'settings': settings,
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
    for (final c in (data['clients'] as List? ?? [])) {
      final client = ClientModel.fromMap(Map<String, dynamic>.from(c));
      final newId = await _db.insertClient(client);
      clientIdMap[client.id ?? -1] = newId;
    }

    final Map<int, int> projectIdMap = {};
    for (final p in (data['projects'] as List? ?? [])) {
      final project = ProjectModel.fromMap(Map<String, dynamic>.from(p));
      final mappedClientId = clientIdMap[project.clientId] ?? project.clientId;
      final newId = await _db.insertProject(project.copyWith(clientId: mappedClientId));
      projectIdMap[project.id ?? -1] = newId;
    }

    // حساب‌ها: فقط حساب‌های غیرسیستمی اضافه می‌شوند (حساب‌های پیش‌فرض از قبل موجودند)
    final Map<int, int> accountIdMap = {};
    final existingAccounts = await _db.getAccounts();
    for (final a in (data['accounts'] as List? ?? [])) {
      final account = AccountModel.fromMap(Map<String, dynamic>.from(a));
      if (account.isSystem) {
        // تطبیق با حساب سیستمی موجود بر اساس نام و نوع
        final match = existingAccounts.where((x) => x.isSystem && x.name == account.name && x.type == account.type);
        if (match.isNotEmpty) {
          accountIdMap[account.id ?? -1] = match.first.id!;
          continue;
        }
      }
      final mappedParentId =
          account.parentId != null ? (accountIdMap[account.parentId] ?? account.parentId) : null;
      final newId = await _db.insertAccount(account.copyWith(
        parentId: mappedParentId,
        clearParent: mappedParentId == null,
        isSystem: false,
      ));
      accountIdMap[account.id ?? -1] = newId;
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
        final originalClientId = lm['clientId'] as int?;
        final mappedClientId =
            originalClientId != null ? (clientIdMap[originalClientId] ?? originalClientId) : null;
        return JournalLineModel(
          accountId: mappedAccountId,
          debit: (lm['debit'] as num).toDouble(),
          credit: (lm['credit'] as num).toDouble(),
          description: lm['description'] as String?,
          projectId: mappedProjectId,
          clientId: mappedClientId,
        );
      }).toList();

      final entry = JournalEntryModel(
        date: map['date'] as String,
        description: map['description'] as String?,
        createdAt: map['createdAt'] as String? ?? map['date'] as String,
        lines: lines,
      );
      if (entry.isBalanced) {
        await _db.insertJournalEntry(entry);
      }
    }

    // تنظیمات برنامه (سال مالی، قفل امنیتی، پیامک بانکی و...)
    final settingsRaw = data['settings'];
    if (settingsRaw is Map) {
      final settings = settingsRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
      await _db.setAllSettings(settings);
    }
  }
}
