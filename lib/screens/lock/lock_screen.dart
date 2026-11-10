import 'dart:async';

import 'package:flutter/material.dart';

import '../../services/security_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// صفحه ورود با پین (و در صورت فعال بودن، پیشنهاد اثر انگشت) — قبل از هر صفحه دیگری نمایش داده می‌شود
class LockScreen extends StatefulWidget {
  final VoidCallback onUnlocked;
  const LockScreen({super.key, required this.onUnlocked});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final _security = SecurityService();
  String _entered = '';
  String? _error;
  bool _checkingBiometric = false;
  // ثانیه‌های باقی‌مانده قفل موقت پس از چند تلاش ناموفق؛ صفر یعنی باز.
  int _lockoutSeconds = 0;
  Timer? _lockoutTimer;

  @override
  void initState() {
    super.initState();
    _restoreLockout();
    _tryBiometricAtStart();
  }

  @override
  void dispose() {
    _lockoutTimer?.cancel();
    super.dispose();
  }

  /// اگر برنامه وسط یک قفل موقت بسته و دوباره باز شده، شمارش ادامه پیدا
  /// می‌کند.
  Future<void> _restoreLockout() async {
    final remaining = await _security.pinLockoutRemaining();
    if (!mounted || remaining <= Duration.zero) return;
    _startLockout(remaining);
  }

  void _startLockout(Duration duration) {
    _lockoutTimer?.cancel();
    setState(() {
      _lockoutSeconds = duration.inSeconds < 1 ? 1 : duration.inSeconds;
      _entered = '';
      _error = null;
    });
    _lockoutTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _lockoutSeconds--);
      if (_lockoutSeconds <= 0) timer.cancel();
    });
  }

  String get _lockoutMessage {
    final minutes = _lockoutSeconds ~/ 60;
    final seconds = _lockoutSeconds % 60;
    final time = minutes > 0 ? '${pn(minutes)} دقیقه و ${pn(seconds)} ثانیه' : '${pn(seconds)} ثانیه';
    return 'تلاش ناموفق زیاد بود؛ $time دیگر دوباره امتحان کنید';
  }

  Future<void> _tryBiometricAtStart() async {
    final enabled = await _security.isBiometricEnabled();
    if (!enabled || !mounted) return;
    setState(() => _checkingBiometric = true);
    final ok = await _security.authenticateWithBiometrics();
    if (!mounted) return;
    setState(() => _checkingBiometric = false);
    if (ok) widget.onUnlocked();
  }

  Future<void> _onDigit(String d) async {
    if (_lockoutSeconds > 0 || _entered.length >= 4) return;
    setState(() {
      _entered += d;
      _error = null;
    });
    if (_entered.length == 4) {
      final result = await _security.attemptUnlock(_entered);
      if (!mounted) return;
      if (result.success) {
        widget.onUnlocked();
      } else if (result.isLockedOut) {
        _startLockout(result.lockout);
      } else {
        setState(() {
          _error = 'پین اشتباه است؛ ${pn(result.attemptsLeft)} تلاش دیگر باقی مانده';
          _entered = '';
        });
      }
    }
  }

  void _onBackspace() {
    if (_lockoutSeconds > 0 || _entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              const Text('دفتریار',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, letterSpacing: 1)),
              const SizedBox(height: 10),
              const Text('ورود با پین',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(4, (i) {
                  final filled = i < _entered.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? AppColors.brass : Colors.transparent,
                      border: Border.all(color: AppColors.gridLine, width: 1.4),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),
              SizedBox(
                height: 38, // جا برای پیام دوخطی قفل موقت
                child: _checkingBiometric
                    ? const Text('در حال تأیید اثر انگشت...',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
                    : Text(_lockoutSeconds > 0 ? _lockoutMessage : (_error ?? ''),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 12, color: AppColors.negative)),
              ),
              const Spacer(),
              _NumPad(
                onDigit: _onDigit,
                onBackspace: _onBackspace,
                onBiometric: () async {
                  final ok = await _security.authenticateWithBiometrics();
                  if (ok && mounted) widget.onUnlocked();
                },
                showBiometric: true,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _NumPad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onBiometric;
  final bool showBiometric;

  const _NumPad({
    required this.onDigit,
    required this.onBackspace,
    required this.onBiometric,
    required this.showBiometric,
  });

  @override
  Widget build(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, Widget? child}) {
      return Expanded(
        child: AspectRatio(
          aspectRatio: 1.5,
          child: InkWell(
            onTap: onTap ?? () => onDigit(label),
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: child ??
                  Text(pn(label), style: const TextStyle(fontSize: 20, color: AppColors.textPrimary)),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        Row(children: [key('1'), key('2'), key('3')]),
        Row(children: [key('4'), key('5'), key('6')]),
        Row(children: [key('7'), key('8'), key('9')]),
        Row(children: [
          key('', onTap: showBiometric ? onBiometric : null,
              child: showBiometric
                  ? const Icon(Icons.fingerprint, color: AppColors.brass, size: 26)
                  : const SizedBox.shrink()),
          key('0'),
          key('', onTap: onBackspace, child: const Icon(Icons.backspace_outlined, color: AppColors.textSecondary, size: 20)),
        ]),
      ],
    );
  }
}
