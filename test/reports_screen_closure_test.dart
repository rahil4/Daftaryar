// تست‌های مرحله «Reporting Layer Closure» (۲.۱). هدف این‌ها جلوگیری از
// بازگشت تکرار معنایی (Semantic Duplication) در reports_screen.dart است -
// نه تست رفتار Widget (که نیازمند هارنس کامل Flutter Widget Test با Mock
// کردن PDF/Excel/DatabaseHelper بود و از محدوده این مرحله بیرون است).
//
// دو نوع تست اینجاست:
// ۱. تست‌های مبتنی بر منبع (Source-Based) - تأیید می‌کنند خودِ کد فایل
//    دیگر فرمول تکراری ندارد و از منبع مرجع واحد استفاده می‌کند. این‌ها
//    دقیقاً از نوع «جلوگیری از بازگشت الگوی اشتباه در آینده» هستند.
// ۲. تست‌های واحد خالص برای منبع مرجع (FinancialPeriodComparison.compute)
//    که حالا reports_screen.dart هم به آن متکی است - تقویت پوشش مورد ۲۴.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:daftaryar/models/financial_reports.dart';

void main() {
  group('مورد A — Semantic Source Consistency (بررسی مبتنی بر منبع)', () {
    late String source;

    setUpAll(() {
      source = File('lib/screens/reports/reports_screen.dart').readAsStringSync();
    });

    test('_pctChange دیگر فرمول رشد را مستقیم بازتولید نمی‌کند، بلکه از'
        ' FinancialPeriodComparison.compute (منبع مرجع واحد) استفاده می‌کند', () {
      expect(source.contains('FinancialPeriodComparison.compute'), true,
          reason: 'باید از منبع مرجع واحد فرمول رشد استفاده کند');
      // الگوی قدیمی تکراری (بازسازی مستقیم فرمول به‌جای فراخوانی منبع مرجع)
      // دیگر نباید در تابع _pctChange وجود داشته باشد.
      expect(source.contains('((now - prev) / prev.abs())'), false,
          reason: 'فرمول رشد نباید دوباره این‌جا به‌صورت مستقل بازسازی شود');
    });

    test('reports_screen.dart نباید یک "collectionRate" عمومی و مبهم دوباره بسازد', () {
      // طبق قرارداد صریح مرحله ۲: periodReceiptToRevenueRatio و
      // periodArCollectionRate دو مفهوم متفاوت و صریح‌اند؛ این فایل اصلاً
      // این مدل‌ها را مصرف نمی‌کند (محاسبات محلی خودش را دارد که در همین
      // فایل مستند شده)، پس نباید هیچ‌جا رشته "collectionRate" (حروف کوچک،
      // به‌عنوان یک شناسه عمومی مبهم) در آن ظاهر شود.
      expect(source.contains('collectionRate'), false,
          reason: 'نباید یک متغیر/فیلد عمومی به نام collectionRate در این فایل بازسازی شود');
    });

    test('reports_screen.dart سال مالی را با تابع مرجع مشترک (currentFiscalYearRange)'
        ' محاسبه می‌کند، نه یک پیاده‌سازی مستقل جدید', () {
      expect(source.contains('currentFiscalYearRange('), true,
          reason: 'باید از همان تابع مرجعی استفاده کند که DashboardPeriodResolver هم از آن استفاده می‌کند');
    });

    test('Zero-vs-Null: هیچ fallback ساختگی (prev==0 ? 0 : ...) در محاسبه درصد باقی نمانده', () {
      expect(source.contains('== 0 ? 0 :'), false,
          reason: 'الگوی ممنوع مرحله ۲: تبدیل خاموش صفر/نامعلوم به مقدار ساختگی');
      expect(source.contains('== 0 ? now == 0 ? 0 : 100'), false);
    });
  });

  group('مورد B/E — Zero vs Null در منبع مرجع (Regression تقویتی مورد ۲۴)', () {
    test('previous = 0 → growthRate باید null باشد، نه Infinity یا عدد ساختگی', () {
      final c = FinancialPeriodComparison.compute(metricName: 'x', current: 50, previous: 0);
      expect(c.growthRate, isNull);
    });

    test('previous = 0 و current = 0 → همچنان null (نه صفر ساختگی)', () {
      final c = FinancialPeriodComparison.compute(metricName: 'x', current: 0, previous: 0);
      expect(c.growthRate, isNull);
    });

    test('previous منفی، current مثبت → علامت رشد معکوس نمی‌شود (Regression مورد ۲۴)', () {
      final c = FinancialPeriodComparison.compute(metricName: 'profit', current: 20, previous: -20);
      // (20 - (-20)) / abs(-20) * 100 = 40/20*100 = 200% (مثبت)
      expect(c.growthRate, 200.0);
    });

    test('previous مثبت عادی - فرمول استاندارد رشد', () {
      final c = FinancialPeriodComparison.compute(metricName: 'x', current: 120, previous: 100);
      expect(c.growthRate, 20.0);
    });
  });
}
