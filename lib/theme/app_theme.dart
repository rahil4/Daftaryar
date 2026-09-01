import 'package:flutter/material.dart';

/// پالت رنگی یکپارچه برنامه — تم تیره، مینیمال و واضح با لهجه برند برنزی/طلایی
class AppColors {
  static const background = Color(0xFF0F1115); // پس‌زمینه اصلی صفحات (تقریباً مشکی)
  static const surface = Color(0xFF1A1D23); // کارت‌ها و نوار بالا/پایین
  static const surfaceAlt = Color(0xFF23262D); // فیلدهای ورودی و کارت‌های ثانویه
  static const gridLine = Color(0xFF2A2E37); // حاشیه/جداکننده ملایم برای وضوح در تم تیره

  static const brass = Color(0xFFC9A227); // رنگ برند دفتریار — تنها لهجه رنگی اصلی
  static const brassLight = Color(0xFFE0C05C);

  static const textPrimary = Color(0xFFF1F5F9);
  static const textSecondary = Color(0xFF8B93A1);

  static const positive = Color(0xFF22C55E); // سبز — دریافت/سود
  static const negative = Color(0xFFEF4444); // قرمز — پرداخت/زیان
  static const info = Color(0xFF3B82F6); // آبی — برای شاخص‌های خنثی مثل خالص ارزش
  static const teal = Color(0xFF14B8A6); // فیروزه‌ای — برای شاخص‌های ثانویه مثل حقوق سهام
}

/// نام خانواده فونت محلی که در assets/fonts باندل شده (بدون نیاز به اینترنت)
const String kAppFontFamily = 'Vazirmatn';

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

/// پس‌زمینه استاندارد صفحات برنامه
class BlueprintGridBackground extends StatelessWidget {
  final Widget child;
  const BlueprintGridBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(color: AppColors.background, child: child);
  }
}
