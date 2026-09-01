import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/sms_draft.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'sms_draft_review_screen.dart';

class SmsDraftsScreen extends StatefulWidget {
  const SmsDraftsScreen({super.key});

  @override
  State<SmsDraftsScreen> createState() => _SmsDraftsScreenState();
}

class _SmsDraftsScreenState extends State<SmsDraftsScreen> {
  final _db = DatabaseHelper.instance;
  List<SmsDraftModel> _drafts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final list = await _db.getSmsDrafts();
    setState(() {
      _drafts = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('پیش‌نویس‌های پیامکی')),
      body: BlueprintGridBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _drafts.isEmpty
                ? const Center(
                    child: Text('پیش‌نویس در انتظاری وجود ندارد',
                        style: TextStyle(color: AppColors.textSecondary)))
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _drafts.length,
                      itemBuilder: (ctx, i) {
                        final d = _drafts[i];
                        final isReceipt = d.type == 'دریافت';
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              isReceipt ? Icons.south_west_rounded : Icons.north_east_rounded,
                              color: isReceipt ? AppColors.positive : AppColors.negative,
                            ),
                            title: Text(formatMoney(d.amount)),
                            subtitle: Text(
                              '${d.type} · ${formatJalaliLong(d.date)}\n${d.rawBody}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            trailing: const Text('‹', style: TextStyle(color: AppColors.textSecondary)),
                            onTap: () async {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => SmsDraftReviewScreen(draft: d)),
                              );
                              _load();
                            },
                          ),
                        );
                      },
                    ),
                  ),
      ),
    );
  }
}
