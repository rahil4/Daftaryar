import 'package:shamsi_date/shamsi_date.dart';

const _persianDigits = ['۰', '۱', '۲', '۳', '۴', '۵', '۶', '۷', '۸', '۹'];

/// تبدیل هر رشته حاوی اعداد لاتین به ارقام فارسی (فقط برای نمایش)
String toPersianDigits(Object input) {
  final s = input.toString();
  final buffer = StringBuffer();
  for (final ch in s.split('')) {
    final code = ch.codeUnitAt(0);
    if (code >= 48 && code <= 57) {
      buffer.write(_persianDigits[code - 48]);
    } else {
      buffer.write(ch);
    }
  }
  return buffer.toString();
}

/// میان‌بر کوتاه برای تبدیل هر مقدار (عدد/شناسه) به ارقام فارسی جهت نمایش
String pn(Object value) => toPersianDigits(value);

/// مبلغ را با جداکننده سه‌رقمی فارسی («٬») و ارقام فارسی نمایش می‌دهد،
/// مثال: ۱٬۲۳۴٬۵۶۷ تومان
String formatMoney(num amount, {bool withSuffix = true}) {
  final isNegative = amount < 0;
  final rounded = amount.abs().round();
  final digits = rounded.toString();
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('٬');
    buffer.write(digits[i]);
  }
  var result = toPersianDigits(buffer.toString());
  if (isNegative) result = '−$result';
  return withSuffix ? '$result تومان' : result;
}

/// امروز را به صورت رشته شمسی yyyy/mm/dd (ارقام لاتین، برای ذخیره‌سازی و مرتب‌سازی) برمی‌گرداند
String todayJalaliString() {
  final j = Jalali.now();
  return jalaliToString(j);
}

String jalaliToString(Jalali j) {
  final mm = j.month.toString().padLeft(2, '0');
  final dd = j.day.toString().padLeft(2, '0');
  return '${j.year}/$mm/$dd';
}

Jalali? parseJalaliString(String s) {
  final parts = s.split('/');
  if (parts.length != 3) return null;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (y == null || m == null || d == null) return null;
  try {
    return Jalali(y, m, d);
  } catch (_) {
    return null;
  }
}

String jalaliMonthName(int month) {
  const names = [
    'فروردین', 'اردیبهشت', 'خرداد', 'تیر', 'مرداد', 'شهریور',
    'مهر', 'آبان', 'آذر', 'دی', 'بهمن', 'اسفند'
  ];
  return names[month - 1];
}

/// نمایش تاریخ شمسی با ارقام فارسی، مثال: «۵ مرداد ۱۴۰۴»
String formatJalaliLong(String s) {
  final j = parseJalaliString(s);
  if (j == null) return toPersianDigits(s);
  return '${toPersianDigits(j.day)} ${jalaliMonthName(j.month)} ${toPersianDigits(j.year)}';
}
