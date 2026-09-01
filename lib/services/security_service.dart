import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';

import '../db/database_helper.dart';

/// مدیریت قفل امنیتی برنامه: پین (هش‌شده ذخیره می‌شود) و ورود با اثر انگشت/بیومتریک
class SecurityService {
  final _db = DatabaseHelper.instance;
  final _localAuth = LocalAuthentication();

  String _hash(String pin) => sha256.convert(utf8.encode(pin)).toString();

  Future<bool> isLockEnabled() async {
    return (await _db.getSetting('lock_enabled')) == '1';
  }

  Future<bool> isPinSet() async {
    return (await _db.getSetting('pin_hash')) != null;
  }

  Future<void> setPin(String pin) async {
    await _db.setSetting('pin_hash', _hash(pin));
    await _db.setSetting('lock_enabled', '1');
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _db.getSetting('pin_hash');
    if (stored == null) return false;
    return stored == _hash(pin);
  }

  Future<void> disableLock() async {
    await _db.setSetting('lock_enabled', '0');
    await _db.setSetting('biometric_enabled', '0');
  }

  Future<bool> isBiometricEnabled() async {
    return (await _db.getSetting('biometric_enabled')) == '1';
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _db.setSetting('biometric_enabled', enabled ? '1' : '0');
  }

  /// آیا دستگاه سخت‌افزار بیومتریک (اثر انگشت/چهره) دارد و پشتیبانی می‌شود
  Future<bool> deviceSupportsBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      return canCheck && isSupported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: 'برای ورود به دفتریار هویت خود را تأیید کنید',
        options: const AuthenticationOptions(biometricOnly: true, stickyAuth: true),
      );
    } catch (_) {
      return false;
    }
  }
}
