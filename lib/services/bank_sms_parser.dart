/// نتیجه پارس یک پیامک بانکی: مبلغ (به تومان) و نوع تراکنش
class BankSmsParseResult {
  final double amount;
  final String type; // 'دریافت' یا 'پرداخت'
  BankSmsParseResult({required this.amount, required this.type});
}

/// نویسه‌های عربی رایج در پیامک‌های بانکی (ي، ك) را به معادل فارسی تبدیل می‌کند
String _normalizeArabic(String input) {
  return input.replaceAll('ي', 'ی').replaceAll('ك', 'ک');
}

const _incomeKeywords = [
  'واریز',
  'واریزی',
  'انتقال به حساب شما',
  'دریافت وجه',
  'شارژ حساب',
];

const _expenseKeywords = [
  'برداشت',
  'خرید',
  'انتقال از حساب',
  'کارمزد',
  'پرداخت از',
  'برداشت از',
];

/// شواهد بانکی بودن پیامک؛ «مانده»/«موجودی» در پیامک‌های واقعی بانک‌های ایرانی
/// حتی بدون ذکر صریح «ریال»/«تومان» هم رایج است
const _bankContextWords = ['ریال', 'تومان', 'حساب', 'کارت', 'مانده', 'موجودی'];

final _amountRegex = RegExp(r'([\d]{1,3}(?:[,،.][\d]{3})+|\d{4,})\s*(ریال|تومان)?');

/// متن یک پیامک را بررسی می‌کند و در صورت تشخیص الگوی تراکنش بانکی،
/// مبلغ (تبدیل‌شده به تومان) و نوع آن را برمی‌گرداند؛ در غیر این صورت null.
BankSmsParseResult? parseBankSms(String rawBody) {
  final body = _normalizeArabic(rawBody);

  int? keywordEnd;
  bool isIncome = false;
  for (final k in _incomeKeywords) {
    final idx = body.indexOf(k);
    if (idx >= 0) {
      keywordEnd = idx + k.length;
      isIncome = true;
      break;
    }
  }
  if (keywordEnd == null) {
    for (final k in _expenseKeywords) {
      final idx = body.indexOf(k);
      if (idx >= 0) {
        keywordEnd = idx + k.length;
        break;
      }
    }
  }
  if (keywordEnd == null) return null;

  final hasBankContext = _bankContextWords.any((w) => body.contains(w));
  if (!hasBankContext) return null;

  final matches = _amountRegex.allMatches(body).toList();
  if (matches.isEmpty) return null;

  // ترجیح با نزدیک‌ترین عدد بعد از کلیدواژه تراکنش (نه هر عددی در پیامک،
  // مثل شماره پیگیری یا مانده حساب که معمولاً بعدتر می‌آیند)
  final match = matches.firstWhere((m) => m.start >= keywordEnd!, orElse: () => matches.first);

  final rawNumber = match.group(1)!.replaceAll(RegExp(r'[,،.]'), '');
  var amount = double.tryParse(rawNumber) ?? 0;
  if (amount <= 0) return null;

  final unit = match.group(2);
  if (unit == 'ریال') {
    amount = amount / 10; // تبدیل ریال به تومان
  }

  final type = isIncome ? 'دریافت' : 'پرداخت';
  return BankSmsParseResult(amount: amount, type: type);
}
