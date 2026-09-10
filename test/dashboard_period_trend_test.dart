// تست‌های اصلاح نمودار روند داشبورد: نمودار نباید تا روزهای هنوز‌نیامده
// کشیده شود، و تفکیک باید متناسب با طول واقعی بازه (روزانه/هفتگی/ماهانه)
// خودکار انتخاب شود - نه همیشه روزانه تا ۶۲ روز که ستون‌های له‌شده تولید می‌کرد.
import 'package:flutter_test/flutter_test.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'package:daftaryar/utils/dashboard_period.dart';
import 'package:daftaryar/utils/formatters.dart';

void main() {
  group('trendBuckets — محدود کردن به امروز', () {
    test('بازه «این ماه» که تا آخر ماه تقویمی می‌رود، در نمودار فقط تا امروز کشیده می‌شود', () {
      final today = Jalali(1405, 6, 10);
      // «این ماه» یعنی از ۱ شهریور تا ۳۱ شهریور - ۲۱ روز هنوز نیامده
      final buckets = DashboardPeriodResolver.trendBuckets('1405/06/01', '1405/06/31', today: today);
      final lastBucket = buckets.last;
      expect(lastBucket.toDate, '1405/06/10', reason: 'نباید از امروز جلوتر برود');
    });

    test('بازه کاملاً گذشته (مثل «ماه قبل») دست‌نخورده باقی می‌ماند', () {
      final today = Jalali(1405, 6, 10);
      final buckets = DashboardPeriodResolver.trendBuckets('1405/05/01', '1405/05/31', today: today);
      expect(buckets.last.toDate, '1405/05/31', reason: 'بازه گذشته نباید کوتاه شود');
    });
  });

  group('trendBuckets — انتخاب خودکار تفکیک بر مبنای طول بازه', () {
    test('بازه تک‌روزه به ۱۴ روز اخیر برمی‌گردد', () {
      final today = Jalali(1405, 6, 10);
      final buckets = DashboardPeriodResolver.trendBuckets('1405/06/10', '1405/06/10', today: today);
      expect(buckets.length, 14);
    });

    test('بازه ≤۱۴ روزه روزانه است', () {
      final today = Jalali(1405, 6, 20);
      final buckets = DashboardPeriodResolver.trendBuckets('1405/06/01', '1405/06/14', today: today);
      expect(buckets.length, 14);
      expect(buckets.first.fromDate, buckets.first.toDate, reason: 'هر Bucket باید تک‌روزه باشد');
    });

    test('بازه بین ۱۵ تا ۶۲ روز هفتگی است (نه روزانه له‌شده)', () {
      final today = Jalali(1405, 7, 1);
      // «این ماه» شهریور: ۳۱ روز - باید هفتگی شود، نه ۳۱ ستون روزانه
      final buckets = DashboardPeriodResolver.trendBuckets('1405/06/01', '1405/06/31', today: today);
      expect(buckets.length, lessThan(10), reason: 'هفتگی باید حدود ۵ Bucket بدهد، نه ۳۱');
      expect(buckets.first.fromDate, '1405/06/01');
      expect(buckets.last.toDate, '1405/06/31');
      // هیچ Bucket‌ای نباید بیش از ۷ روز باشد
      for (final b in buckets) {
        final start = parseJalaliString(b.fromDate)!;
        final end = parseJalaliString(b.toDate)!;
        expect(end.julianDayNumber - start.julianDayNumber + 1, lessThanOrEqualTo(7));
      }
    });

    test('بازه بیش از ۶۲ روز ماهانه است', () {
      final today = Jalali(1405, 12, 1);
      final buckets = DashboardPeriodResolver.trendBuckets('1405/01/01', '1405/12/29', today: today);
      expect(buckets.length, 12);
    });
  });

  group('weeklyBuckets — تکه‌کردن ۷ روزه با Intersection دقیق', () {
    test('بازه ۱۰ روزه به دو Bucket (۷ روز + ۳ روز باقی‌مانده) تقسیم می‌شود', () {
      final buckets = DashboardPeriodResolver.weeklyBuckets('1405/06/01', '1405/06/10');
      expect(buckets.length, 2);
      expect(buckets[0].fromDate, '1405/06/01');
      expect(buckets[0].toDate, '1405/06/07');
      expect(buckets[1].fromDate, '1405/06/08');
      expect(buckets[1].toDate, '1405/06/10', reason: 'آخرین Bucket باید دقیقاً در toDate تمام شود، نه فراتر برود');
    });

    test('بازه دقیقاً ۷ روزه یک Bucket تک می‌دهد', () {
      final buckets = DashboardPeriodResolver.weeklyBuckets('1405/06/01', '1405/06/07');
      expect(buckets.length, 1);
      expect(buckets.first.fromDate, '1405/06/01');
      expect(buckets.first.toDate, '1405/06/07');
    });
  });
}
