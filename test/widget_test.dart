// این فایل جایگزین بویلرپلیت پیش‌فرض «flutter create» شد که به کلاس
// ناموجود «MyApp» ارجاع می‌داد (چون این پروژه ریشه‌اش «DaftaryarApp» نام
// دارد، نه «MyApp»)؛ چون test/widget_test.dart در مخزن وجود نداشت،
// «flutter create» در CI هر بار نسخه پیش‌فرض خودش را می‌ساخت و کامپایل آن
// شکست می‌خورد. این نسخه واقعی برنامه را Smoke-Test می‌کند.
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:daftaryar/db/database_helper.dart';
import 'package:daftaryar/main.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  testWidgets('DaftaryarApp بدون Exception ساخته و یک فریم Render می‌شود (Smoke Test)',
      (WidgetTester tester) async {
    // دیتابیس تازه: sms_reading_enabled تنظیم نشده، پس مسیر
    // NotificationService/SmsListenerService (که به Platform Channel واقعی
    // نیاز دارند و در محیط تست ویجت موجود نیستند) هرگز در AppRoot._check()
    // فراخوانی نمی‌شود.
    await DatabaseHelper.instance.wipeAll();

    await tester.pumpWidget(const DaftaryarApp());
    // یک فریم ساده (نه pumpAndSettle) تا منتظر هیچ تایمر/انیمیشن نامحدودی
    // نمانیم؛ هدف فقط اثبات این است که ساخت اولیه درخت ویجت (شامل
    // MaterialApp/Theme/Localization) بدون Exception انجام می‌شود - چه در
    // حالت Loading اولیه (CircularProgressIndicator) بماند چه جلوتر برود.
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
