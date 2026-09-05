import 'package:shamsi_date/shamsi_date.dart';

import 'formatters.dart';

/// گزینه‌های پیش‌فرض انتخاب بازه در داشبورد مدیریتی
enum DashboardPeriodPreset {
  today,
  thisWeek,
  thisMonth,
  lastMonth,
  thisQuarter,
  lastQuarter,
  thisYear,
  lastYear,
  custom,
}

const Map<DashboardPeriodPreset, String> kDashboardPeriodLabels = {
  DashboardPeriodPreset.today: 'امروز',
  DashboardPeriodPreset.thisWeek: 'این هفته',
  DashboardPeriodPreset.thisMonth: 'این ماه',
  DashboardPeriodPreset.lastMonth: 'ماه قبل',
  DashboardPeriodPreset.thisQuarter: 'این فصل',
  DashboardPeriodPreset.lastQuarter: 'فصل قبل',
  DashboardPeriodPreset.thisYear: 'امسال',
  DashboardPeriodPreset.lastYear: 'سال قبل',
  DashboardPeriodPreset.custom: 'بازه سفارشی',
};

/// یک بازه تاریخ شمسی مشخص با برچسب نمایشی - صرفاً محاسبه تاریخ، هیچ
/// داده مالی در این کلاس نیست.
class DashboardPeriodRange {
  final String fromDate; // شمسی yyyy/mm/dd
  final String toDate;
  final String label;

  DashboardPeriodRange({required this.fromDate, required this.toDate, required this.label});
}

/// محاسبه بازه‌های تاریخ برای گزینه‌های پیش‌فرض داشبورد - فقط ریاضیات تاریخ،
/// هیچ ارتباطی با دیتابیس یا Ledger ندارد.
class DashboardPeriodResolver {
  static DashboardPeriodRange resolve(
    DashboardPeriodPreset preset, {
    Jalali? today,
    String? customFrom,
    String? customTo,
    // پیش‌فرض ۱/۱ یعنی سال مالی = سال تقویمی (وقتی کاربر سال مالی سفارشی
    // تنظیم نکرده)؛ با این پیش‌فرض، رفتار قبلی این دو Preset بدون تغییر
    // باقی می‌ماند. اگر کاربر سال مالی سفارشی تنظیم کرده باشد (از طریق
    // DatabaseHelper.getFiscalYearStart)، Caller باید مقدار واقعی را اینجا
    // پاس دهد تا این‌سال/سال‌قبل واقعاً بر مبنای سال مالی محاسبه شوند - نه
    // همیشه فروردین تا اسفند تقویمی، صرف‌نظر از تنظیمات کاربر.
    int fiscalYearStartMonth = 1,
    int fiscalYearStartDay = 1,
  }) {
    final now = today ?? Jalali.now();
    final isCalendarYear = fiscalYearStartMonth == 1 && fiscalYearStartDay == 1;
    switch (preset) {
      case DashboardPeriodPreset.today:
        return DashboardPeriodRange(
            fromDate: jalaliToString(now), toDate: jalaliToString(now), label: kDashboardPeriodLabels[preset]!);

      case DashboardPeriodPreset.thisWeek:
        final range = jalaliWeekRange(now);
        return DashboardPeriodRange(
            fromDate: jalaliToString(range[0]),
            toDate: jalaliToString(range[1]),
            label: kDashboardPeriodLabels[preset]!);

      case DashboardPeriodPreset.thisMonth:
        final start = Jalali(now.year, now.month, 1);
        final end = Jalali(now.year, now.month, start.monthLength);
        return DashboardPeriodRange(
            fromDate: jalaliToString(start), toDate: jalaliToString(end), label: kDashboardPeriodLabels[preset]!);

      case DashboardPeriodPreset.lastMonth:
        final firstOfThisMonth = Jalali(now.year, now.month, 1);
        final lastDayOfPrevMonth = firstOfThisMonth.addDays(-1);
        final start = Jalali(lastDayOfPrevMonth.year, lastDayOfPrevMonth.month, 1);
        return DashboardPeriodRange(
            fromDate: jalaliToString(start),
            toDate: jalaliToString(lastDayOfPrevMonth),
            label: kDashboardPeriodLabels[preset]!);

      case DashboardPeriodPreset.thisQuarter:
        final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        final start = Jalali(now.year, qStartMonth, 1);
        final endMonthJalali = Jalali(now.year, qStartMonth + 2, 1);
        final end = Jalali(endMonthJalali.year, endMonthJalali.month, endMonthJalali.monthLength);
        return DashboardPeriodRange(
            fromDate: jalaliToString(start), toDate: jalaliToString(end), label: kDashboardPeriodLabels[preset]!);

      case DashboardPeriodPreset.lastQuarter:
        final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
        final thisQStart = Jalali(now.year, qStartMonth, 1);
        final lastQEnd = thisQStart.addDays(-1);
        final lastQStartMonth = ((lastQEnd.month - 1) ~/ 3) * 3 + 1;
        final lastQStart = Jalali(lastQEnd.year, lastQStartMonth, 1);
        return DashboardPeriodRange(
            fromDate: jalaliToString(lastQStart),
            toDate: jalaliToString(lastQEnd),
            label: kDashboardPeriodLabels[preset]!);

      case DashboardPeriodPreset.thisYear:
        final fy = currentFiscalYearRange(fiscalYearStartMonth, fiscalYearStartDay, now);
        return DashboardPeriodRange(
            fromDate: jalaliToString(fy[0]),
            toDate: jalaliToString(fy[1]),
            label: isCalendarYear ? kDashboardPeriodLabels[preset]! : 'سال مالی جاری');

      case DashboardPeriodPreset.lastYear:
        final fy = currentFiscalYearRange(fiscalYearStartMonth, fiscalYearStartDay, now);
        final lastFyStart = fy[0].addYears(-1);
        final lastFyEnd = fy[1].addYears(-1);
        return DashboardPeriodRange(
            fromDate: jalaliToString(lastFyStart),
            toDate: jalaliToString(lastFyEnd),
            label: isCalendarYear ? kDashboardPeriodLabels[preset]! : 'سال مالی قبل');

      case DashboardPeriodPreset.custom:
        final from = customFrom ?? jalaliToString(now);
        final to = customTo ?? jalaliToString(now);
        return DashboardPeriodRange(fromDate: from, toDate: to, label: kDashboardPeriodLabels[preset]!);
    }
  }

  /// بازه‌ای دقیقاً هم‌طول، بلافاصله پیش از بازه داده‌شده - برای مقایسه دوره‌ای
  static DashboardPeriodRange previousPeriodOf(DashboardPeriodRange range) {
    final start = parseJalaliString(range.fromDate)!;
    final end = parseJalaliString(range.toDate)!;
    final lengthDays = end.julianDayNumber - start.julianDayNumber + 1;
    final prevEnd = start.addDays(-1);
    final prevStart = prevEnd.addDays(-(lengthDays - 1));
    return DashboardPeriodRange(
        fromDate: jalaliToString(prevStart), toDate: jalaliToString(prevEnd), label: 'دوره قبل');
  }

  /// فهرست بازه‌های ماهانه بین دو تاریخ (شامل هر دو سر بازه) - برای نمودارهای
  /// روند ماهانه؛ صرفاً محاسبه تاریخ است.
  static const List<String> _monthNames = [
    'فروردین',
    'اردیبهشت',
    'خرداد',
    'تیر',
    'مرداد',
    'شهریور',
    'مهر',
    'آبان',
    'آذر',
    'دی',
    'بهمن',
    'اسفند',
  ];

  /// فهرست بازه‌های ماهانه بین دو تاریخ - هر Bucket دقیقاً با بازه واقعی
  /// [fromDate, toDate] برخورد (Intersection) دارد؛ اولین Bucket از خودِ
  /// fromDate شروع می‌شود (نه لزوماً روز اول ماه) و آخرین Bucket دقیقاً در
  /// toDate تمام می‌شود (نه لزوماً آخر ماه). این‌طوری برای یک بازه سفارشی
  /// مثل «۱۵ مرداد تا ۱۰ شهریور»، هیچ روزی خارج از بازه انتخابی وارد Trend
  /// نمی‌شود. برای Periodهای کامل ماه/سال (که fromDate/toDate خودشان دقیقاً
  /// اول/آخر ماه‌اند)، رفتار قبلی بدون تغییر باقی می‌ماند.
  /// N ماه کامل منتهی به ماهِ تاریخ مرجع (شامل خودِ آن ماه) - مخصوص نمودار
  /// روند. برخلاف monthlyBuckets که بازه انتخابی را تکه می‌کند، این تابع
  /// همیشه چند ماه برمی‌گرداند؛ چون یک «روند» ذاتاً به چند نقطه نیاز دارد
  /// و اگر بازه انتخابی کوتاه باشد (مثل «امروز» یا «این ماه»)، تقسیم آن
  /// فقط یک نقطه تولید می‌کند که هیچ روندی نشان نمی‌دهد.
  static List<DashboardPeriodRange> lastNMonths(int count, {Jalali? reference}) {
    final ref = reference ?? Jalali.now();
    final buckets = <DashboardPeriodRange>[];
    for (var i = count - 1; i >= 0; i--) {
      var year = ref.year;
      var month = ref.month - i;
      while (month <= 0) {
        month += 12;
        year -= 1;
      }
      final first = Jalali(year, month, 1);
      final last = Jalali(year, month, first.monthLength);
      buckets.add(DashboardPeriodRange(
        fromDate: jalaliToString(first),
        toDate: jalaliToString(last),
        label: '${_monthNames[month - 1]} $year',
      ));
    }
    return buckets;
  }

  static List<DashboardPeriodRange> monthlyBuckets(String fromDate, String toDate) {
    final start = parseJalaliString(fromDate)!;
    final end = parseJalaliString(toDate)!;
    final buckets = <DashboardPeriodRange>[];
    var cursor = start;
    while (cursor.compareTo(end) <= 0) {
      final naturalMonthEnd = Jalali(cursor.year, cursor.month, cursor.monthLength);
      final bucketEnd = naturalMonthEnd.compareTo(end) <= 0 ? naturalMonthEnd : end;
      buckets.add(DashboardPeriodRange(
        fromDate: jalaliToString(cursor),
        toDate: jalaliToString(bucketEnd),
        label: '${_monthNames[cursor.month - 1]} ${cursor.year}',
      ));
      cursor = bucketEnd.addDays(1);
    }
    return buckets;
  }

  /// فهرست بازه‌های تک‌روزه بین دو تاریخ (شامل هر دو سر بازه) - برای نمودار
  /// روند در بازه‌های کوتاه (هفته/ماه جاری) که تفکیک ماهانه فقط یک Bucket
  /// (و در نتیجه یک نقطه بی‌فایده) تولید می‌کرد.
  static List<DashboardPeriodRange> dailyBuckets(String fromDate, String toDate) {
    final start = parseJalaliString(fromDate)!;
    final end = parseJalaliString(toDate)!;
    final buckets = <DashboardPeriodRange>[];
    var cursor = start;
    while (cursor.compareTo(end) <= 0) {
      buckets.add(DashboardPeriodRange(
        fromDate: jalaliToString(cursor),
        toDate: jalaliToString(cursor),
        label: '${pn(cursor.day)} ${_monthNames[cursor.month - 1]}',
      ));
      cursor = cursor.addDays(1);
    }
    return buckets;
  }

  /// N روز اخیر منتهی به تاریخ مرجع (شامل خودِ آن روز) - فقط برای بازه‌های
  /// تک‌روزه انتخابی (مثل «امروز») که حتی تفکیک روزانه هم یک نقطه تنها
  /// می‌دهد؛ یک روند معنادار به‌جایش لازم است.
  static List<DashboardPeriodRange> lastNDays(int count, {Jalali? reference}) {
    final ref = reference ?? Jalali.now();
    final buckets = <DashboardPeriodRange>[];
    for (var i = count - 1; i >= 0; i--) {
      final day = ref.addDays(-i);
      buckets.add(DashboardPeriodRange(
        fromDate: jalaliToString(day),
        toDate: jalaliToString(day),
        label: '${pn(day.day)} ${_monthNames[day.month - 1]}',
      ));
    }
    return buckets;
  }

  /// انتخاب خودکار Bucketهای نمودار روند بر مبنای طول واقعی بازه انتخابی -
  /// به‌جای همیشه پرش به یک بازه ثابت (۶ ماه اخیر) که ربطی به انتخاب کاربر
  /// نداشت. بازه‌های کوتاه (هفته/ماه جاری/سفارشی کوتاه) اکنون با جزئیات
  /// روزانه *همان بازه انتخابی* نمایش داده می‌شوند - نه یک بازه متفاوت.
  static List<DashboardPeriodRange> trendBuckets(String fromDate, String toDate) {
    final start = parseJalaliString(fromDate)!;
    final end = parseJalaliString(toDate)!;
    final spanDays = end.julianDayNumber - start.julianDayNumber + 1;
    if (spanDays <= 1) {
      // بازه تک‌روزه (مثل «امروز») - تفکیک روزانه همین بازه هم فقط یک نقطه
      // می‌دهد؛ ۱۴ روز اخیر به‌عنوان روند معنادار جایگزین آن است.
      return lastNDays(14, reference: end);
    }
    if (spanDays <= 62) {
      // هفته/ماه جاری/فصل کوتاه/بازه سفارشی کوتاه - جزئیات روزانه همان
      // بازه انتخابی.
      return dailyBuckets(fromDate, toDate);
    }
    // بازه‌های بلندتر (فصل/سال) - تفکیک ماهانه، مثل قبل.
    return monthlyBuckets(fromDate, toDate);
  }
}
