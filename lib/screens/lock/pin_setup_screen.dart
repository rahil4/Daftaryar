import 'package:flutter/material.dart';

import '../../services/security_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// تعریف یا تغییر پین از تنظیمات — یک بار وارد کن، یک بار تکرار کن
class PinSetupScreen extends StatefulWidget {
  const PinSetupScreen({super.key});

  @override
  State<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends State<PinSetupScreen> {
  final _security = SecurityService();
  String _first = '';
  String _second = '';
  bool _confirming = false;
  String? _error;

  void _onDigit(String d) {
    final current = _confirming ? _second : _first;
    if (current.length >= 4) return;
    setState(() {
      _error = null;
      if (_confirming) {
        _second += d;
      } else {
        _first += d;
      }
    });

    final updated = _confirming ? _second : _first;
    if (updated.length == 4) {
      if (!_confirming) {
        setState(() => _confirming = true);
      } else {
        _finish();
      }
    }
  }

  Future<void> _finish() async {
    if (_first != _second) {
      setState(() {
        _error = 'پین‌ها یکسان نبودند. دوباره تلاش کنید';
        _first = '';
        _second = '';
        _confirming = false;
      });
      return;
    }
    await _security.setPin(_first);
    if (mounted) Navigator.pop(context, true);
  }

  void _onBackspace() {
    setState(() {
      if (_confirming) {
        if (_second.isNotEmpty) _second = _second.substring(0, _second.length - 1);
      } else {
        if (_first.isNotEmpty) _first = _first.substring(0, _first.length - 1);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = _confirming ? _second : _first;
    return Scaffold(
      appBar: AppBar(title: const Text('تنظیم پین ورود')),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 30),
            Text(
              _confirming ? 'پین جدید را دوباره وارد کنید' : 'یک پین ۴ رقمی وارد کنید',
              style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(4, (i) {
                final filled = i < current.length;
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
              child: Text(_error ?? '', style: const TextStyle(fontSize: 12, color: AppColors.negative)),
            ),
            const Spacer(),
            _SetupNumPad(onDigit: _onDigit, onBackspace: _onBackspace),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SetupNumPad extends StatelessWidget {
  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  const _SetupNumPad({required this.onDigit, required this.onBackspace});

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
          key('', onTap: () {}, child: const SizedBox.shrink()),
          key('0'),
          key('', onTap: onBackspace, child: const Icon(Icons.backspace_outlined, color: AppColors.textSecondary, size: 20)),
        ]),
      ],
    );
  }
}
