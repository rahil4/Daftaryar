import 'package:flutter/material.dart';

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

  final _screens = const [
    ManagementDashboardScreen(),
    AccountingScreen(),
    ProjectsScreen(),
    ReportsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
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
