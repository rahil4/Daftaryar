/// تبدیل عدد صحیح به حروف فارسی - برای نمایش «مبلغ به حروف» زیر فیلد مبلغ،
/// تا خطای یک صفر کم/زیاد پیش از ثبت دیده شود. فقط نمایشی است.
const List<String> _ones = ['', 'یک', 'دو', 'سه', 'چهار', 'پنج', 'شش', 'هفت', 'هشت', 'نه'];
const List<String> _teens = [
  'ده',
  'یازده',
  'دوازده',
  'سیزده',
  'چهارده',
  'پانزده',
  'شانزده',
  'هفده',
  'هجده',
  'نوزده',
];
const List<String> _tens = ['', '', 'بیست', 'سی', 'چهل', 'پنجاه', 'شصت', 'هفتاد', 'هشتاد', 'نود'];
const List<String> _hundreds = [
  '',
  'صد',
  'دویست',
  'سیصد',
  'چهارصد',
  'پانصد',
  'ششصد',
  'هفتصد',
  'هشتصد',
  'نهصد',
];
const List<String> _scales = ['', 'هزار', 'میلیون', 'میلیارد', 'هزار میلیارد'];

String _threeDigitsToWords(int n) {
  final parts = <String>[];
  final hundreds = n ~/ 100;
  final rest = n % 100;
  if (hundreds > 0) parts.add(_hundreds[hundreds]);
  if (rest >= 10 && rest < 20) {
    parts.add(_teens[rest - 10]);
  } else {
    if (rest >= 20) parts.add(_tens[rest ~/ 10]);
    if (rest % 10 > 0) parts.add(_ones[rest % 10]);
  }
  return parts.join(' و ');
}

/// مثال: ۴۵٬۰۰۰٬۰۰۰ ← «چهل و پنج میلیون». برای عددی بزرگ‌تر از محدوده
/// پشتیبانی‌شده (۱۰^۱۵ به بالا) رشته خالی برمی‌گرداند تا چیز نادرستی نمایش
/// داده نشود.
String numberToPersianWords(int number) {
  if (number == 0) return 'صفر';
  if (number < 0) return 'منفی ${numberToPersianWords(-number)}';

  final groups = <int>[];
  var remaining = number;
  while (remaining > 0) {
    groups.add(remaining % 1000);
    remaining ~/= 1000;
  }
  if (groups.length > _scales.length) return '';

  final parts = <String>[];
  for (var i = groups.length - 1; i >= 0; i--) {
    if (groups[i] == 0) continue;
    final words = _threeDigitsToWords(groups[i]);
    parts.add(_scales[i].isEmpty ? words : '$words ${_scales[i]}');
  }
  return parts.join(' و ');
}

/// مبلغ به حروف همراه واحد: «چهل و پنج میلیون تومان». برای مبلغ صفر یا
/// خارج از محدوده، رشته خالی (چیزی برای نمایش نیست).
String amountToPersianWords(num amount) {
  final rounded = amount.round();
  if (rounded <= 0) return '';
  final words = numberToPersianWords(rounded);
  return words.isEmpty ? '' : '$words تومان';
}
