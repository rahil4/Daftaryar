import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../../utils/reloadable.dart';
import '../../widgets/quick_add_sheet.dart';
import '../accounting/accounting_screen.dart';
import '../dashboard/management_dashboard_screen.dart';
import '../projects/projects_screen.dart';
import '../reports/reports_screen.dart';

/// پوستهٔ اصلی ناوبری برنامه - ۴ تب با مرز مفهومی واضح: داشبورد، حسابداری
/// (دفترکل+چارت حساب‌ها)، پروژه‌ها، گزارش‌ها؛ و یک دکمه «+» در وسط نوار
/// پایین که تنها نقطه ورود همه ثبت‌هاست (به‌جای دکمه‌های شناور پراکنده در
/// هر تب). «تنظیمات» تب مستقل ندارد و از آیکون بالای هر تب در دسترس است.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final _dashboardKey = GlobalKey<State<ManagementDashboardScreen>>();
  final _accountingKey = GlobalKey<State<AccountingScreen>>();
  final _projectsKey = GlobalKey<State<ProjectsScreen>>();
  final _reportsKey = GlobalKey<State<ReportsScreen>>();

  late final _screens = [
    ManagementDashboardScreen(key: _dashboardKey),
    AccountingScreen(key: _accountingKey),
    ProjectsScreen(key: _projectsKey),
    ReportsScreen(key: _reportsKey),
  ];

  late final _keys = [_dashboardKey, _accountingKey, _projectsKey, _reportsKey];

  void _onTap(int i) {
    setState(() => _index = i);
    triggerReload(_keys[i]);
  }

  void _openQuickAdd() {
    // هر ثبتی که از این برگه انجام شود، تب فعلی را تازه می‌کند.
    showQuickAddSheet(context, onDone: () => triggerReload(_keys[_index]));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: _BottomBar(index: _index, onTap: _onTap, onAdd: _openQuickAdd),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;

  const _BottomBar({required this.index, required this.onTap, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.gridLine)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          // ارتفاع ثابت لازم است: Scaffold به نوار پایین اجازه می‌دهد تا کل
          // ارتفاع صفحه بزرگ شود و بدون این قید، بدنه صفحه جایی نمی‌گیرد.
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                Expanded(child: _item(0, Icons.dashboard_outlined, 'داشبورد')),
                Expanded(child: _item(1, Icons.menu_book_outlined, 'حسابداری')),
                Expanded(
                  child: Center(
                    child: Semantics(
                      button: true,
                      label: 'ثبت جدید',
                      child: Material(
                        color: AppColors.brass,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: onAdd,
                          child: const SizedBox(
                            width: 52,
                            height: 52,
                            child: Icon(Icons.add, size: 26, color: Color(0xFF15100A)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(child: _item(2, Icons.work_outline, 'پروژه‌ها')),
                Expanded(child: _item(3, Icons.bar_chart_outlined, 'گزارش‌ها')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _item(int i, IconData icon, String label) {
    final selected = i == index;
    final color = selected ? AppColors.brassLight : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onTap(i),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 22, color: color),
              const SizedBox(height: 4),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
