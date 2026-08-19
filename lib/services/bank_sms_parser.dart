/// نتیجه پارس یک پیامک بانکی: مبلغ (به تومان) و نوع تراکنش
class BankSmsParseResult {
  final double amount;
  final String type; // 'دریافت' یا 'پرداخت'
  BankSmsParseResult({required this.amount, required this.type});
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

final _amountRegex = RegExp(r'([\d]{1,3}(?:[,،.][\d]{3})+|\d{4,})\s*(ریال|تومان)?');

/// متن یک پیامک را بررسی می‌کند و در صورت تشخیص الگوی تراکنش بانکی،
/// مبلغ (تبدیل‌شده به تومان) و نوع آن را برمی‌گرداند؛ در غیر این صورت null.
BankSmsParseResult? parseBankSms(String body) {
  final hasIncomeKeyword = _incomeKeywords.any((k) => body.contains(k));
  final hasExpenseKeyword = _expenseKeywords.any((k) => body.contains(k));
  if (!hasIncomeKeyword && !hasExpenseKeyword) return null;

  // برای کاهش تشخیص اشتباه، وجود شواهد بانکی بیشتر (واحد پول یا کلمه حساب/کارت) را هم می‌طلبیم
  final hasBankContext =
      body.contains('ریال') || body.contains('تومان') || body.contains('حساب') || body.contains('کارت');
  if (!hasBankContext) return null;

  final matches = _amountRegex.allMatches(body).toList();
  if (matches.isEmpty) return null;

  final match = matches.first;
  final rawNumber = match.group(1)!.replaceAll(RegExp(r'[,،.]'), '');
  var amount = double.tryParse(rawNumber) ?? 0;
  if (amount <= 0) return null;

  final unit = match.group(2);
  if (unit == 'ریال') {
    amount = amount / 10; // تبدیل ریال به تومان
  }

  final type = hasIncomeKeyword && !hasExpenseKeyword ? 'دریافت' : 'پرداخت';
  return BankSmsParseResult(amount: amount, type: type);
}
