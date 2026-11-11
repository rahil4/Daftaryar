// تست‌های SecurityService - هش‌کردن PIN با Salt تصادفی به‌جای SHA-256 ساده
// (که قابل حمله با Rainbow Table بود)، و ارتقای خودکار و بی‌صدای PIN های
// قدیمی (بدون Salt) به فرمت جدید در اولین ورود موفق.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daftaryar/db/database_helper.dart';
import 'package:daftaryar/services/security_service.dart';

void main() {
  final db = DatabaseHelper.instance;
  final security = SecurityService();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.wipeAll();
    // wipeAll جدول app_settings را پاک نمی‌کند (خارج از محدوده‌ی آن است)،
    // ولی تست‌های این فایل دقیقاً روی نبود/وجود pin_hash/pin_salt بین هر
    // تست حساس‌اند - برای همین اینجا صریحاً پاک می‌شود.
    await (await db.database).delete('app_settings');
  });

  group('SecurityService — PIN با Salt', () {
    test('setPin یک Salt تصادفی می‌سازد و pin_hash خام (بدون Salt) ذخیره نمی‌شود', () async {
      await security.setPin('1234');
      final hash = await db.getSetting('pin_hash');
      final salt = await db.getSetting('pin_salt');
      expect(hash, isNotNull);
      expect(salt, isNotNull);
      expect(hash, isNot('1234'));
    });

    test('verifyPin با PIN درست true و با PIN غلط false برمی‌گرداند', () async {
      await security.setPin('4321');
      expect(await security.verifyPin('4321'), true);
      expect(await security.verifyPin('0000'), false);
    });

    test('دو کاربر با PIN یکسان، Salt و در نتیجه pin_hash متفاوتی دارند', () async {
      await security.setPin('1111');
      final hash1 = await db.getSetting('pin_hash');
      final salt1 = await db.getSetting('pin_salt');

      await db.wipeAll();
      await security.setPin('1111');
      final hash2 = await db.getSetting('pin_hash');
      final salt2 = await db.getSetting('pin_salt');

      expect(salt1, isNot(salt2));
      expect(hash1, isNot(hash2));
    });

    test('PIN قدیمی بدون Salt (فرمت نسخه قبل) با PIN درست تأیید و بی‌صدا ارتقا می‌یابد', () async {
      // شبیه‌سازی کاربری که با نسخه قدیمی برنامه PIN تنظیم کرده - فقط
      // pin_hash خام SHA-256 دارد و pin_salt اصلاً وجود ندارد.
      const legacySha256Of5678 = 'f8638b979b2f4f793ddb6dbd197e0ee25a7a6ea32b0ae22f5e3c5d119d839e75';
      await db.setSetting('pin_hash', legacySha256Of5678);
      await db.setSetting('lock_enabled', '1');

      expect(await security.verifyPin('5678'), true);
      // پس از تأیید موفق، باید دیگر Salt داشته باشد (ارتقای خودکار)
      expect(await db.getSetting('pin_salt'), isNotNull);
      // و از این پس هم باز باید با همان PIN تأیید شود
      expect(await security.verifyPin('5678'), true);
    });

    test('PIN قدیمی بدون Salt، با PIN غلط رد می‌شود و ارتقا نمی‌یابد', () async {
      const legacySha256Of5678 = 'f8638b979b2f4f793ddb6dbd197e0ee25a7a6ea32b0ae22f5e3c5d119d839e75';
      await db.setSetting('pin_hash', legacySha256Of5678);

      expect(await security.verifyPin('9999'), false);
      expect(await db.getSetting('pin_salt'), isNull);
    });

    test('pin_salt هم مثل pin_hash در فهرست کلیدهای امنیتی محافظت‌شده از Backup است', () {
      expect(DatabaseHelper.kSecuritySettingKeys.contains('pin_salt'), true);
    });
  });
  group('SecurityService — محدودیت تلاش ورود با پین', () {
    final t0 = DateTime(2026, 1, 1, 12);

    Future<PinAttemptResult> wrong(DateTime at) => security.attemptUnlock('0000', now: at);

    test('پین درست بدون هیچ تلاش ناموفقی، ورود موفق است', () async {
      await security.setPin('1234');
      final result = await security.attemptUnlock('1234', now: t0);
      expect(result.success, true);
      expect(result.isLockedOut, false);
    });

    test('تلاش‌های ناموفق شمرده می‌شوند و تعداد باقی‌مانده کم می‌شود', () async {
      await security.setPin('1234');
      for (var i = 1; i < SecurityService.kPinAttemptsPerRound; i++) {
        final result = await wrong(t0);
        expect(result.success, false);
        expect(result.isLockedOut, false);
        expect(result.attemptsLeft, SecurityService.kPinAttemptsPerRound - i);
      }
    });

    test('پس از پنجمین تلاش ناموفق، ورود با پین موقتاً بسته می‌شود - حتی برای پین درست', () async {
      await security.setPin('1234');
      PinAttemptResult? last;
      for (var i = 0; i < SecurityService.kPinAttemptsPerRound; i++) {
        last = await wrong(t0);
      }
      expect(last!.lockout, SecurityService.kBasePinLockout);

      final duringLockout =
          await security.attemptUnlock('1234', now: t0.add(const Duration(seconds: 10)));
      expect(duringLockout.success, false);
      expect(duringLockout.lockout, const Duration(seconds: 20));

      final afterLockout = await security.attemptUnlock('1234',
          now: t0.add(SecurityService.kBasePinLockout + const Duration(seconds: 1)));
      expect(afterLockout.success, true);
    });

    test('تلاش در مدت قفل موقت شمرده نمی‌شود', () async {
      await security.setPin('1234');
      for (var i = 0; i < SecurityService.kPinAttemptsPerRound; i++) {
        await wrong(t0);
      }
      await wrong(t0.add(const Duration(seconds: 5)));
      await wrong(t0.add(const Duration(seconds: 6)));

      // بلافاصله بعد از پایان قفل، یک تلاش ناموفق دیگر باید «۴ تلاش باقی‌مانده»
      // بدهد، نه این‌که به‌خاطر شمرده‌شدن تلاش‌های دوره قفل، دوباره قفل شود.
      final next = await wrong(t0.add(const Duration(seconds: 31)));
      expect(next.isLockedOut, false);
      expect(next.attemptsLeft, SecurityService.kPinAttemptsPerRound - 1);
    });

    test('مدت قفل موقت در هر دور دو برابر می‌شود و از سقف بیشتر نمی‌شود', () async {
      await security.setPin('1234');
      var now = t0;
      final lockouts = <Duration>[];
      for (var round = 0; round < 9; round++) {
        PinAttemptResult? last;
        for (var i = 0; i < SecurityService.kPinAttemptsPerRound; i++) {
          last = await wrong(now);
        }
        lockouts.add(last!.lockout);
        now = now.add(last.lockout + const Duration(seconds: 1));
      }
      expect(lockouts.take(3).toList(),
          const [Duration(seconds: 30), Duration(seconds: 60), Duration(seconds: 120)]);
      expect(lockouts.last, SecurityService.kMaxPinLockout);
      expect(lockouts.every((d) => d <= SecurityService.kMaxPinLockout), true);
    });

    test('ورود موفق شمارنده را صفر می‌کند', () async {
      await security.setPin('1234');
      for (var i = 0; i < SecurityService.kPinAttemptsPerRound - 1; i++) {
        await wrong(t0);
      }
      expect((await security.attemptUnlock('1234', now: t0)).success, true);

      final next = await wrong(t0);
      expect(next.isLockedOut, false);
      expect(next.attemptsLeft, SecurityService.kPinAttemptsPerRound - 1);
    });

    test('عقب‌کشیدن ساعت دستگاه قفل موقت را از سقف طولانی‌تر نمی‌کند', () async {
      await security.setPin('1234');
      for (var i = 0; i < SecurityService.kPinAttemptsPerRound; i++) {
        await wrong(t0);
      }
      final remaining =
          await security.pinLockoutRemaining(now: t0.subtract(const Duration(days: 30)));
      expect(remaining, SecurityService.kMaxPinLockout);
    });

    test('شمارنده‌های تلاش از پشتیبان/بازیابی کنار گذاشته می‌شوند', () {
      expect(DatabaseHelper.kSecuritySettingKeys, containsAll(['pin_failed_attempts', 'pin_lockout_until']));
    });
  });
}
