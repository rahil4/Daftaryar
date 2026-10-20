// تست‌های BackupCrypto - رمزنگاری اختیاری فایل پشتیبان با رمز عبور
// (AES-256-GCM + کلید مشتق‌شده با PBKDF2-HMAC-SHA256).
import 'package:flutter_test/flutter_test.dart';

import 'package:daftaryar/services/backup_crypto.dart';

void main() {
  const samplePlainJson = '{"version":5,"counterparties":[{"name":"تست"}]}';

  test('رمزگذاری و رمزگشایی با رمز عبور درست، متن اصلی را دقیقاً برمی‌گرداند', () {
    final envelope = BackupCrypto.encrypt(samplePlainJson, 'my-secret-password');
    expect(BackupCrypto.isEncryptedEnvelope(envelope), true);
    final decrypted = BackupCrypto.decrypt(envelope, 'my-secret-password');
    expect(decrypted, samplePlainJson);
  });

  test('رمز عبور غلط، به‌جای داده نامعتبر، صریحاً BackupPasswordException می‌دهد', () {
    final envelope = BackupCrypto.encrypt(samplePlainJson, 'correct-password');
    expect(
      () => BackupCrypto.decrypt(envelope, 'wrong-password'),
      throwsA(isA<BackupPasswordException>()),
    );
  });

  test('دستکاری ciphertext هم مثل رمز غلط رد می‌شود (احراز صحت GCM)', () {
    final envelope = BackupCrypto.encrypt(samplePlainJson, 'correct-password');
    final tampered = Map<String, dynamic>.from(envelope);
    tampered['ciphertext'] = envelope['ciphertext'].toString().replaceRange(0, 4, 'AAAA');
    expect(
      () => BackupCrypto.decrypt(tampered, 'correct-password'),
      throwsA(isA<BackupPasswordException>()),
    );
  });

  test('یک Map عادی/قدیمی (بدون رمزگذاری) به‌عنوان envelope رمزنگاری‌شده تشخیص داده نمی‌شود', () {
    final plainBackup = {'version': 5, 'counterparties': []};
    expect(BackupCrypto.isEncryptedEnvelope(plainBackup), false);
  });

  test('هر بار رمزگذاری همان متن، Salt/IV و در نتیجه ciphertext متفاوتی تولید می‌کند', () {
    final e1 = BackupCrypto.encrypt(samplePlainJson, 'same-password');
    final e2 = BackupCrypto.encrypt(samplePlainJson, 'same-password');
    expect(e1['salt'], isNot(e2['salt']));
    expect(e1['ciphertext'], isNot(e2['ciphertext']));
  });
}
