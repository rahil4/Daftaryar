import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// نمایش اعلان محلی هنگام شناسایی تراکنش جدید از پیامک بانک
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  static Future<void> _ensureInit() async {
    if (_initialized) return;
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(settings);

    final androidImpl = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidImpl?.requestNotificationsPermission();
    _initialized = true;
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
    );
  }
}
