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

/// سطح تفکیک محور افقی نمودار روند داشبورد.
enum ChartGranularity { week, month, quarter, year }

/// طرح کامل محور افقی نمودار روند: بازه‌های واقعی برای Query داده هر ستون
/// (buckets) و یک زیرنویس اختیاری زیر کل محور - سطح هفته: «هفته N | تاریخ
/// تا تاریخ»، سطح ماه: «نام‌ماه سال»، سطح فصل/سال (وقتی همه ستون‌ها در یک
/// سال باشند): «سال سال».
class ChartAxisPlan {
  final List<DashboardPeriodRange> buckets;
  final String? caption;
  ChartAxisPlan({required this.buckets, this.caption});
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
  /// نام روزهای هفته شمسی - برای برچسب دوخطی Bucketهای روزانه (نام روز +
  /// تاریخ) در نمودار روند؛ اندیس بر مبنای Jalali.weekDay (۱=شنبه..۷=جمعه).
  static const List<String> _weekDayNames = [
    'شنبه',
    'یکشنبه',
    'دوشنبه',
    'سه‌شنبه',
    'چهارشنبه',
    'پنجشنبه',
    'جمعه',
  ];

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

  /// سطح تفکیک محور افقی نمودار روند داشبورد - انتخاب می‌شود بر مبنای
  /// این‌که بازه انتخابی به کدام واحد تقویمی طبیعی نزدیک‌تر است، نه یک
  /// آستانه دلخواه روی تعداد خام روز.
  static ChartGranularity resolveGranularity(
    DashboardPeriodPreset preset,
    String fromDate,
    String toDate,
  ) {
    switch (preset) {
      case DashboardPeriodPreset.today:
      case DashboardPeriodPreset.thisWeek:
        return ChartGranularity.week;
      case DashboardPeriodPreset.thisMonth:
      case DashboardPeriodPreset.lastMonth:
        return ChartGranularity.month;
      case DashboardPeriodPreset.thisQuarter:
      case DashboardPeriodPreset.lastQuarter:
        return ChartGranularity.quarter;
      case DashboardPeriodPreset.thisYear:
      case DashboardPeriodPreset.lastYear:
        return ChartGranularity.year;
      case DashboardPeriodPreset.custom:
        final start = parseJalaliString(fromDate)!;
        final end = parseJalaliString(toDate)!;
        final spanDays = end.julianDayNumber - start.julianDayNumber + 1;
        if (spanDays <= 9) return ChartGranularity.week;
        if (spanDays <= 35) return ChartGranularity.month;
        if (spanDays <= 100) return ChartGranularity.quarter;
        return ChartGranularity.year;
    }
  }

  /// طرح کامل محور افقی نمودار روند برای بازه/Preset انتخابی - رفتار دقیقاً
  /// طبق درخواست کاربر برای هر سطح:
  /// - هفته (امروز/این‌هفته/بازه سفارشی کوتاه): ۷ ستون شنبه→جمعه همان هفته،
  ///   لیبل فقط نام روز (افقی)، به‌همراه زیرنویس مشترک زیر کل محور («هفته
  ///   N | تاریخ تا تاریخ»).
  /// - ماه (این‌ماه/ماه‌قبل/بازه سفارشی حدود یک ماه): یک ستون به ازای هر
  ///   روز بازه، لیبل فقط عدد روز، زیرنویس «نام‌ماه سال».
  /// - فصل/سال: یک ستون به ازای هر ماه بازه؛ اگر همه ماه‌ها در یک سال
  ///   باشند (حالت معمول)، لیبل هر ستون فقط نام ماه است (بدون تکرار سال
  ///   روی هر ستون) و سال یک‌بار در زیرنویس می‌آید.
  static ChartAxisPlan buildAxisPlan(
    DashboardPeriodPreset preset,
    String fromDate,
    String toDate,
  ) {
    final granularity = resolveGranularity(preset, fromDate, toDate);
    switch (granularity) {
      case ChartGranularity.week:
        return _weekAxisPlan(fromDate);
      case ChartGranularity.month:
        return _monthAxisPlan(fromDate, toDate);
      case ChartGranularity.quarter:
      case ChartGranularity.year:
        return _monthlyColumnsAxisPlan(fromDate, toDate);
    }
  }

  static ChartAxisPlan _weekAxisPlan(String fromDate) {
    final ref = parseJalaliString(fromDate)!;
    final range = jalaliWeekRange(ref);
    final weekStart = range[0];
    final weekEnd = range[1];
    final buckets = <DashboardPeriodRange>[];
    for (var i = 0; i < 7; i++) {
      final day = weekStart.addDays(i);
      buckets.add(DashboardPeriodRange(
        fromDate: jalaliToString(day),
        toDate: jalaliToString(day),
        label: _weekDayNames[day.weekDay - 1],
      ));
    }
    final caption = 'هفته ${pn(_weekNumberOfYear(weekStart))} | ${_dateRangeText(weekStart, weekEnd)}';
    return ChartAxisPlan(buckets: buckets, caption: caption);
  }

  static ChartAxisPlan _monthAxisPlan(String fromDate, String toDate) {
    final start = parseJalaliString(fromDate)!;
    final end = parseJalaliString(toDate)!;
    final buckets = <DashboardPeriodRange>[];
    var cursor = start;
    while (cursor.compareTo(end) <= 0) {
      buckets.add(DashboardPeriodRange(
        fromDate: jalaliToString(cursor),
        toDate: jalaliToString(cursor),
        label: pn(cursor.day),
      ));
      cursor = cursor.addDays(1);
    }
    // اگر بازه دقیقاً یک ماه تقویمی کامل باشد (حالت معمول این‌ماه/ماه‌قبل)،
    // زیرنویس فقط «نام‌ماه سال» است؛ اگر بازه سفارشی از مرز ماه عبور کند،
    // برای رفع ابهام بازه دقیق تاریخ نشان داده می‌شود.
    final caption = (start.year == end.year && start.month == end.month)
        ? '${_monthNames[start.month - 1]} ${pn(start.year)}'
        : _dateRangeText(start, end);
    return ChartAxisPlan(buckets: buckets, caption: caption);
  }

  /// طرح محور افقی سطح فصل/سال: هر ستون یک ماه. اگر همه ماه‌های بازه در
  /// یک سال شمسی باشند (حالت معمول این‌فصل/فصل‌قبل/امسال/سال‌قبل)، لیبل هر
  /// ستون فقط نام ماه است و سال یک‌بار در زیرنویس می‌آید - نه تکرار «نام‌ماه
  /// سال» روی هر ستون. اگر بازه (فقط ممکن برای بازه سفارشی، یا سال مالی
  /// سفارشی که از مرز سال تقویمی عبور می‌کند) بیش از یک سال را پوشش دهد،
  /// برای رفع ابهام هر ستون نام سال خودش را هم نگه می‌دارد و زیرنویسی
  /// نمایش داده نمی‌شود.
  static ChartAxisPlan _monthlyColumnsAxisPlan(String fromDate, String toDate) {
    final monthly = monthlyBuckets(fromDate, toDate);
    final years = monthly.map((b) => parseJalaliString(b.fromDate)!.year).toSet();
    if (years.length == 1) {
      final simplified = monthly.map((b) {
        final d = parseJalaliString(b.fromDate)!;
        return DashboardPeriodRange(fromDate: b.fromDate, toDate: b.toDate, label: _monthNames[d.month - 1]);
      }).toList();
      return ChartAxisPlan(buckets: simplified, caption: 'سال ${pn(years.first)}');
    }
    return ChartAxisPlan(buckets: monthly);
  }

  /// شماره هفته از ابتدای سال شمسیِ [weekStart] - هفته ۱ = هفته‌ای که ۱
  /// فروردین همان سال در آن قرار دارد؛ هفته‌ها بر مبنای شنبه محاسبه
  /// می‌شوند (هم‌راستا با jalaliWeekRange). این فقط یک شماره نمایشی برای
  /// زیرنویس نمودار است، نه یک استاندارد رسمی (تقویم جلالی تعریف رسمی
  /// «شماره هفته سال» ندارد).
  static int _weekNumberOfYear(Jalali weekStart) {
    final firstWeekStart = jalaliWeekRange(Jalali(weekStart.year, 1, 1))[0];
    final diffDays = weekStart.julianDayNumber - firstWeekStart.julianDayNumber;
    return (diffDays / 7).round() + 1;
  }

  /// نمایش خوانای بازه [start]..[end] برای زیرنویس نمودار - اگر هر دو سر
  /// در یک ماه/سال باشند کوتاه («۲۰ تا ۲۷ اردیبهشت ۱۴۰۵»)، وگرنه (هفته‌ای
  /// که از مرز ماه یا سال عبور می‌کند) هر سر بازه نام ماه/سال خودش را
  /// جداگانه می‌گیرد.
  static String _dateRangeText(Jalali start, Jalali end) {
    if (start.year == end.year && start.month == end.month) {
      return '${pn(start.day)} تا ${pn(end.day)} ${_monthNames[start.month - 1]} ${pn(start.year)}';
    }
    if (start.year == end.year) {
      return '${pn(start.day)} ${_monthNames[start.month - 1]} تا ${pn(end.day)} ${_monthNames[end.month - 1]} ${pn(start.year)}';
    }
    return '${pn(start.day)} ${_monthNames[start.month - 1]} ${pn(start.year)} تا '
        '${pn(end.day)} ${_monthNames[end.month - 1]} ${pn(end.year)}';
  }
}
