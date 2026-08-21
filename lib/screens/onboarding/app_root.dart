import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../services/security_service.dart';
import '../../services/sms_listener_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../home/home_shell.dart';
import '../lock/lock_screen.dart';
import 'fiscal_year_setup_screen.dart';

/// نقطه ورود برنامه پس از splash: ابتدا قفل امنیتی (در صورت فعال بودن)،
/// سپس تعریف سال مالی (فقط بار اول)، سپس برنامه اصلی.
class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final _db = DatabaseHelper.instance;
  final _security = SecurityService();
  bool _loading = true;
  bool _locked = false;
  bool _configured = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    final lockEnabled = await _security.isLockEnabled();
    final fyConfigured = await _db.isFiscalYearConfigured();
    final smsEnabled = await _db.getSetting('sms_reading_enabled');
    if (smsEnabled == '1') {
      SmsListenerService.startListening();
      final pendingCount = await _db.countPendingSmsDrafts();
      await NotificationService.updatePendingDraftsNotification(pendingCount);
    }
    setState(() {
      _locked = lockEnabled;
      _configured = fyConfigured;
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
    if (_locked) {
      return LockScreen(onUnlocked: () => setState(() => _locked = false));
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
