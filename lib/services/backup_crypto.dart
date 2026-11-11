import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as enc;

/// رمزنگاری اختیاریِ فایل پشتیبان با رمز عبور کاربر - AES-256-GCM با کلید
/// مشتق‌شده از رمز عبور توسط PBKDF2-HMAC-SHA256 (پیاده‌سازی دستی، چون
/// پکیج crypto فقط HMAC خام می‌دهد نه PBKDF2 آماده). GCM هم محرمانگی و هم
/// احراز صحت (Authentication Tag) می‌دهد - یعنی رمز عبور غلط یا فایل
/// دستکاری‌شده به‌جای تولید JSON بی‌معنی، صریحاً رد می‌شود.
///
/// خروجی رمزنگاری‌شده خودش یک Map/JSON معتبر است (envelope با یک کلید
/// نشان‌گر `daftaryarEncryptedBackup`) - یعنی فایل همچنان پسوند .json دارد
/// و مسیر انتخاب فایل/اشتراک‌گذاری موجود بدون تغییر کار می‌کند؛ فایل‌های
/// پشتیبان قدیمی (بدون رمز، از نسخه‌های قبلی این ویژگی) فاقد این کلید
/// هستند و مثل قبل به‌صورت JSON ساده پردازش می‌شوند - رمزگذاری کاملاً
/// اختیاری و با سازگاری کامل به عقب است.
class BackupCrypto {
  static const int _pbkdf2Iterations = 120000;
  static const int _saltLength = 16;
  static const int _ivLength = 12; // طول استاندارد Nonce برای GCM
  static const int _keyLength = 32; // AES-256

  static Uint8List _deriveKey(String password, List<int> salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    var u = hmac.convert([...salt, 0, 0, 0, 1]).bytes; // شماره بلوک ۱ (Big-Endian) - چون _keyLength=32 همیشه فقط یک بلوک لازم است
    var block = List<int>.from(u);
    for (var j = 1; j < iterations; j++) {
      u = hmac.convert(u).bytes;
      for (var k = 0; k < block.length; k++) {
        block[k] ^= u[k];
      }
    }
    return Uint8List.fromList(block.sublist(0, _keyLength));
  }

  /// رشته JSON فایل پشتیبان را با رمز عبور کاربر رمزنگاری می‌کند.
  static Map<String, dynamic> encrypt(String plainJson, String password) {
    final salt = Uint8List.fromList(
        List<int>.generate(_saltLength, (_) => Random.secure().nextInt(256)));
    final iv = enc.IV.fromSecureRandom(_ivLength);
    final key = enc.Key(_deriveKey(password, salt, _pbkdf2Iterations));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    final encrypted = encrypter.encrypt(plainJson, iv: iv);
    return {
      'daftaryarEncryptedBackup': true,
      'kdf': 'pbkdf2-hmac-sha256',
      'iterations': _pbkdf2Iterations,
      'salt': base64Encode(salt),
      'iv': base64Encode(iv.bytes),
      'ciphertext': encrypted.base64,
    };
  }

  /// آیا این Map خروجی decode-شده‌ی فایل پشتیبان، رمزنگاری‌شده است؟
  static bool isEncryptedEnvelope(Map<String, dynamic> data) =>
      data['daftaryarEncryptedBackup'] == true;

  /// رمزگشایی envelope و بازگرداندن رشته JSON اصلی فایل پشتیبان. در صورت
  /// رمز عبور نادرست یا دستکاری فایل، برچسب احراز GCM نامعتبر خواهد بود و
  /// یک BackupPasswordException با پیام روشن فارسی پرتاب می‌شود (نه یک
  /// استثنای فنی مبهم از پکیج رمزنگاری، و نه بازگشت بی‌صدای داده نامعتبر).
  static String decrypt(Map<String, dynamic> envelope, String password) {
    final salt = base64Decode(envelope['salt'] as String);
    final iv = enc.IV(base64Decode(envelope['iv'] as String));
    final iterations = (envelope['iterations'] as num?)?.toInt() ?? _pbkdf2Iterations;
    final key = enc.Key(_deriveKey(password, salt, iterations));
    final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.gcm));
    try {
      return encrypter.decrypt64(envelope['ciphertext'] as String, iv: iv);
    } catch (_) {
      throw BackupPasswordException('رمز عبور نادرست است یا فایل پشتیبان دستکاری/خراب شده.');
    }
  }
}

class BackupPasswordException implements Exception {
  final String message;
  BackupPasswordException(this.message);
  @override
  String toString() => message;
}
