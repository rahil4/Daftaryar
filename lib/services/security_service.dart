import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';

import '../db/database_helper.dart';

/// مدیریت قفل امنیتی برنامه: پین (هش‌شده با Salt ذخیره می‌شود) و ورود با اثر انگشت/بیومتریک
class SecurityService {
  final _db = DatabaseHelper.instance;
  final _localAuth = LocalAuthentication();

  static const int _stretchRounds = 10000;

  String _generateSalt() {
    final rand = Random.secure();
    return base64UrlEncode(List<int>.generate(16, (_) => rand.nextInt(256)));
  }

  /// هش کشیده‌شده (Key Stretching دستی با تکرار SHA-256) به‌همراه Salt
  /// تصادفی هر کاربر - جلوی حمله Rainbow-table/Brute-force را بیشتر از یک
  /// SHA-256 ساده و بدون Salt می‌گیرد.
  String _hash(String pin, String salt) {
    List<int> bytes = utf8.encode(pin + salt);
    for (var i = 0; i < _stretchRounds; i++) {
      bytes = sha256.convert(bytes).bytes;
    }
    return base64UrlEncode(bytes);
  }

  /// فرمت قدیمی (پیش از افزودن Salt) - فقط برای تشخیص و ارتقای خودکار PIN
  /// کاربرانی که پیش‌تر با نسخه قدیمی PIN تنظیم کرده‌اند، نگه داشته شده.
  String _legacyHash(String pin) => sha256.convert(utf8.encode(pin)).toString();

  Future<bool> isLockEnabled() async {
    return (await _db.getSetting('lock_enabled')) == '1';
  }

  Future<bool> isPinSet() async {
    return (await _db.getSetting('pin_hash')) != null;
  }

  Future<void> setPin(String pin) async {
    final salt = _generateSalt();
    await _db.setSetting('pin_salt', salt);
    await _db.setSetting('pin_hash', _hash(pin, salt));
    await _db.setSetting('lock_enabled', '1');
  }

  Future<bool> verifyPin(String pin) async {
    final stored = await _db.getSetting('pin_hash');
    if (stored == null) return false;
    final salt = await _db.getSetting('pin_salt');
    if (salt == null) {
      // فرمت قدیمی بدون Salt - در صورت تطابق، بی‌صدا به فرمت جدید Salt‌دار
      // ارتقا می‌دهیم تا از این پس محافظت بهتری داشته باشد.
      if (stored != _legacyHash(pin)) return false;
      await setPin(pin);
      return true;
    }
    return stored == _hash(pin, salt);
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
