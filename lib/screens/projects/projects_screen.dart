import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/project.dart';
import '../../theme/app_theme.dart';
import 'project_form_screen.dart';
import 'project_detail_screen.dart';
import '../counterparties/counterparties_screen.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  final _db = DatabaseHelper.instance;
  List<ProjectModel> _projects = [];
  Map<int, String> _counterpartyNames = {};
  bool _loading = true;
  String _query = '';
  String? _statusFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final projects = await _db.getProjects(query: _query);
    final counterparties = await _db.getCounterparties(includeInactive: true);
    final names = {for (final c in counterparties) c.id!: c.name};
    setState(() {
      _projects = _statusFilter == null
          ? projects
          : projects.where((p) => p.status == _statusFilter).toList();
      _counterpartyNames = names;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('پروژه‌ها'),
        actions: [
          IconButton(
            icon: const Icon(Icons.people_alt_outlined),
            tooltip: 'اشخاص',
            onPressed: () async {
              await Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const CounterpartiesScreen()));
              _load();
            },
          ),
        ],
      ),
      body: BlueprintGridBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'جستجوی عنوان پروژه...',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: (v) {
                  _query = v;
                  _load();
                },
              ),
            ),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: const Text('همه'),
                      selected: _statusFilter == null,
                      onSelected: (_) {
                        _statusFilter = null;
                        _load();
                      },
                    ),
                  ),
                  ...kProjectStatuses.map((s) => Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text(s),
                          selected: _statusFilter == s,
                          onSelected: (_) {
                            _statusFilter = s;
                            _load();
                          },
                        ),
                      )),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _projects.isEmpty
                      ? const Center(
                          child: Text('پروژه‌ای یافت نشد',
                              style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _projects.length,
                          itemBuilder: (ctx, i) {
                            final p = _projects[i];
                            return Card(
                              child: ListTile(
                                leading: const Icon(Icons.work_outline, color: AppColors.brass),
                                title: Text(p.title),
                                subtitle: Text(
                                    '${_counterpartyNames[p.counterpartyId] ?? '—'} · ${p.projectType}'),
                                trailing: _StatusBadge(status: p.status),
                                onTap: () async {
                                  await Navigator.push(context,
                                      MaterialPageRoute(builder: (_) => ProjectDetailScreen(project: p)));
                                  _load();
                                },
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final result = await Navigator.push(
              context, MaterialPageRoute(builder: (_) => const ProjectFormScreen()));
          if (result == true) _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  Color _color() {
    switch (status) {
      case 'تکمیل شده':
        return AppColors.positive;
      case 'متوقف شده':
        return AppColors.negative;
      default:
        return AppColors.brass;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _color().withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _color()),
      ),
      child: Text(status, style: TextStyle(color: _color(), fontSize: 10)),
    );
  }
}
