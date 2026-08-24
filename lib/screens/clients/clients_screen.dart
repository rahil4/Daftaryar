import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/client.dart';
import '../../theme/app_theme.dart';
import 'client_form_screen.dart';
import 'client_detail_screen.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final _db = DatabaseHelper.instance;
  List<ClientModel> _clients = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getClients(query: _query);
    setState(() {
      _clients = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('اشخاص')),
      body: BlueprintGridBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'جستجوی نام یا شماره تماس...',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: (v) {
                  _query = v;
                  _load();
                },
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _clients.isEmpty
                      ? const Center(
                          child: Text('هنوز شخصی ثبت نشده است',
                              style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _clients.length,
                          itemBuilder: (ctx, i) {
                            final c = _clients[i];
                            return Card(
                              child: ListTile(
                                leading: const CircleAvatar(
                                  backgroundColor: AppColors.surfaceAlt,
                                  child: Icon(Icons.person_outline, color: AppColors.brass),
                                ),
                                title: Text(c.name),
                                subtitle: Text(
                                    '${c.relationType} · ${c.phone ?? 'بدون شماره تماس'}'),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => ClientDetailScreen(client: c)),
                                  );
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
              context, MaterialPageRoute(builder: (_) => const ClientFormScreen()));
          if (result == true) _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
