// تست چرخه کامل پشتیبان‌گیریِ رمزنگاری‌شده - در فایل مستقل خودش (طبق همان
// درس backup_cycle_test.dart: تستی که به وضعیت پاک دیتابیس و ترتیب اجرا
// وابسته است نباید در فایلی باشد که تست‌های دیگرش ساختار را تغییر می‌دهند).
//
// این‌جا مسیر importBackupFile را مستقیماً با envelope رمزنگاری‌شده
// (ساخته‌شده با BackupCrypto، دقیقاً همان چیزی که exportToFile با پارامتر
// password تولید می‌کند) تست می‌کند - بدون نیاز به Mock کردن path_provider/
// share_plus که فقط داخل خودِ exportToFile استفاده می‌شوند.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daftaryar/db/database_helper.dart';
import 'package:daftaryar/models/counterparty.dart';
import 'package:daftaryar/models/project.dart';
import 'package:daftaryar/services/backup_crypto.dart';
import 'package:daftaryar/services/backup_service.dart';
import 'package:daftaryar/utils/formatters.dart';

void main() {
  final db = DatabaseHelper.instance;
  final backup = BackupService();
  final today = todayJalaliString();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    await db.wipeAll();
  });

  test('بازیابی از فایل پشتیبان رمزنگاری‌شده بدون رمز عبور، BackupPasswordRequiredException می‌دهد', () async {
    await db.insertCounterparty(CounterpartyModel(
        name: 'مشتری تست رمزنگاری', createdAt: today, updatedAt: today, roles: const ['مشتری']));

    final plainJson = jsonEncode(await backup.collectBackupData());
    final envelope = BackupCrypto.encrypt(plainJson, 'my-backup-password');
    final tempFile = File('${Directory.systemTemp.path}/encrypted_backup_no_password_test.json');
    await tempFile.writeAsString(jsonEncode(envelope));

    expect(
      () => backup.importBackupFile(tempFile, replaceExisting: true),
      throwsA(isA<BackupPasswordRequiredException>()),
    );

    await tempFile.delete();
  });

  test('بازیابی از فایل پشتیبان رمزنگاری‌شده با رمز عبور غلط، BackupPasswordException می‌دهد', () async {
    await db.insertCounterparty(CounterpartyModel(
        name: 'مشتری تست رمزنگاری', createdAt: today, updatedAt: today, roles: const ['مشتری']));

    final plainJson = jsonEncode(await backup.collectBackupData());
    final envelope = BackupCrypto.encrypt(plainJson, 'my-backup-password');
    final tempFile = File('${Directory.systemTemp.path}/encrypted_backup_wrong_password_test.json');
    await tempFile.writeAsString(jsonEncode(envelope));

    expect(
      () => backup.importBackupFile(tempFile, replaceExisting: true, password: 'wrong-password'),
      throwsA(isA<BackupPasswordException>()),
    );

    await tempFile.delete();
  });

  test('چرخه کامل: پشتیبان رمزنگاری‌شده با رمز درست، اثر انگشت داده را دقیقاً بازمی‌گرداند', () async {
    final cpId = await db.insertCounterparty(CounterpartyModel(
        name: 'مشتری چرخه رمزنگاری‌شده', createdAt: today, updatedAt: today, roles: const ['مشتری']));
    final projectId = await db.insertProject(ProjectModel(
      title: 'پروژه چرخه رمزنگاری‌شده',
      counterpartyId: cpId,
      projectTypes: [kProjectTypes.first],
      status: kProjectStatuses.first,
      startDate: today,
      agreedAmount: 30000000,
      createdAt: today,
    ));
    final cash = (await db.getCashAccounts()).first;
    await db.receiveProjectPayment(
        projectId: projectId, cashAccountId: cash.id!, amount: 12000000, date: today);

    final before = await db.dataFingerprint();
    expect(before['اسناد']! > 0, true);

    final plainJson = jsonEncode(await backup.collectBackupData());
    final envelope = BackupCrypto.encrypt(plainJson, 'correct-password-1404');
    final tempFile = File('${Directory.systemTemp.path}/encrypted_backup_full_cycle_test.json');
    await tempFile.writeAsString(jsonEncode(envelope));

    await backup.importBackupFile(tempFile,
        replaceExisting: true, password: 'correct-password-1404');

    final after = await db.dataFingerprint();
    expect(after, before,
        reason: 'اثر انگشت داده پس از بازیابی رمزگشایی‌شده باید دقیقاً یکسان باشد.\n'
            'پیش: $before\nپس: $after');

    await tempFile.delete();
  });

  test('فایل پشتیبان قدیمی (بدون رمزنگاری) همچنان بدون هیچ رمز عبوری بازیابی می‌شود', () async {
    await db.insertCounterparty(CounterpartyModel(
        name: 'مشتری بدون رمز', createdAt: today, updatedAt: today, roles: const ['مشتری']));

    final plainJson = jsonEncode(await backup.collectBackupData());
    final tempFile = File('${Directory.systemTemp.path}/plain_backup_backward_compat_test.json');
    await tempFile.writeAsString(plainJson);

    // نباید هیچ استثنایی (نه رمز لازم، نه رمز غلط) پرتاب شود.
    await backup.importBackupFile(tempFile, replaceExisting: true);

    final counterparties = await db.getCounterparties();
    expect(counterparties.any((c) => c.name == 'مشتری بدون رمز'), true);

    await tempFile.delete();
  });
}
