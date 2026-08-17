import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../home/home_shell.dart';
import 'fiscal_year_setup_screen.dart';

/// نقطه ورود برنامه پس از splash: اگر سال مالی هنوز تعریف نشده،
/// قبل از نمایش برنامه اصلی، تعریف آن را از کاربر می‌خواهد.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final _db = DatabaseHelper.instance;
  bool _loading = true;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final configured = await _db.isFiscalYearConfigured();
    setState(() {
      _configured = configured;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!_configured) {
      return FiscalYearSetupScreen(
        isOnboarding: true,
        onDone: () => setState(() => _configured = true),
      );
    }
    return const HomeShell();
  }
}
