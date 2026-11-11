// تبدیل مبلغ به حروف فارسی - این متن پیش از ثبت به کاربر نشان داده می‌شود تا
// خطای تعداد صفر را ببیند؛ اگر خودِ تبدیل غلط باشد، کاربر را گمراه می‌کند.
import 'package:flutter_test/flutter_test.dart';

import 'package:daftaryar/utils/persian_words.dart';

void main() {
  test('اعداد یک‌رقمی، ده تا نوزده و دهگان', () {
    expect(numberToPersianWords(0), 'صفر');
    expect(numberToPersianWords(7), 'هفت');
    expect(numberToPersianWords(10), 'ده');
    expect(numberToPersianWords(11), 'یازده');
    expect(numberToPersianWords(19), 'نوزده');
    expect(numberToPersianWords(20), 'بیست');
    expect(numberToPersianWords(45), 'چهل و پنج');
    expect(numberToPersianWords(90), 'نود');
  });

  test('صدگان، از جمله شکل‌های بی‌قاعده', () {
    expect(numberToPersianWords(100), 'صد');
    expect(numberToPersianWords(200), 'دویست');
    expect(numberToPersianWords(300), 'سیصد');
    expect(numberToPersianWords(500), 'پانصد');
    expect(numberToPersianWords(115), 'صد و پانزده');
    expect(numberToPersianWords(999), 'نهصد و نود و نه');
  });

  test('هزار، میلیون و میلیارد', () {
    expect(numberToPersianWords(1000), 'یک هزار');
    expect(numberToPersianWords(2500), 'دو هزار و پانصد');
    expect(numberToPersianWords(45000000), 'چهل و پنج میلیون');
    expect(numberToPersianWords(1250000000), 'یک میلیارد و دویست و پنجاه میلیون');
    expect(numberToPersianWords(12345678),
        'دوازده میلیون و سیصد و چهل و پنج هزار و ششصد و هفتاد و هشت');
  });

  test('گروه‌های صفر میانی نام برده نمی‌شوند', () {
    expect(numberToPersianWords(1000000), 'یک میلیون');
    expect(numberToPersianWords(1000001), 'یک میلیون و یک');
    expect(numberToPersianWords(5000300), 'پنج میلیون و سیصد');
  });

  test('عدد منفی و عدد خارج از محدوده', () {
    expect(numberToPersianWords(-250), 'منفی دویست و پنجاه');
    expect(numberToPersianWords(1000000000000000), '');
  });

  test('مبلغ به حروف واحد تومان می‌گیرد و برای صفر چیزی نمایش نمی‌دهد', () {
    expect(amountToPersianWords(45000000), 'چهل و پنج میلیون تومان');
    expect(amountToPersianWords(0), '');
    expect(amountToPersianWords(-5), '');
    expect(amountToPersianWords(1500.4), 'یک هزار و پانصد تومان');
  });
}
