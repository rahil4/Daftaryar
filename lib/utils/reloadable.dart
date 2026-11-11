import 'package:flutter/widgets.dart';

/// پیاده‌سازی این mixin روی State یک صفحه یعنی «وقتی این صفحه دوباره در
/// معرض دید کاربر قرار گرفت، دیتایش را از نو بارگذاری کن».
///
/// صفحات اصلی برنامه (داشبورد/حسابداری/پروژه‌ها/گزارش‌ها) داخل یک
/// IndexedStack در HomeShell نگه داشته می‌شوند تا وضعیت اسکرول/فیلتر هرکدام
/// هنگام سوییچ تب حفظ شود - اما همین یعنی initState هرکدام فقط یک‌بار در
/// طول عمر برنامه اجرا می‌شود؛ خودِ سوییچ تب باعث rebuild/initState دوباره
/// نمی‌شود. بدون این mixin، دیتای یک تب که پس از آخرین بازدیدش در تب دیگری
/// تغییر کرده (مثلاً یک سند جدید)، تا بازگشت از یک Push/Pop دیگر تازه
/// نمی‌شد.
mixin Reloadable<T extends StatefulWidget> on State<T> {
  Future<void> reload();
}

/// اگر currentState این GlobalKey پیاده‌ساز Reloadable باشد، reload را صدا
/// می‌زند؛ در غیر این صورت بی‌صدا نادیده می‌گیرد.
void triggerReload(GlobalKey key) {
  final state = key.currentState;
  if (state is Reloadable) {
    state.reload();
  }
}
