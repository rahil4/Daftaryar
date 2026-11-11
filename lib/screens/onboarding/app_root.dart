import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../navigation.dart';
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

/// اگر برنامه دست‌کم این مدت در پس‌زمینه بماند، هنگام برگشت دوباره قفل
/// می‌شود. کوتاه‌تر از این، رفت‌وبرگشت‌های عادی (انتخاب عکس رسید، اشتراک
/// فایل پشتیبان، پنجره اثر انگشت) هر بار پین می‌خواستند.
const Duration kRelockAfterBackground = Duration(minutes: 1);

class _AppRootState extends State<AppRoot> with WidgetsBindingObserver {
  final _db = DatabaseHelper.instance;
  final _security = SecurityService();
  bool _loading = true;
  bool _locked = false;
  bool _configured = false;
  DateTime? _backgroundedAt;
  bool _relockRouteShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _backgroundedAt ??= DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      final since = _backgroundedAt;
      _backgroundedAt = null;
      if (since != null && DateTime.now().difference(since) >= kRelockAfterBackground) {
        _relock();
      }
    }
  }

  /// قفل مجدد پس از برگشت از پس‌زمینه. صفحه قفل به‌صورت یک مسیر تمام‌صفحه
  /// روی هر چیزی که باز است (صفحه، دیالوگ، شیت) می‌نشیند و با دکمه برگشت
  /// بسته نمی‌شود؛ پس از ورود، کاربر دقیقاً به همان‌جایی که بود برمی‌گردد.
  Future<void> _relock() async {
    // قفل اولیه (هنگام بازشدن برنامه) را خودِ build مدیریت می‌کند.
    if (_loading || _locked || _relockRouteShown) return;
    if (!await _security.isLockEnabled()) return;
    final navigator = rootNavigatorKey.currentState;
    if (!mounted || navigator == null || _relockRouteShown) return;
    _relockRouteShown = true;
    await navigator.push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => PopScope(
        canPop: false,
        child: LockScreen(onUnlocked: () => navigator.pop()),
      ),
    ));
    _relockRouteShown = false;
  }

  Future<void> _check() async {
    final lockEnabled = await _security.isLockEnabled();
    final fyConfigured = await _db.isFiscalYearConfigured();
    final smsEnabled = await _db.getSetting('sms_reading_enabled');
    if (smsEnabled == '1') {
      await NotificationService.requestPermission();
      SmsListenerService.startListening();
    }
    if (!mounted) return;
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
