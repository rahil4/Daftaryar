import 'package:flutter/material.dart';

import '../dashboard/dashboard_screen.dart';
import '../journal/journal_list_screen.dart';
import '../projects/projects_screen.dart';
import '../accounts/accounts_screen.dart';
import '../reports/reports_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  final _screens = const [
    DashboardScreen(),
    JournalListScreen(),
    ProjectsScreen(),
    AccountsScreen(),
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
          BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'اسناد'),
          BottomNavigationBarItem(icon: Icon(Icons.work_outline), label: 'پروژه‌ها'),
          BottomNavigationBarItem(icon: Icon(Icons.account_tree_outlined), label: 'حساب‌ها'),
          BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'گزارش‌ها'),
        ],
      ),
    );
  }
}
