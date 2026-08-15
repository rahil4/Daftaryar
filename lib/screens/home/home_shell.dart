import 'package:flutter/material.dart';

import '../dashboard/dashboard_screen.dart';
import '../projects/projects_screen.dart';
import '../clients/clients_screen.dart';
import '../expenses/expenses_screen.dart';
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
    ProjectsScreen(),
    ClientsScreen(),
    ExpensesScreen(),
    ReportsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          const BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'داشبورد'),
          const BottomNavigationBarItem(icon: Icon(Icons.work_outline), label: 'پروژه‌ها'),
          const BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'کارفرمایان'),
          const BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'هزینه‌ها'),
          const BottomNavigationBarItem(icon: Icon(Icons.bar_chart_outlined), label: 'گزارش'),
        ],
      ),
    );
  }
}
