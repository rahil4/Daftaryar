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

/// رشته ورودی (با ارقام فارسی/لاتین و جداکننده سه‌رقمی) را به عدد خام تبدیل می‌کند
double? parsePersianAmount(String text) {
  final latinDigitsOnly = text.split('').map((ch) {
    final idx = _persianDigits.indexOf(ch);
    return idx >= 0 ? idx.toString() : ch;
  }).join();
  final digitsOnly = latinDigitsOnly.replaceAll(RegExp(r'[^0-9]'), '');
  if (digitsOnly.isEmpty) return null;
  return double.tryParse(digitsOnly);
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

/// بازه سال مالی جاری را بر اساس روز/ماه شروع سال مالی و تاریخ امروز محاسبه می‌کند.
/// اگر امروز از تاریخ شروع سال مالی در همین سال شمسی گذشته باشد، سال مالی
/// جاری همان سال است؛ در غیر این صورت سال مالی از سال قبل شروع شده.
List<Jalali> currentFiscalYearRange(int startMonth, int startDay, Jalali today) {
  Jalali candidate;
  try {
    candidate = Jalali(today.year, startMonth, startDay);
  } catch (_) {
    candidate = Jalali(today.year, startMonth, 1);
  }
  final fyStart = today.compareTo(candidate) >= 0
      ? candidate
      : Jalali(today.year - 1, startMonth, startDay > 29 ? 29 : startDay);
  final fyEnd = fyStart.addYears(1).addDays(-1);
  return [fyStart, fyEnd];
}

/// بازه ماه جاری شمسی (از روز اول ماه تا امروز)
List<Jalali> currentMonthToDateRange(Jalali today) {
  return [Jalali(today.year, today.month, 1), today];
}

/// شروع و پایان هفته شمسی (شنبه تا جمعه) حاوی تاریخ داده‌شده را برمی‌گرداند
List<Jalali> jalaliWeekRange(Jalali date) {
  // در پکیج shamsi_date: weekDay از ۱ (شنبه) تا ۷ (جمعه) شماره‌گذاری می‌شود
  final start = date.addDays(-(date.weekDay - 1));
  final end = start.addDays(6);
  return [start, end];
}
