import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../db/database_helper.dart';
import '../../models/account.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'financial_overview_screen.dart';
import 'outstanding_receivables_screen.dart';
import '../settings/settings_screen.dart';
import '../../widgets/jalali_date_field.dart';
import '../../widgets/section_title.dart';
import '../../services/pdf_export_service.dart';
import '../../services/excel_export_service.dart';

enum _RangeMode { month, fiscalYear, custom }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 3, vsync: this);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('گزارش‌ها'),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long_outlined),
            tooltip: 'طلب‌های باز',
            onPressed: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const OutstandingReceivablesScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'تنظیمات',
            onPressed: () =>
                Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'سود و زیان'),
            Tab(text: 'تراز آزمایشی'),
            Tab(text: 'وضعیت مالی'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _ProfitLossTab(),
          _TrialBalanceTab(),
          FinancialOverviewScreen(embedded: true),
        ],
      ),
    );
  }
}

/// ---------------- تب سود و زیان: صورت استاندارد سبک سنتی ----------------
/// تب سود و زیان سنتی (بر مبنای نوع حساب - Income/Expense Chart of Accounts).
///
/// طبقه‌بندی Audit مرحله ۲.۱ (Reporting Layer Closure): این تب و توابع
/// `accountTypeBreakdown` که مصرف می‌کند، **تکرار لایه Metrics/Reporting
/// نیستند** (Category 2 - محاسبه‌ای که به‌درستی در UI/این لایه باقی می‌ماند).
/// دلیل: این‌جا خط‌به‌خط بر مبنای **نام هر حساب** در دفتر کل شکسته می‌شود
/// (مثلاً «درآمد نقشه‌برداری» جدا از «درآمد پیگیری ثبتی»)، در حالی که لایه
/// Reporting/Metrics فقط مجموع‌های طبقه‌بندی‌شده بر اساس systemKey
/// (Project Revenue/Direct Cost/Overhead/Office Expense) را می‌دهد، نه
/// شکست ریز به تفکیک تک‌تک حساب‌ها. این دو یک مفهوم مشترک با دو سطح
/// جزئیات متفاوت نیستند؛ یک گزارش «تراز حسابداری سنتی» در مقابل یک گزارش
/// «اقتصاد پروژه» است. جایگزین‌کردن این تب با خروجی Reporting Layer باعث
/// از‌دست‌رفتن جزئیات تک‌حسابی می‌شد که این تب دقیقاً برایش ساخته شده.
class _ProfitLossTab extends StatefulWidget {
  const _ProfitLossTab();

  @override
  State<_ProfitLossTab> createState() => _ProfitLossTabState();
}

class _ProfitLossTabState extends State<_ProfitLossTab> {
  final _db = DatabaseHelper.instance;
  final _pdf = PdfExportService();
  final _excelExport = ExcelExportService();
  _RangeMode _mode = _RangeMode.month;
  String _fromDate = '';
  String _toDate = '';

  Map<String, double> _incomeLines = {};
  Map<String, double> _expenseLines = {};
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _applyMode(_RangeMode.month);
  }

  Future<void> _applyMode(_RangeMode mode) async {
    final today = Jalali.now();
    List<Jalali> range;
    if (mode == _RangeMode.month) {
      range = currentMonthToDateRange(today);
    } else if (mode == _RangeMode.fiscalYear) {
      // مورد ۹/۱۰ مرحله ۲ / بند Fiscal Year مرحله ۲.۱: این خط از همان تابع
      // مرجع سال مالی (currentFiscalYearRange) استفاده می‌کند که
      // DashboardPeriodResolver.resolve هم داخلاً برای پیش‌نمایش
      // thisYear/lastYear از آن استفاده می‌کند - یعنی منطق سال مالی
      // موازی یا دوباره‌سازی‌شده نیست، فقط نقطه ورودی متفاوتی به همان
      // تابع مشترک است. علت استفاده مستقیم (نه از طریق DashboardPeriodResolver
      // خودش): این تب سه حالت (این‌ماه/سال‌مالی/سفارشی) دارد که با Enum
      // DashboardPeriodPreset یک‌به‌یک منطبق نیست؛ عبورش از آن Enum یک
      // تغییر ساختاری بزرگ‌تر از محدوده این مرحله (Closure، نه Redesign) بود.
      final fy = await _db.getFiscalYearStart();
      range = currentFiscalYearRange(fy['month']!, fy['day']!, today);
    } else {
      range = currentMonthToDateRange(today); // نقطه شروع پیش‌فرض برای انتخاب دستی
    }
    setState(() {
      _mode = mode;
      _fromDate = jalaliToString(range[0]);
      _toDate = jalaliToString(range[1]);
    });
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final income = await _db.accountTypeBreakdown(kAccountIncome, fromDate: _fromDate, toDate: _toDate);
    final expense = await _db.accountTypeBreakdown(kAccountExpense, fromDate: _fromDate, toDate: _toDate);
    setState(() {
      _incomeLines = income;
      _expenseLines = expense;
      _loading = false;
    });
  }

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      await _pdf.exportProfitLoss(
        fromDate: _fromDate,
        toDate: _toDate,
        incomeLines: _incomeLines,
        expenseLines: _expenseLines,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exporting = true);
    try {
      await _excelExport.exportProfitLoss(
        fromDate: _fromDate,
        toDate: _toDate,
        incomeLines: _incomeLines,
        expenseLines: _expenseLines,
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalIncome = _incomeLines.values.fold<double>(0, (s, v) => s + v);
    final totalExpense = _expenseLines.values.fold<double>(0, (s, v) => s + v);
    final net = totalIncome - totalExpense;

    return BlueprintGridBackground(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                _RangeSelector(
                  mode: _mode,
                  onChanged: _applyMode,
                ),
                if (_mode == _RangeMode.custom) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: JalaliDateField(
                          label: 'از تاریخ',
                          value: _fromDate,
                          onChanged: (v) {
                            _fromDate = v;
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: JalaliDateField(
                          label: 'تا تاریخ',
                          value: _toDate,
                          onChanged: (v) {
                            _toDate = v;
                            _load();
                          },
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 18),

                Container(
                  padding: const EdgeInsets.only(bottom: 14),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.gridLine)),
                  ),
                  child: Column(
                    children: [
                      const Text('صورت سود و زیان',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      const SizedBox(height: 4),
                      Text(
                        'از ${formatJalaliLong(_fromDate)} تا ${formatJalaliLong(_toDate)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton.icon(
                            onPressed: _exporting ? null : _exportPdf,
                            icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                            label: const Text('خروجی PDF', style: TextStyle(fontSize: 12)),
                          ),
                          const SizedBox(width: 8),
                          TextButton.icon(
                            onPressed: _exporting ? null : _exportExcel,
                            icon: const Icon(Icons.table_chart_outlined, size: 16),
                            label: const Text('خروجی اکسل', style: TextStyle(fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),
                const SectionTitle('درآمدها'),
                const Divider(color: AppColors.gridLine, height: 1),
                if (_incomeLines.isEmpty)
                  const _EmptyLine('درآمدی در این بازه ثبت نشده')
                else
                  ..._incomeLines.entries.map((e) => _StatementRow(label: e.key, value: e.value)),
                _StatementRow(label: 'جمع درآمدها', value: totalIncome, isSubtotal: true),

                const SizedBox(height: 22),
                const SectionTitle('هزینه‌ها'),
                const Divider(color: AppColors.gridLine, height: 1),
                if (_expenseLines.isEmpty)
                  const _EmptyLine('هزینه‌ای در این بازه ثبت نشده')
                else
                  ..._expenseLines.entries.map((e) => _StatementRow(label: e.key, value: e.value)),
                _StatementRow(label: 'جمع هزینه‌ها', value: totalExpense, isSubtotal: true),

                const SizedBox(height: 22),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: const BoxDecoration(
                    border: Border(
                      top: BorderSide(color: AppColors.brass, width: 2),
                      bottom: BorderSide(color: AppColors.brass, width: 2),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(net >= 0 ? 'سود خالص' : 'زیان خالص',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      Text(
                        formatMoney(net.abs()),
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: net >= 0 ? AppColors.positive : AppColors.negative,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// انتخاب بازه گزارش: ماه جاری (پیش‌فرض) / سال مالی جاری / دلخواه
class _RangeSelector extends StatelessWidget {
  final _RangeMode mode;
  final ValueChanged<_RangeMode> onChanged;
  const _RangeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, _RangeMode value) {
      final selected = mode == value;
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          selectedColor: AppColors.brass.withValues(alpha: 0.18),
          labelStyle: TextStyle(
            color: selected ? AppColors.brass : AppColors.textSecondary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
            fontSize: 12.5,
          ),
          onSelected: (_) => onChanged(value),
        ),
      );
    }

    return SizedBox(
      height: 38,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          chip('ماه جاری', _RangeMode.month),
          chip('سال مالی جاری', _RangeMode.fiscalYear),
          chip('دلخواه', _RangeMode.custom),
        ],
      ),
    );
  }
}

/// ردیف یک قلم در صورت سود و زیان؛ اگر جمع‌بندی بخش باشد با خط برنزی مشخص می‌شود
class _StatementRow extends StatelessWidget {
  final String label;
  final double value;
  final bool isSubtotal;

  const _StatementRow({required this.label, required this.value, this.isSubtotal = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(top: isSubtotal ? 12 : 10, bottom: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isSubtotal ? AppColors.brass : AppColors.gridLine,
            width: isSubtotal ? 1.4 : 1,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: isSubtotal ? AppColors.textPrimary : AppColors.textSecondary,
              fontWeight: isSubtotal ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
          Text(
            formatMoney(value),
            style: TextStyle(
              fontSize: isSubtotal ? 15 : 14,
              fontWeight: isSubtotal ? FontWeight.w800 : FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  final String text;
  const _EmptyLine(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Text(text, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12.5)),
    );
  }
}

/// ---------------- تب تراز آزمایشی: مانده تجمعی همه حساب‌ها ----------------
/// تب تراز آزمایشی (Trial Balance).
///
/// طبقه‌بندی Audit مرحله ۲.۱: این یک آرتیفکت بنیادی حسابداری دوطرفه است
/// (اثبات تساوی جمع بدهکار و بستانکار کل دفتر حساب‌ها، تجمعی از ابتدا تا
/// امروز) - مفهومی کاملاً متفاوت و مستقل از «اقتصاد پروژه/مشتری» که لایه
/// Metrics/Reporting پوشش می‌دهد. `_db.trialBalance()` تنها و مرجع صحیح
/// این داده است؛ هیچ سرویس Metrics/Reporting معادلی برایش وجود ندارد یا
/// باید داشته باشد (Category 2).
class _TrialBalanceTab extends StatefulWidget {
  const _TrialBalanceTab();

  @override
  State<_TrialBalanceTab> createState() => _TrialBalanceTabState();
}

class _TrialBalanceTabState extends State<_TrialBalanceTab> {
  final _db = DatabaseHelper.instance;
  final _pdf = PdfExportService();
  final _excelExport = ExcelExportService();
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _db.trialBalance();
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  List<Map<String, dynamic>> get _nonZeroRows => _rows
      .where((r) => (r['debit'] as double) != 0 || (r['credit'] as double) != 0)
      .map((r) => {
            'name': (r['account'] as AccountModel).name,
            'debit': r['debit'] as double,
            'credit': r['credit'] as double,
          })
      .toList();

  Future<void> _exportPdf() async {
    setState(() => _exporting = true);
    try {
      await _pdf.exportTrialBalance(rows: _nonZeroRows);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _exportExcel() async {
    setState(() => _exporting = true);
    try {
      await _excelExport.exportTrialBalance(_nonZeroRows);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalDebit = _rows.fold<double>(0, (s, r) => s + (r['debit'] as double));
    final totalCredit = _rows.fold<double>(0, (s, r) => s + (r['credit'] as double));

    return BlueprintGridBackground(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                children: [
                  const Text('تراز آزمایشی',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  const Text('مانده تجمعی همه حساب‌ها تا امروز',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _exporting ? null : _exportPdf,
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                        label: const Text('خروجی PDF', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _exporting ? null : _exportExcel,
                        icon: const Icon(Icons.table_chart_outlined, size: 16),
                        label: const Text('خروجی اکسل', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  for (final type in kAccountTypes)
                    if (_rows.any((r) => (r['account'] as AccountModel).type == type &&
                        ((r['debit'] as double) != 0 || (r['credit'] as double) != 0))) ...[
                      SectionTitle(type),
                      const Divider(color: AppColors.gridLine, height: 1),
                      for (final row in _rows.where((r) =>
                          (r['account'] as AccountModel).type == type &&
                          ((r['debit'] as double) != 0 || (r['credit'] as double) != 0)))
                        _TrialBalanceRow(
                          name: (row['account'] as AccountModel).name,
                          debit: row['debit'] as double,
                          credit: row['credit'] as double,
                        ),
                      const SizedBox(height: 18),
                    ],
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: const BoxDecoration(
                      border: Border(
                        top: BorderSide(color: AppColors.brass, width: 2),
                        bottom: BorderSide(color: AppColors.brass, width: 2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('جمع کل بدهکار',
                                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            Text(formatMoney(totalDebit),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('جمع کل بستانکار',
                                style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            Text(formatMoney(totalCredit),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _TrialBalanceRow extends StatelessWidget {
  final String name;
  final double debit;
  final double credit;
  const _TrialBalanceRow({required this.name, required this.debit, required this.credit});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.gridLine)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(name, style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              debit != 0 ? formatMoney(debit, withSuffix: false) : '—',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.positive, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              credit != 0 ? formatMoney(credit, withSuffix: false) : '—',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.negative, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

