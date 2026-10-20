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
}
