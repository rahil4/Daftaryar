import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../navigation.dart';
import '../screens/sms_drafts/sms_drafts_screen.dart';

const _draftPayload = 'sms_drafts';

/// نمایش اعلان لحظه‌ای برای هر تراکنش بانکی تازه‌شناسایی‌شده از پیامک
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

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
  static Future<void> requestPermission() async {
    await _ensureInit();
    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
  }

  static void _onNotificationTap(NotificationResponse response) {
    if (response.payload == _draftPayload) {
      rootNavigatorKey.currentState?.push(
        MaterialPageRoute(builder: (_) => const SmsDraftsScreen()),
      );
    }
  }

  static Future<void> showTransactionDetected({
    required String title,
    required String body,
  }) async {
    // اعلان صرفاً یک قابلیت جانبی است؛ هرگز نباید جریان اصلی ثبت تراکنش را
    // مختل کند، پس خطای احتمالی آن (مثل باگ شناخته‌شده این پکیج در برخی
    // دستگاه‌ها) اینجا بی‌صدا نادیده گرفته می‌شود.
    try {
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
        payload: _draftPayload,
      );
    } catch (_) {
      // نادیده گرفته می‌شود - نبود اعلان نباید مانع ثبت سند شود
    }
  }
}
