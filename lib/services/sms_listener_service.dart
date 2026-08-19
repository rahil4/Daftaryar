import 'package:another_telephony/telephony.dart';

import '../db/database_helper.dart';
import '../models/sms_draft.dart';
import '../utils/formatters.dart';
import 'bank_sms_parser.dart';

/// این تابع باید سطح بالا (top-level) بماند تا در ایزوله پس‌زمینه پیامک قابل اجرا باشد
@pragma('vm:entry-point')
Future<void> smsBackgroundMessageHandler(SmsMessage message) async {
  await SmsListenerService.handleIncomingSms(message.body ?? '', message.address);
}

/// مدیریت دریافت و ذخیره پیش‌نویس پیامک‌های بانکی
class SmsListenerService {
  static final Telephony _telephony = Telephony.instance;

  static Future<bool> hasPermission() async {
    final granted = await _telephony.requestPhoneAndSmsPermissions;
    return granted == true;
  }

  static void startListening() {
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage message) {
        handleIncomingSms(message.body ?? '', message.address);
      },
      onBackgroundMessage: smsBackgroundMessageHandler,
      listenInBackground: true,
    );
  }

  /// پیامک ورودی را بررسی و در صورت تشخیص تراکنش بانکی، پیش‌نویس ذخیره می‌کند
  static Future<void> handleIncomingSms(String body, String? sender) async {
    if (body.trim().isEmpty) return;
    final db = DatabaseHelper.instance;

    final enabled = await db.getSetting('sms_reading_enabled');
    if (enabled != '1') return;

    final alreadyExists = await db.smsDraftExists(body);
    if (alreadyExists) return;

    final parsed = parseBankSms(body);
    if (parsed == null) return;

    await db.insertSmsDraft(SmsDraftModel(
      rawBody: body,
      sender: sender,
      amount: parsed.amount,
      type: parsed.type,
      date: todayJalaliString(),
      createdAt: todayJalaliString(),
    ));
  }
}
