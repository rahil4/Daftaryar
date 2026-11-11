import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'theme/app_theme.dart';
import 'screens/onboarding/app_root.dart';
import 'navigation.dart';

void main() {
  runApp(const DaftaryarApp());
}

class DaftaryarApp extends StatelessWidget {
  const DaftaryarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'دفتریار',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.theme,
      locale: const Locale('fa', 'IR'),
      supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        // اندازه فونت سیستم فقط در یک بازه محدود اثر می‌کند: کارت‌های آماری
        // و جدول‌های برنامه ابعاد ثابت دارند و با فونت خیلی بزرگ سیستم، متن
        // از کادر بیرون می‌زد یا بریده می‌شد.
        return MediaQuery.withClampedTextScaling(
          minScaleFactor: 0.9,
          maxScaleFactor: 1.2,
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
      home: const AppRoot(),
    );
  }
}
