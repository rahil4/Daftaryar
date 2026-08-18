import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/client.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../services/pdf_export_service.dart';
import 'client_form_screen.dart';
import '../projects/project_detail_screen.dart';
import '../projects/project_form_screen.dart';

class ClientDetailScreen extends StatefulWidget {
  final ClientModel client;
  const ClientDetailScreen({super.key, required this.client});

  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  final _db = DatabaseHelper.instance;
  final _pdf = PdfExportService();
  List<ProjectModel> _projects = [];
  late ClientModel _client;
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _client = widget.client;
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getProjects(clientId: _client.id);
    setState(() {
      _projects = list;
      _loading = false;
    });
  }

  Future<void> _exportStatement() async {
    setState(() => _exporting = true);
    try {
      final projectRows = <Map<String, dynamic>>[];
      final transactions = <Map<String, dynamic>>[];

      for (final p in _projects) {
        final fin = await _db.projectFinancials(p.id!);
        final received = fin['received']!;
        projectRows.add({
          'title': p.title,
          'agreedAmount': p.agreedAmount,
          'received': received,
          'remaining': p.agreedAmount - received,
        });

        final entries = await _db.getJournalEntries(projectId: p.id);
        for (final e in entries) {
          for (final l in e.lines) {
            if (l.projectId != p.id) continue;
            if (l.debit == 0 && l.credit == 0) continue;
            transactions.add({
              'date': e.date,
              'description': e.description ?? p.title,
              'type': l.credit > 0 ? 'دریافت' : 'پرداخت',
              'amount': l.credit > 0 ? l.credit : l.debit,
            });
          }
        }
      }
      transactions.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));

      await _pdf.exportClientStatement(
        clientName: _client.name,
        clientPhone: _client.phone,
        projectRows: projectRows,
        transactions: transactions,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _deleteClient() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف شخص'),
        content: Text(
            'با حذف «${_client.name}» تمام پروژه‌ها و تراکنش‌های مرتبط با آن نیز حذف خواهد شد. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: AppColors.negative))),
        ],
      ),
    );
    if (confirm == true && _client.id != null) {
      await _db.deleteClient(_client.id!);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_client.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final result = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ClientFormScreen(existing: _client)));
              if (result == true) {
                final updated = await _db.getClient(_client.id!);
                if (updated != null) setState(() => _client = updated);
              }
            },
          ),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteClient),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _exporting ? null : _exportStatement,
        icon: _exporting
            ? const SizedBox(
                height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('خروجی صورتحساب'),
      ),
      body: BlueprintGridBackground(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_client.phone != null) _infoRow(Icons.phone_outlined, _client.phone!),
                      if (_client.nationalId != null)
                        _infoRow(Icons.badge_outlined, _client.nationalId!),
                      if (_client.address != null)
                        _infoRow(Icons.location_on_outlined, _client.address!),
                      if (_client.notes != null) _infoRow(Icons.notes_outlined, _client.notes!),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('پروژه‌های این شخص (${pn(_projects.length)})',
                      style: Theme.of(context).textTheme.titleMedium),
                  TextButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ProjectFormScreen(presetClient: _client)),
                      );
                      if (result == true) _load();
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('پروژه جدید'),
                  ),
                ],
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.only(top: 30),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 20),
                  child: Text('پروژه‌ای برای این شخص ثبت نشده',
                      style: TextStyle(color: AppColors.textSecondary)),
                )
              else
                ..._projects.map((p) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.work_outline, color: AppColors.brass),
                        title: Text(p.title),
                        subtitle: Text('${p.projectType} · ${p.status}'),
                        trailing: const Icon(Icons.chevron_left),
                        onTap: () async {
                          await Navigator.push(context,
                              MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p)));
                          _load();
                        },
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
