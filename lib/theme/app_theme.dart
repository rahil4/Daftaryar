import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// پالت رنگی یکپارچه برنامه — طراحی روشن، مینیمال و مدرن با لهجه برند برنزی/طلایی
class AppColors {
  static const background = Color(0xFFF5F7FA); // پس‌زمینه اصلی صفحات
  static const surface = Colors.white; // کارت‌ها و نوار بالا
  static const surfaceAlt = Color(0xFFF1F5F9); // فیلدهای ورودی و کارت‌های ثانویه
  static const gridLine = Color(0xFFE2E8F0); // حاشیه/جداکننده بسیار ملایم

  static const brass = Color(0xFFC9A227); // رنگ برند دفتریار
  static const brassLight = Color(0xFFE0C05C);

  static const textPrimary = Color(0xFF1E293B);
  static const textSecondary = Color(0xFF94A3B8);

  static const positive = Color(0xFF16A34A); // سبز — دریافت/سود
  static const negative = Color(0xFFDC2626); // قرمز — پرداخت/زیان

  // پس‌زمینه‌های پاستلی برای آیکون‌های کارت (سبک fintech مدرن)
  static const pastelGreenBg = Color(0xFFDCFCE7);
  static const pastelRedBg = Color(0xFFFEE2E2);
  static const pastelBlueBg = Color(0xFFDBEAFE);
  static const pastelBlueFg = Color(0xFF2563EB);
  static const pastelTealBg = Color(0xFFCCFBF1);
  static const pastelTealFg = Color(0xFF0D9488);
  static const pastelAmberBg = Color(0xFFFEF3C7);
}

class AppTheme {
  static ThemeData get theme {
    final fontFamily = GoogleFonts.vazirmatn().fontFamily;
    final baseText = GoogleFonts.vazirmatnTextTheme(ThemeData.light().textTheme).apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: fontFamily,
      textTheme: baseText,
      colorScheme: const ColorScheme.light(
        primary: AppColors.brass,
        secondary: AppColors.brassLight,
        surface: AppColors.surface,
        error: AppColors.negative,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: Colors.black.withOpacity(0.06),
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: fontFamily,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      // کارت‌های سراسر برنامه: گوشه گرد ۲۰ و سایه بسیار نرم (بدون حاشیه خط)
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 3,
        shadowColor: Colors.black.withOpacity(0.06),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.brass, width: 1.6),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brass,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.brass,
          side: const BorderSide(color: AppColors.brass),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppColors.brass),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.brass,
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      dividerTheme: const DividerThemeData(color: AppColors.gridLine, thickness: 1),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceAlt,
        labelStyle: const TextStyle(color: AppColors.textPrimary),
        side: BorderSide.none,
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
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.brass,
        textColor: AppColors.textPrimary,
      ),
    );
  }
}

/// پس‌زمینه استاندارد صفحات برنامه — رنگ ملایم یکدست، بدون گرافیک اضافه
class BlueprintGridBackground extends StatelessWidget {
  final Widget child;
  const BlueprintGridBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(color: AppColors.background, child: child);
  }
}
