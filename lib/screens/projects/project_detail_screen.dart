import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/counterparty.dart';
import '../../models/project.dart';
import '../../models/journal_entry.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/quick_add_sheet.dart';
import '../../widgets/project_receipt_context_box.dart';
import '../journal/journal_entry_detail_screen.dart';
import 'project_form_screen.dart';
import 'project_finance_screen.dart';
import 'project_economics_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  final ProjectModel project;
  const ProjectDetailScreen({super.key, required this.project});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);
  final _db = DatabaseHelper.instance;
  late ProjectModel _project;
  CounterpartyModel? _counterparty;
  List<JournalEntryModel> _entries = [];
  Map<String, dynamic>? _summary;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _project = widget.project;
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final client = await _db.getCounterparty(_project.counterpartyId);
    final entries = await _db.getJournalEntries(projectId: _project.id);
    final summary = await _db.projectFinancialSummary(_project.id!);
    setState(() {
      _counterparty = client;
      _entries = entries;
      _summary = summary;
      _loading = false;
    });
  }

  /// لغو پروژه: یک Workflow مستقل و کوچک، نه یک انتخاب ساده در فرم عمومی
  /// ویرایش پروژه. اطلاعات مالی (اسناد، رویدادهای قیمت) دست‌نخورده می‌مانند؛
  /// فقط وضعیت عملیاتی پروژه تغییر می‌کند.
  Future<void> _cancelProject() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('لغو پروژه'),
        content: const Text(
            'وضعیت این پروژه به «لغوشده» تغییر می‌کند. اسناد مالی و تاریخچه قیمت حذف نمی‌شوند. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('لغو پروژه', style: TextStyle(color: AppColors.negative))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _db.cancelProject(_project.id!);
        final updated = await _db.getProject(_project.id!);
        if (updated != null && mounted) setState(() => _project = updated);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        }
      }
    }
  }

  Future<void> _deleteProject() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف پروژه'),
        content: const Text(
            'اگر این پروژه سند مالی یا تاریخچه تغییر مبلغ ثبت‌شده داشته باشد، برای حفظ سوابق قابل حذف نخواهد بود. ادامه می‌دهید؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('انصراف')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف', style: TextStyle(color: AppColors.negative))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await _db.deleteProject(_project.id!);
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))));
        }
      }
    }
  }

  void _showAddOptions() {
    showQuickAddSheet(context, presetProjectId: _project.id, onDone: _load);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_project.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final result = await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => ProjectFormScreen(existing: _project)));
              if (result == true) {
                final updated = await _db.getProject(_project.id!);
                if (updated != null) setState(() => _project = updated);
                _load();
              }
            },
          ),
          if (_project.status != kProjectStatusCancelled &&
              _project.status != kProjectStatusFinalized)
            IconButton(
              icon: const Icon(Icons.block_outlined),
              tooltip: 'لغو پروژه',
              onPressed: _cancelProject,
            ),
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _deleteProject),
        ],
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'خلاصه'),
            Tab(text: 'مالی'),
            Tab(text: 'اقتصاد'),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : BlueprintGridBackground(
              child: TabBarView(
                controller: _tab,
                children: [
                  _SummaryTab(
                    project: _project,
                    counterparty: _counterparty,
                    entries: _entries,
                    summary: _summary!,
                    onLoad: _load,
                    onAddOptions: _showAddOptions,
                  ),
                  ProjectFinanceScreen(project: _project, embedded: true),
                  ProjectEconomicsScreen(projectId: _project.id!, embedded: true),
                ],
              ),
            ),
    );
  }
}

/// تب «خلاصه» - کارت اطلاعات کلی، آمار سریع، و فهرست اسناد این پروژه.
/// جزئیات مالی کامل (Finalization/تخفیف/طلب) و تحلیل اقتصادی اکنون تب‌های
/// همسطح مستقل خودشان هستند، نه دکمه‌ای که کاربر را از این صفحه خارج کند.
class _SummaryTab extends StatelessWidget {
  final ProjectModel project;
  final CounterpartyModel? counterparty;
  final List<JournalEntryModel> entries;
  final Map<String, dynamic> summary;
  final VoidCallback onLoad;
  final VoidCallback onAddOptions;

  const _SummaryTab({
    required this.project,
    required this.counterparty,
    required this.entries,
    required this.summary,
    required this.onLoad,
    required this.onAddOptions,
  });

  @override
  Widget build(BuildContext context) {
    final initialEstimate = summary['initialEstimate'] as double;
    final currentExpected = summary['currentExpectedAmount'] as double?;
    final isFinalized = summary['isFinalized'] as bool;
    final grossFinalAmount = summary['grossFinalAmount'] as double?;
    final discount = summary['discount'] as double? ?? 0;
    final netRevenue = summary['netRevenue'] as double?;
    final totalReceived = summary['totalReceived'] as double? ?? 0;
    final directProjectCost = summary['directProjectCost'] as double? ?? 0;
    final remainingInfo = computeProjectRemaining(project, summary);
    final remaining = remainingInfo.value;
    // «مبلغ فعلی/نهایی» که در کارت آماری اصلی نشان داده می‌شود: پیش از
    // Finalization برآورد فعلی (پس از اعمال تاریخچه تغییرات)، پس از آن
    // درآمد خالص واقعی.
    final displayAmount = isFinalized ? (netRevenue ?? initialEstimate) : (currentExpected ?? initialEstimate);
    final hasChanged = !isFinalized && currentExpected != null && currentExpected != initialEstimate;

    return RefreshIndicator(
      onRefresh: () async => onLoad(),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.person_outline, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text(counterparty?.name ?? '—'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.category_outlined, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text('${project.projectTypes.join('، ')} · ${project.status}'),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.event_outlined, size: 16, color: AppColors.textSecondary),
                      const SizedBox(width: 6),
                      Text('شروع: ${formatJalaliLong(project.startDate)}'),
                    ],
                  ),
                  if (project.description != null) ...[
                    const SizedBox(height: 8),
                    Text(project.description!, style: const TextStyle(color: AppColors.textSecondary)),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // کارت «روند مبلغ پروژه» - رابطهٔ برآورد اولیه و مبلغ فعلی/نهایی
          // را صریح نشان می‌دهد، به‌جای یک عدد تنها که معلوم نبود مربوط به
          // کدام مرحله است.
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('روند مبلغ پروژه', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 10),
                  _amountRow('برآورد اولیه (زمان ایجاد پروژه)', formatMoney(initialEstimate)),
                  if (!isFinalized) ...[
                    if (hasChanged) ...[
                      const SizedBox(height: 4),
                      _amountRow(
                        'مبلغ فعلی (پس از تغییرات)',
                        formatMoney(currentExpected),
                        badge: _deltaBadge(currentExpected - initialEstimate),
                        bold: true,
                      ),
                    ] else
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text('هنوز تغییری نسبت به برآورد اولیه ثبت نشده',
                            style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ),
                  ] else ...[
                    const SizedBox(height: 4),
                    _amountRow('مبلغ نهایی ناخالص', formatMoney(grossFinalAmount ?? 0)),
                    if (discount > 0) _amountRow('تخفیف', '- ${formatMoney(discount)}'),
                    const Divider(),
                    _amountRow('درآمد خالص (مبنای محاسبات پس از نهایی‌سازی)', formatMoney(netRevenue ?? 0),
                        bold: true),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              StatCard(
                title: isFinalized ? 'درآمد خالص (نهایی)' : 'مبلغ فعلی (برآورد)',
                value: formatMoney(displayAmount),
                icon: Icons.description_outlined,
              ),
              StatCard(
                title: 'مجموع دریافتی',
                value: formatMoney(totalReceived),
                icon: Icons.south_west_rounded,
                valueColor: AppColors.positive,
              ),
              StatCard(
                title: 'هزینه مستقیم پروژه',
                value: formatMoney(directProjectCost),
                icon: Icons.north_east_rounded,
                valueColor: AppColors.negative,
              ),
              StatCard(
                title: remainingInfo.label,
                value: remaining == null ? '—' : formatMoney(remaining.abs()),
                icon: Icons.account_balance_wallet_outlined,
                valueColor: remaining == null
                    ? AppColors.textSecondary
                    : (remaining > 0 ? AppColors.brass : AppColors.positive),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('اسناد این پروژه (${pn(entries.length)})', style: Theme.of(context).textTheme.titleMedium),
              TextButton.icon(
                onPressed: onAddOptions,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('ثبت جدید'),
              ),
            ],
          ),
          if (entries.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child:
                  Text('هنوز سندی برای این پروژه ثبت نشده', style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            ...entries.map((e) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long_outlined, color: AppColors.brass),
                    title: Text(e.description ?? 'سند شماره ${pn(e.id!)}'),
                    subtitle: Text('${formatJalaliLong(e.date)} · ${formatMoney(e.totalDebit)}'),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => JournalEntryDetailScreen(entryId: e.id!)),
                      );
                      onLoad();
                    },
                  ),
                )),
        ],
      ),
    );
  }

  Widget _amountRow(String label, String value, {Widget? badge, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
          ),
          if (badge != null) ...[badge, const SizedBox(width: 8)],
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }

  /// نشان کوچک اختلاف مبلغ فعلی نسبت به برآورد اولیه - سبز برای افزایش،
  /// قرمز برای کاهش (بدون قضاوت این‌که کدام برای دفتر بهتر است؛ فقط جهت
  /// تغییر مبلغ قرارداد را نشان می‌دهد)
  Widget _deltaBadge(double delta) {
    final positive = delta >= 0;
    final color = positive ? AppColors.positive : AppColors.negative;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: Text('${positive ? '+' : '-'} ${formatMoney(delta.abs())}',
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
