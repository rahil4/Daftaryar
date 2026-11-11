import 'package:flutter/material.dart';

/// پالت رنگی یکپارچه برنامه — تم تیره، مینیمال و واضح با لهجه برند برنزی/طلایی
class AppColors {
  static const background = Color(0xFF0F1115); // پس‌زمینه اصلی صفحات (تقریباً مشکی)
  static const surface = Color(0xFF1A1D23); // کارت‌ها و نوار بالا/پایین
  static const surfaceAlt = Color(0xFF23262D); // فیلدهای ورودی و کارت‌های ثانویه
  static const gridLine = Color(0xFF2A2E37); // حاشیه/جداکننده ملایم برای وضوح در تم تیره

  static const brass = Color(0xFFC9A227); // رنگ برند دفتریار — تنها لهجه رنگی اصلی
  static const brassLight = Color(0xFFE0C05C);

  static const lineStrong = Color(0xFF3A3F4B); // جداکننده پررنگ‌تر (خط پایه نمودار، سطر جمع)

  static const textPrimary = Color(0xFFF1F5F9);
  // کمی روشن‌تر از قبل (‎#8B93A1‎) تا برچسب‌های ریز ۱۱ پیکسلی روی سطح کارت هم
  // کنتراست کافی داشته باشند.
  static const textSecondary = Color(0xFF9AA3B2);

  static const positive = Color(0xFF22C55E); // سبز — دریافت/سود
  static const negative = Color(0xFFEF4444); // قرمز — پرداخت/زیان
  static const info = Color(0xFF3B82F6); // آبی — برای شاخص‌های خنثی مثل خالص ارزش
  static const teal = Color(0xFF14B8A6); // فیروزه‌ای — برای شاخص‌های ثانویه مثل حقوق سهام

  // رنگ سری‌های نمودار. برنز برند برای میله نمودار روی زمینه تیره زیادی روشن
  // است، پس یک پله تیره‌تر استفاده می‌شود؛ جفت برنزی/آبی برای کاربر کوررنگ
  // هم از هم قابل تشخیص است (سبز/قرمز نیست).
  static const chartIncome = Color(0xFFB08A1E);
  static const chartExpense = Color(0xFF5B8DEF);
  // پله‌های تک‌رنگ برنزی برای مقادیر ترتیبی (کم ← زیاد)
  static const rampLow = Color(0xFF7D6718);
  static const rampMid = Color(0xFFB08A1E);
  static const rampHigh = Color(0xFFE0C05C);
  // وضعیت «بحرانی» در نمودارها (مثل سهم پروژه‌های زیان‌ده)؛ از قرمز عمومی
  // برنامه کم‌رنگ‌تر است تا کنار پله‌های برنزی روی زمینه تیره چشم را نزند.
  static const statusCritical = Color(0xFFD03B3B);
}

/// نام خانواده فونت محلی که در assets/fonts باندل شده (بدون نیاز به اینترنت)
const String kAppFontFamily = 'Vazirmatn';

/// مقیاس تایپوگرافی مشترک - چند سایز/وزن نام‌گذاری‌شده به‌جای مقادیر دستی
/// پراکنده (در حال حاضر نزدیک به ۱۸ مقدار متفاوت fontSize در کل برنامه، از
/// ۸.۵ تا ۲۲، بدون هیچ الگوی مشترک). این کلاس فقط پایه را اضافه می‌کند؛
/// جایگزینی تدریجی مقادیر دستی موجود با این‌ها یک گام جداست تا ریسک تغییر
/// بصری ناخواسته در صفحاتی که در این محیط قابل تست بصری نیستند، به یک‌باره
/// به کل برنامه تحمیل نشود.
class AppTextStyles {
  static const caption =
      TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary);
  static const label = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600);
  static const body = TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500);
  static const sectionTitle = TextStyle(fontSize: 15, fontWeight: FontWeight.w800);
  static const pageHeading = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);

  /// عدد اصلی هر صفحه (موجودی، مانده طلب، سود ناخالص) - فقط یکی در هر صفحه.
  static const heroNumber = TextStyle(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    height: 1.25,
    color: AppColors.brassLight,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const rowTitle = TextStyle(fontSize: 13, fontWeight: FontWeight.w600);
  static const rowAmount = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
  );
  static const blockHeading = TextStyle(fontSize: 14, fontWeight: FontWeight.w800);
}

class AppTheme {
  static ThemeData get theme {
    const fontFamily = kAppFontFamily;
    final baseText = ThemeData.dark().textTheme.apply(
          fontFamily: fontFamily,
          bodyColor: AppColors.textPrimary,
          displayColor: AppColors.textPrimary,
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: fontFamily,
      textTheme: baseText,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brass,
        secondary: AppColors.brassLight,
        surface: AppColors.surface,
        error: AppColors.negative,
        onPrimary: Color(0xFF15100A),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      // کارت‌های سراسر برنامه: تخت و واضح با حاشیه ملایم (سایه در تم تیره کم‌اثر است)
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.gridLine),
        ),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gridLine),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.gridLine),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brass, width: 1.6),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      // دکمه اصلی: پرکاربردترین اکشن‌ها (ذخیره، ثبت) — پس‌زمینه برنزی با متن تیره پرکنتراست
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brass,
          foregroundColor: const Color(0xFF15100A),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      // دکمه فرعی: اکشن‌های کم‌اهمیت‌تر — فقط حاشیه، بدون پرکردن پس‌زمینه
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brass,
          side: const BorderSide(color: AppColors.brass),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.brass),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brass,
        foregroundColor: Color(0xFF15100A),
        elevation: 2,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.gridLine, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        labelStyle: const TextStyle(color: AppColors.textPrimary),
        side: const BorderSide(color: AppColors.gridLine),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.brass,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.brass,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.brass,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceAlt,
        contentTextStyle: const TextStyle(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.gridLine),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.brass,
        textColor: AppColors.textPrimary,
      ),
      iconTheme: const IconThemeData(color: AppColors.textSecondary),
    );
  }
}

/// پس‌زمینه استاندارد صفحات برنامه - یک الگوی گرید مهندسی ظریف (شبیه کاغذ
/// میلی‌متری نقشه‌برداری) که با رنگ برند (برنز) و اپاسیتی بسیار کم رسم
/// می‌شود؛ هویت بصری «نقشه‌برداری» را به‌طور واقعی (نه فقط در نام کلاس) به
/// همه صفحات می‌دهد.
class BlueprintGridBackground extends StatelessWidget {
  final Widget child;
  const BlueprintGridBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _BlueprintGridPainter())),
          child,
        ],
      ),
    );
  }
}

class _BlueprintGridPainter extends CustomPainter {
  static const double _cell = 22;

  @override
  void paint(Canvas canvas, Size size) {
    final thin = Paint()
      ..color = AppColors.brass.withValues(alpha: 0.05)
      ..strokeWidth = 0.6;
    final thick = Paint()
      ..color = AppColors.brass.withValues(alpha: 0.09)
      ..strokeWidth = 0.8;

    var i = 0;
    for (double x = 0; x <= size.width; x += _cell, i++) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 5 == 0 ? thick : thin);
    }
    i = 0;
    for (double y = 0; y <= size.height; y += _cell, i++) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), i % 5 == 0 ? thick : thin);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
