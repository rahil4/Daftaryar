import 'package:flutter/material.dart';

import '../../utils/reloadable.dart';
import '../accounting/accounting_screen.dart';
import '../dashboard/management_dashboard_screen.dart';
import '../projects/projects_screen.dart';
import '../reports/reports_screen.dart';

/// پوستهٔ اصلی ناوبری برنامه - ۴ تب با مرز مفهومی واضح (به‌جای ۵ تب پراکنده
/// قبلی): داشبورد یکپارچه، حسابداری (دفترکل+چارت حساب‌ها)، پروژه‌ها،
/// گزارش‌ها. «تنظیمات» دیگر تب مستقل ندارد و از یک آیکون در بالای هرکدام
/// از تب‌های اصلی در دسترس است - چون به‌مراتب کمتر از بقیه استفاده می‌شود.
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: _onTap,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'داشبورد'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book_outlined), label: 'حسابداری'),
          BottomNavigationBarItem(icon: Icon(Icons.work_outline), label: 'پروژه‌ها'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'گزارش‌ها'),
        ],
      ),
    );
  }
}
