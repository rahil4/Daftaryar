import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../navigation.dart';
import '../screens/sms_drafts/sms_drafts_screen.dart';
import '../utils/formatters.dart';

const _summaryPayload = 'sms_drafts';

/// نمایش اعلان‌های مربوط به پیامک بانکی: یک اعلان لحظه‌ای برای هر تراکنش
/// تازه شناسایی‌شده، و یک اعلان دائمی و به‌روزشونده که تعداد پیش‌نویس‌های
/// در انتظار را نشان می‌دهد تا ثبت آن‌ها فراموش نشود.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static const int _summaryNotificationId = 9001;

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    _initialized = true;
  }

  /// درخواست مجوز نمایش اعلان — باید فقط از یک صفحه/کانتکست فعال (نه از
  /// ایزوله پس‌زمینه شنود پیامک) فراخوانی شود، چون نیاز به یک Activity دارد.
  /// اگر این مجوز زودتر گرفته نشود، تلاش برای گرفتنش از پس‌زمینه می‌تواند
  /// بی‌صدا شکست بخورد و باعث دیرکرد یا نیامدن اعلان تراکنش تازه شود.
  static Future<void> requestPermission() async {
    await _ensureInit();
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
  }

  static void _onNotificationTap(NotificationResponse response) {
    if (response.payload == _summaryPayload) {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const SmsDraftsScreen()),
      );
    }
  }

  static Future<void> showTransactionDetected({
    required String title,
    required String body,
  }) async {
    await _ensureInit();
    const androidDetails = AndroidNotificationDetails(
      'sms_drafts_channel',
      'تراکنش‌های شناسایی‌شده',
      channelDescription: 'اعلان هنگام شناسایی تراکنش بانکی جدید از پیامک',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      details,
      payload: _summaryPayload,
    );
  }

  /// اعلان دائمی و به‌روزشونده تعداد پیش‌نویس‌های در انتظار تأیید؛
  /// با صفر شدن تعداد، خودش پاک می‌شود.
  static Future<void> updatePendingDraftsNotification(int count) async {
    await _ensureInit();
    if (count <= 0) {
      await _plugin.cancel(_summaryNotificationId);
      return;
    }
    final androidDetails = AndroidNotificationDetails(
      'sms_drafts_summary_channel',
      'یادآوری پیش‌نویس‌های در انتظار',
      channelDescription: 'یادآوری همیشگی تعداد پیش‌نویس‌های پیامکی تأییدنشده',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      onlyAlertOnce: true,
      autoCancel: false,
    );
    final details = NotificationDetails(android: androidDetails);
    await _plugin.show(
      _summaryNotificationId,
      'پیش‌نویس پیامکی در انتظار تأیید',
      '${pn(count)} تراکنش شناسایی‌شده هنوز بررسی نشده — برای مشاهده ضربه بزنید',
      details,
      payload: _summaryPayload,
    );
  }
}
