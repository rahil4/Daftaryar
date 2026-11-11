import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:local_auth/local_auth.dart';

import '../db/database_helper.dart';

/// نتیجه یک تلاش ورود با پین (SecurityService.attemptUnlock).
class PinAttemptResult {
  final bool success;

  /// اگر بزرگ‌تر از صفر باشد، ورود با پین تا پایان این مدت بسته است (چه
  /// به‌خاطر همین تلاش ناموفق، چه چون از قبل بسته بوده).
  final Duration lockout;

  /// تعداد تلاش باقی‌مانده تا قفل موقت بعدی؛ فقط برای تلاش ناموفقی که هنوز
  /// به قفل موقت نرسیده معنا دارد.
  final int attemptsLeft;

  const PinAttemptResult({required this.success, required this.lockout, required this.attemptsLeft});

  bool get isLockedOut => lockout > Duration.zero;
}

/// مدیریت قفل امنیتی برنامه: پین (هش‌شده با Salt ذخیره می‌شود) و ورود با اثر انگشت/بیومتریک
class SecurityService {
  final _db = DatabaseHelper.instance;
  final _localAuth = LocalAuthentication();

  static const int _stretchRounds = 10000;

  /// پین ۴ رقمی فقط ۱۰٬۰۰۰ حالت دارد؛ بدون محدودیت تلاش، حدس‌زدن آن با
  /// دست هم شدنی است. بعد از هر [kPinAttemptsPerRound] تلاش ناموفق پیاپی،
  /// ورود با پین موقتاً بسته می‌شود و مدتش هر بار دو برابر می‌شود (تا سقف
  /// [kMaxPinLockout]). شمارنده در تنظیمات ذخیره می‌شود تا با بستن و
  /// بازکردن برنامه صفر نشود، و فقط با ورود موفق صفر می‌شود.
  static const int kPinAttemptsPerRound = 5;
  static const Duration kBasePinLockout = Duration(seconds: 30);
  static const Duration kMaxPinLockout = Duration(minutes: 30);
  static const String _failedAttemptsKey = 'pin_failed_attempts';
  static const String _lockoutUntilKey = 'pin_lockout_until';

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

  static Duration _lockoutForRound(int round) {
    var seconds = kBasePinLockout.inSeconds;
    for (var i = 1; i < round && seconds < kMaxPinLockout.inSeconds; i++) {
      seconds *= 2;
    }
    return Duration(seconds: seconds > kMaxPinLockout.inSeconds ? kMaxPinLockout.inSeconds : seconds);
  }

  /// مدت باقی‌مانده قفل موقت ورود با پین (صفر یعنی باز است).
  Future<Duration> pinLockoutRemaining({DateTime? now}) async {
    final untilMs = int.tryParse(await _db.getSetting(_lockoutUntilKey) ?? '');
    if (untilMs == null) return Duration.zero;
    final remaining =
        DateTime.fromMillisecondsSinceEpoch(untilMs).difference(now ?? DateTime.now());
    if (remaining <= Duration.zero) return Duration.zero;
    // اگر ساعت دستگاه عقب کشیده شده باشد، قفل هرگز از سقف خودش طولانی‌تر
    // نمی‌شود.
    return remaining > kMaxPinLockout ? kMaxPinLockout : remaining;
  }

  /// تلاش ورود با پین، با محدودیت تعداد تلاش. صفحه قفل باید از این متد
  /// استفاده کند، نه مستقیم از verifyPin. در مدت قفل موقت، پین اصلاً بررسی
  /// نمی‌شود (حتی پین درست)، و آن تلاش هم شمرده نمی‌شود.
  Future<PinAttemptResult> attemptUnlock(String pin, {DateTime? now}) async {
    final current = now ?? DateTime.now();
    final remaining = await pinLockoutRemaining(now: current);
    if (remaining > Duration.zero) {
      return PinAttemptResult(success: false, lockout: remaining, attemptsLeft: 0);
    }

    if (await verifyPin(pin)) {
      await _db.setSetting(_failedAttemptsKey, '0');
      await _db.setSetting(_lockoutUntilKey, '0');
      return const PinAttemptResult(
          success: true, lockout: Duration.zero, attemptsLeft: kPinAttemptsPerRound);
    }

    final failed = (int.tryParse(await _db.getSetting(_failedAttemptsKey) ?? '') ?? 0) + 1;
    await _db.setSetting(_failedAttemptsKey, '$failed');
    if (failed % kPinAttemptsPerRound == 0) {
      final lockout = _lockoutForRound(failed ~/ kPinAttemptsPerRound);
      await _db.setSetting(
          _lockoutUntilKey, '${current.add(lockout).millisecondsSinceEpoch}');
      return PinAttemptResult(success: false, lockout: lockout, attemptsLeft: 0);
    }
    return PinAttemptResult(
      success: false,
      lockout: Duration.zero,
      attemptsLeft: kPinAttemptsPerRound - failed % kPinAttemptsPerRound,
    );
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
