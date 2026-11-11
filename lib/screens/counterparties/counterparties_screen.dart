import 'dart:async';

import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/counterparty.dart';
import '../../theme/app_theme.dart';
import 'counterparty_form_screen.dart';
import 'counterparty_detail_screen.dart';

class CounterpartiesScreen extends StatefulWidget {
  const CounterpartiesScreen({super.key});

  @override
  State<CounterpartiesScreen> createState() => _CounterpartiesScreenState();
}

class _CounterpartiesScreenState extends State<CounterpartiesScreen> {
  final _db = DatabaseHelper.instance;
  List<CounterpartyModel> _counterparties = [];
  bool _loading = true;
  bool _showInactive = false;
  String _query = '';
  Timer? _searchDebounce;
  // نتیجه دیرتر-رسیده یک جستجوی قدیمی نباید روی نتیجه جستجوی جدید بنشیند.
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// جستجو با مکث کوتاه پس از آخرین حرف اجرا می‌شود، نه با هر حرف.
  void _onQueryChanged(String value) {
    _query = value;
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), _load);
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    setState(() => _loading = true);
    final list = await _db.getCounterparties(query: _query, includeInactive: _showInactive);
    if (!mounted || token != _loadToken) return;
    setState(() {
      _counterparties = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طرف‌های حساب')),
      body: BlueprintGridBackground(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
              child: TextField(
                decoration: const InputDecoration(
                  hintText: 'جستجوی نام یا شماره تماس...',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onChanged: _onQueryChanged,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('نمایش غیرفعال‌ها هم'),
                    selected: _showInactive,
                    onSelected: (v) {
                      _showInactive = v;
                      _load();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _counterparties.isEmpty
                      ? Center(
                          child: Text(
                              _query.isNotEmpty
                                  ? 'نتیجه‌ای برای این جستجو یافت نشد'
                                  : 'هنوز طرف حسابی ثبت نشده است',
                              style: const TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _counterparties.length,
                          itemBuilder: (ctx, i) {
                            final c = _counterparties[i];
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: AppColors.surfaceAlt,
                                  child: Icon(
                                    Icons.person_outline,
                                    color: c.isActive ? AppColors.brass : AppColors.textSecondary,
                                  ),
                                ),
                                title: Text(
                                  c.name,
                                  style: c.isActive
                                      ? null
                                      : const TextStyle(
                                          color: AppColors.textSecondary,
                                          decoration: TextDecoration.lineThrough),
                                ),
                                subtitle: Text(
                                    '${c.roles.join('، ')}${c.phone != null ? ' · ${c.phone}' : ''}'),
                                trailing: const Icon(Icons.chevron_left),
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => CounterpartyDetailScreen(counterparty: c)),
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
              context, MaterialPageRoute(builder: (_) => const CounterpartyFormScreen()));
          if (result == true) _load();
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}
