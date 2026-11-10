import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/dashboard_period.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/jalali_date_field.dart';

/// بازه پیش‌فرض «بازه سفارشی»: از اول ماه جاری تا امروز - تا انتخاب این
/// گزینه بلافاصله یک بازه معنادار نشان دهد و کاربر فقط در صورت نیاز تاریخ‌ها
/// را عوض کند.
({String from, String to}) defaultCustomPeriodRange() {
  final now = Jalali.now();
  return (from: jalaliToString(Jalali(now.year, now.month, 1)), to: jalaliToString(now));
}

class PeriodSelectorWidget extends StatelessWidget {
  final DashboardPeriodPreset selected;
  final ValueChanged<DashboardPeriodPreset> onChanged;

  /// تاریخ‌های بازه سفارشی (شمسی yyyy/mm/dd). فقط وقتی «بازه سفارشی» انتخاب
  /// شده باشد، دو فیلد تاریخ زیر چیپ‌ها نمایش داده می‌شود.
  final String customFrom;
  final String customTo;
  final void Function(String from, String to) onCustomRangeChanged;

  const PeriodSelectorWidget({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.customFrom,
    required this.customTo,
    required this.onCustomRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: DashboardPeriodPreset.values.map((preset) {
              final isSelected = preset == selected;
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  label: Text(kDashboardPeriodLabels[preset]!),
                  selected: isSelected,
                  selectedColor: AppColors.brass.withValues(alpha: 0.25),
                  onSelected: (_) => onChanged(preset),
                ),
              );
            }).toList(),
          ),
        ),
        if (selected == DashboardPeriodPreset.custom) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: JalaliDateField(
                  label: 'از تاریخ',
                  value: customFrom,
                  // بازه وارونه (شروع بعد از پایان) معنا ندارد؛ سرِ دیگر بازه
                  // به همان تاریخ کشیده می‌شود.
                  onChanged: (v) => onCustomRangeChanged(v, v.compareTo(customTo) > 0 ? v : customTo),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: JalaliDateField(
                  label: 'تا تاریخ',
                  value: customTo,
                  onChanged: (v) => onCustomRangeChanged(v.compareTo(customFrom) < 0 ? v : customFrom, v),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
