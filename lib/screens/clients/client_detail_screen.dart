import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/client.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
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
  List<ProjectModel> _projects = [];
  late ClientModel _client;
  bool _loading = true;

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

  Future<void> _deleteClient() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف کارفرما'),
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
                  Text('پروژه‌های این کارفرما (${pn(_projects.length)})',
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
                  child: Text('پروژه‌ای برای این کارفرما ثبت نشده',
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
