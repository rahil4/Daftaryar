import 'package:intl/intl.dart';
import 'package:shamsi_date/shamsi_date.dart';

final NumberFormat _moneyFormat = NumberFormat.decimalPattern('en');

/// عدد را با جداکننده هزارگان و پسوند «تومان» نمایش می‌دهد
String formatMoney(num amount, {bool withSuffix = true}) {
  final formatted = _moneyFormat.format(amount);
  return withSuffix ? '$formatted تومان' : formatted;
}

/// امروز را به صورت رشته شمسی yyyy/mm/dd برمی‌گرداند
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

String formatJalaliLong(String s) {
  final j = parseJalaliString(s);
  if (j == null) return s;
  return '${j.day} ${jalaliMonthName(j.month)} ${j.year}';
}
