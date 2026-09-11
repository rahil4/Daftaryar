// تست‌های محور افقی نمودار روند داشبورد: سطح تفکیک (هفته/ماه/فصل/سال) باید
// دقیقاً با واحد تقویمی بازه انتخابی هم‌راستا باشد - نه یک تقسیم دلخواه بر
// مبنای طول خام روز؛ و بازه سفارشی هم بر همین منطق (بر اساس طول واقعی‌اش)
// یکی از این ۴ سطح را انتخاب می‌کند.
import 'package:flutter_test/flutter_test.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'package:daftaryar/utils/dashboard_period.dart';
import 'package:daftaryar/utils/formatters.dart';

void main() {
  group('resolveGranularity — تناظر مستقیم Preset با سطح تفکیک', () {
    test('امروز و این‌هفته → هفته', () {
      expect(
        DashboardPeriodResolver.resolveGranularity(DashboardPeriodPreset.today, '1405/06/10', '1405/06/10'),
        ChartGranularity.week,
      );
      expect(
        DashboardPeriodResolver.resolveGranularity(DashboardPeriodPreset.thisWeek, '1405/06/07', '1405/06/13'),
        ChartGranularity.week,
      );
    });

    test('این‌ماه و ماه‌قبل → ماه', () {
      expect(
        DashboardPeriodResolver.resolveGranularity(DashboardPeriodPreset.thisMonth, '1405/06/01', '1405/06/31'),
        ChartGranularity.month,
      );
      expect(
        DashboardPeriodResolver.resolveGranularity(DashboardPeriodPreset.lastMonth, '1405/05/01', '1405/05/31'),
        ChartGranularity.month,
      );
    });

    test('این‌فصل و فصل‌قبل → فصل', () {
      expect(
        DashboardPeriodResolver.resolveGranularity(
            DashboardPeriodPreset.thisQuarter, '1405/04/01', '1405/06/31'),
        ChartGranularity.quarter,
      );
      expect(
        DashboardPeriodResolver.resolveGranularity(
            DashboardPeriodPreset.lastQuarter, '1405/01/01', '1405/03/31'),
        ChartGranularity.quarter,
      );
    });

    test('امسال و سال‌قبل → سال', () {
      expect(
        DashboardPeriodResolver.resolveGranularity(DashboardPeriodPreset.thisYear, '1405/01/01', '1405/12/29'),
        ChartGranularity.year,
      );
      expect(
        DashboardPeriodResolver.resolveGranularity(DashboardPeriodPreset.lastYear, '1404/01/01', '1404/12/29'),
        ChartGranularity.year,
      );
    });

    test('بازه سفارشی بر اساس طول واقعی بازه (فشردگی/گستردگی) تعیین می‌شود', () {
      ChartGranularity ofSpan(int days) {
        final start = Jalali(1405, 1, 1);
        final end = start.addDays(days - 1);
        return DashboardPeriodResolver.resolveGranularity(
            DashboardPeriodPreset.custom, jalaliToString(start), jalaliToString(end));
      }

      expect(ofSpan(1), ChartGranularity.week);
      expect(ofSpan(9), ChartGranularity.week);
      expect(ofSpan(10), ChartGranularity.month);
      expect(ofSpan(35), ChartGranularity.month);
      expect(ofSpan(36), ChartGranularity.quarter);
      expect(ofSpan(100), ChartGranularity.quarter);
      expect(ofSpan(101), ChartGranularity.year);
    });
  });

  group('buildAxisPlan — سطح هفته', () {
    test('۷ ستون شنبه تا جمعه به ترتیب زمانی (تاریخی)، بدون چرخش‌شمار له‌شده', () {
      final ref = Jalali(1405, 6, 10);
      final plan = DashboardPeriodResolver.buildAxisPlan(
          DashboardPeriodPreset.today, jalaliToString(ref), jalaliToString(ref));
      final expectedWeek = jalaliWeekRange(ref);

      expect(plan.buckets.length, 7);
      expect(plan.rotateLabels, true, reason: 'در سطح هفته لیبل هر ستون باید ۹۰ درجه بچرخد');
      expect(plan.buckets.first.fromDate, jalaliToString(expectedWeek[0]), reason: 'اولین ستون باید شنبه هفته جاری باشد');
      expect(plan.buckets.last.fromDate, jalaliToString(expectedWeek[1]), reason: 'آخرین ستون باید جمعه هفته جاری باشد');
      // ترتیب Bucketها باید صعودی (تاریخی) باشد - قدیمی اول، جدید آخر؛
      // جهت چپ‌به‌راست خودِ ویجت نمودار مسئول برعکس‌کردن بصری است، نه اینجا.
      for (var i = 0; i < 6; i++) {
        final a = parseJalaliString(plan.buckets[i].fromDate)!;
        final b = parseJalaliString(plan.buckets[i + 1].fromDate)!;
        expect(b.julianDayNumber - a.julianDayNumber, 1);
      }
      // لیبل هر ستون فقط نام روز است، بدون تاریخ.
      for (final b in plan.buckets) {
        expect(b.label, isNot(contains('\n')));
        expect(RegExp(r'^[۰-۹0-9]').hasMatch(b.label), false, reason: 'لیبل هفته نباید با رقم شروع شود');
      }
    });

    test('این‌هفته و امروز روی یک هفته یکسان می‌افتند', () {
      final today = Jalali(1405, 6, 10);
      final weekRange = jalaliWeekRange(today);
      final planToday = DashboardPeriodResolver.buildAxisPlan(
          DashboardPeriodPreset.today, jalaliToString(today), jalaliToString(today));
      final planWeek = DashboardPeriodResolver.buildAxisPlan(
          DashboardPeriodPreset.thisWeek, jalaliToString(weekRange[0]), jalaliToString(weekRange[1]));
      expect(planToday.buckets.first.fromDate, planWeek.buckets.first.fromDate);
      expect(planToday.buckets.last.fromDate, planWeek.buckets.last.fromDate);
    });

    test('زیرنویس شامل شماره هفته و بازه تاریخ است', () {
      final ref = Jalali(1405, 6, 10);
      final plan = DashboardPeriodResolver.buildAxisPlan(
          DashboardPeriodPreset.today, jalaliToString(ref), jalaliToString(ref));
      expect(plan.caption, isNotNull);
      expect(plan.caption, contains('هفته'));
      expect(plan.caption, contains('|'));
    });

    test('هفته حاوی ۱ فروردین، «هفته ۱» است', () {
      final farvardinFirst = Jalali(1405, 1, 1);
      final plan = DashboardPeriodResolver.buildAxisPlan(DashboardPeriodPreset.today,
          jalaliToString(farvardinFirst), jalaliToString(farvardinFirst));
      expect(plan.caption, startsWith('هفته ۱ '));
    });

    test('هفته پنجم دقیقاً ۲۸ روز بعد از هفته اول شروع می‌شود', () {
      final farvardinFirst = Jalali(1405, 1, 1);
      final week1Start = jalaliWeekRange(farvardinFirst)[0];
      final week5Start = week1Start.addDays(28); // ۴ هفته کامل بعد از هفته ۱
      final plan = DashboardPeriodResolver.buildAxisPlan(
          DashboardPeriodPreset.today, jalaliToString(week5Start), jalaliToString(week5Start));
      expect(plan.caption, startsWith('هفته ۵ '));
    });
  });

  group('buildAxisPlan — سطح ماه', () {
    test('یک ستون به ازای هر روز ماه، لیبل فقط عدد روز', () {
      final plan =
          DashboardPeriodResolver.buildAxisPlan(DashboardPeriodPreset.thisMonth, '1405/06/01', '1405/06/31');
      expect(plan.buckets.length, 31);
      expect(plan.rotateLabels, false);
      expect(plan.caption, isNull);
      expect(plan.buckets.first.label, pn(1));
      expect(plan.buckets.last.label, pn(31));
      expect(plan.buckets[9].label, pn(10));
    });
  });

  group('buildAxisPlan — سطح فصل/سال', () {
    test('فصل: ۳ ستون، هر کدام یک ماه', () {
      final plan = DashboardPeriodResolver.buildAxisPlan(
          DashboardPeriodPreset.thisQuarter, '1405/04/01', '1405/06/31');
      expect(plan.buckets.length, 3);
      expect(plan.rotateLabels, false);
      expect(plan.caption, isNull);
      expect(plan.buckets.first.fromDate, '1405/04/01');
      expect(plan.buckets.last.toDate, '1405/06/31');
    });

    test('سال: ۱۲ ستون، هر کدام یک ماه', () {
      final plan =
          DashboardPeriodResolver.buildAxisPlan(DashboardPeriodPreset.thisYear, '1405/01/01', '1405/12/29');
      expect(plan.buckets.length, 12);
      expect(plan.rotateLabels, false);
      expect(plan.caption, isNull);
    });
  });
}
