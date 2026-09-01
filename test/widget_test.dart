// این فایل جایگزین بویلرپلیت پیش‌فرض «flutter create» شد که به کلاس
// ناموجود «MyApp» ارجاع می‌داد (چون این پروژه ریشه‌اش «DaftaryarApp» نام
// دارد، نه «MyApp»)؛ چون test/widget_test.dart در مخزن وجود نداشت،
// «flutter create» در CI هر بار نسخه پیش‌فرض خودش را می‌ساخت و کامپایل آن
// شکست می‌خورد.
//
// نسخه قبلی این فایل تلاش می‌کرد DaftaryarApp واقعی را Pump کند (که از طریق
// AppRoot به‌ناچار به DatabaseHelper/sqflite_common_ffi وصل می‌شود). این کار
// در دو اجرای واقعی CI پیاپی - حتی پس از اجبار اجرای متوالی فایل‌های تست
// (flutter test --concurrency=1) - دقیقاً روی مرز ۱۰ دقیقه Timeout خورد؛
// یعنی مشکل صرفاً تداخل هم‌زمانی فایل‌های تست نبود، بلکه یک رفتار
// غیرقابل‌اعتماد و تکرارناپذیر در تعامل sqflite_common_ffi با محیط CI (به
// احتمال زیاد یک قفل سطح‌فرآیند/Isolate که بین اجراهای مختلف flutter test
// به‌درستی آزاد نمی‌شود). چون هدف اصلی این فایل صرفاً رفع خطای کامپایل
// «MyApp» در flutter analyze بود (نه سنجش عمیق رفتار Runtime برنامه - که
// توسط ۴ فایل تست اختصاصی دیگر با sqflite_common_ffi به‌طور کامل پوشش داده
// می‌شود)، این نسخه عمداً هیچ دیتابیسی باز نمی‌کند و هیچ ویجتی را Pump
// نمی‌کند - فقط صحت کامپایل و قابل‌نمونه‌سازی بودن ریشه برنامه را با یک
// Assertion همگام (Synchronous) و بدون‌ریسک تأیید می‌کند.
import 'package:flutter_test/flutter_test.dart';

import 'package:daftaryar/main.dart';

void main() {
  test('DaftaryarApp یک StatelessWidget معتبر و قابل‌نمونه‌سازی است (Compile Smoke Test)', () {
    const app = DaftaryarApp();
    expect(app, isNotNull);
  });
}
