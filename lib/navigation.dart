import 'package:flutter/material.dart';

/// کلید ناوبری سراسری — برای بازکردن صفحه از داخل کدهایی که به BuildContext
/// دسترسی مستقیم ندارند (مثل هندلر لمس نوتیفیکیشن)
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();
