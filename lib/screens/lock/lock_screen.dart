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

  @override
  void initState() {
    super.initState();
    _tryBiometricAtStart();
  }

  Future<void> _tryBiometricAtStart() async {
    final enabled = await _security.isBiometricEnabled();
    if (!enabled) return;
    setState(() => _checkingBiometric = true);
    final ok = await _security.authenticateWithBiometrics();
    if (!mounted) return;
    setState(() => _checkingBiometric = false);
    if (ok) widget.onUnlocked();
  }

  Future<void> _onDigit(String d) async {
    if (_entered.length >= 6) return;
    setState(() {
      _entered += d;
      _error = null;
    });
    if (_entered.length == 4) {
      final ok = await _security.verifyPin(_entered);
      if (ok) {
        widget.onUnlocked();
      } else {
        setState(() {
          _error = 'پین اشتباه است';
          _entered = '';
        });
      }
    }
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
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
                height: 18,
                child: _checkingBiometric
                    ? const Text('در حال تأیید اثر انگشت...',
                        style: TextStyle(fontSize: 12, color: AppColors.textSecondary))
                    : Text(_error ?? '',
                        style: const TextStyle(fontSize: 12, color: AppColors.negative)),
              ),
              const Spacer(),
              _NumPad(
                onDigit: _onDigit,
                onBackspace: _onBackspace,
                onBiometric: () async {
                  final ok = await _security.authenticateWithBiometrics();
                  if (ok) widget.onUnlocked();
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
