import 'package:flutter/material.dart';

import '../dashboard/dashboard_screen.dart';
import '../journal/journal_list_screen.dart';
import '../projects/projects_screen.dart';
import '../accounts/accounts_screen.dart';
import '../reports/reports_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/quick_add_sheet.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  // توجه: «حساب‌ها» در نوار پایین جا نمی‌شود (۴ آیتم + دکمه شناور وسط)
  // و از طریق تنظیمات → چارت حساب‌ها در دسترس باقی می‌ماند.
  final _screens = const [
    DashboardScreen(),
    JournalListScreen(),
    ProjectsScreen(),
    AccountsScreen(),
    ReportsScreen(),
  ];

  void _goTo(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showQuickAddSheet(context),
        child: const Icon(Icons.add),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: AppColors.surface,
        elevation: 4,
        shape: const CircularNotchedRectangle(),
        notchMargin: 8,
        child: SizedBox(
          height: 60,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _NavItem(icon: Icons.home_outlined, label: 'خانه', active: _index == 0, onTap: () => _goTo(0)),
              _NavItem(icon: Icons.receipt_long_outlined, label: 'اسناد', active: _index == 1, onTap: () => _goTo(1)),
              const SizedBox(width: 40), // فضای دکمه شناور وسط
              _NavItem(icon: Icons.work_outline, label: 'پروژه‌ها', active: _index == 2, onTap: () => _goTo(2)),
              _NavItem(icon: Icons.bar_chart_outlined, label: 'گزارشات', active: _index == 4, onTap: () => _goTo(4)),
            ],
          ),
        ),
      ),
    );
  }
}

/// آیتم نوار پایین با رنگ برند برای حالت فعال و خاکستری روشن برای غیرفعال
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.brass : AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
