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
  }) {
    final now = today ?? Jalali.now();
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
        final start = Jalali(now.year, 1, 1);
        final decEnd = Jalali(now.year, 12, 1);
        final end = Jalali(now.year, 12, decEnd.monthLength);
        return DashboardPeriodRange(
            fromDate: jalaliToString(start), toDate: jalaliToString(end), label: kDashboardPeriodLabels[preset]!);

      case DashboardPeriodPreset.lastYear:
        final start = Jalali(now.year - 1, 1, 1);
        final decEnd = Jalali(now.year - 1, 12, 1);
        final end = Jalali(now.year - 1, 12, decEnd.monthLength);
        return DashboardPeriodRange(
            fromDate: jalaliToString(start), toDate: jalaliToString(end), label: kDashboardPeriodLabels[preset]!);

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

  static List<DashboardPeriodRange> monthlyBuckets(String fromDate, String toDate) {
    final start = parseJalaliString(fromDate)!;
    final end = parseJalaliString(toDate)!;
    final buckets = <DashboardPeriodRange>[];
    var cursor = Jalali(start.year, start.month, 1);
    while (cursor.year < end.year || (cursor.year == end.year && cursor.month <= end.month)) {
      final monthEnd = Jalali(cursor.year, cursor.month, cursor.monthLength);
      buckets.add(DashboardPeriodRange(
        fromDate: jalaliToString(cursor),
        toDate: jalaliToString(monthEnd),
        label: '${_monthNames[cursor.month - 1]} ${cursor.year}',
      ));
      cursor = cursor.month == 12 ? Jalali(cursor.year + 1, 1, 1) : Jalali(cursor.year, cursor.month + 1, 1);
    }
    return buckets;
  }
}
