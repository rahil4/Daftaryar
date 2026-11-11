import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';

import '../theme/app_theme.dart';
import '../utils/dashboard_period.dart';
import '../utils/formatters.dart';
import 'jalali_date_field.dart';

/// بازه پیش‌فرض «بازه سفارشی»: از اول ماه جاری تا امروز - تا انتخاب این
/// گزینه بلافاصله یک بازه معنادار نشان دهد و کاربر فقط در صورت نیاز تاریخ‌ها
/// را عوض کند.
({String from, String to}) defaultCustomPeriodRange() {
  final now = Jalali.now();
  return (from: jalaliToString(Jalali(now.year, now.month, 1)), to: jalaliToString(now));
}

/// انتخاب‌گر بازه: چهار بازه پرکاربرد همیشه روی صفحه (هفته/ماه/فصل/سال) و
/// بقیه (امروز، دوره‌های قبل، بازه سفارشی) پشت دکمه تقویم. جایگزین ردیف ۹
/// چیپ اسکرولی قبلی.
class PeriodSegmentedControl extends StatelessWidget {
  final DashboardPeriodPreset selected;
  final ValueChanged<DashboardPeriodPreset> onChanged;
  final String customFrom;
  final String customTo;
  final void Function(String from, String to) onCustomRangeChanged;

  const PeriodSegmentedControl({
    super.key,
    required this.selected,
    required this.onChanged,
    required this.customFrom,
    required this.customTo,
    required this.onCustomRangeChanged,
  });

  static const Map<DashboardPeriodPreset, String> _mainLabels = {
    DashboardPeriodPreset.thisWeek: 'هفته',
    DashboardPeriodPreset.thisMonth: 'ماه',
    DashboardPeriodPreset.thisQuarter: 'فصل',
    DashboardPeriodPreset.thisYear: 'سال',
  };

  static const List<DashboardPeriodPreset> _otherPresets = [
    DashboardPeriodPreset.today,
    DashboardPeriodPreset.lastMonth,
    DashboardPeriodPreset.lastQuarter,
    DashboardPeriodPreset.lastYear,
    DashboardPeriodPreset.custom,
  ];

  bool get _otherSelected => !_mainLabels.containsKey(selected);

  Future<void> _openOtherPresets(BuildContext context) async {
    final picked = await showModalBottomSheet<DashboardPeriodPreset>(
      context: context,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text('بازه‌های دیگر', style: AppTextStyles.blockHeading),
              ),
            ),
            for (final preset in _otherPresets)
              ListTile(
                title: Text(kDashboardPeriodLabels[preset]!),
                trailing: preset == selected ? const Icon(Icons.check, color: AppColors.brass) : null,
                onTap: () => Navigator.pop(ctx, preset),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.gridLine),
          ),
          child: Row(
            children: [
              for (final entry in _mainLabels.entries)
                Expanded(
                  child: _Segment(
                    selected: entry.key == selected,
                    onTap: () => onChanged(entry.key),
                    child: Text(entry.value),
                  ),
                ),
              Container(width: 1, height: 44, color: AppColors.gridLine),
              Expanded(
                child: _Segment(
                  selected: _otherSelected,
                  onTap: () => _openOtherPresets(context),
                  semanticLabel: 'بازه‌های دیگر و بازه سفارشی',
                  child: const Icon(Icons.calendar_today_outlined, size: 18),
                ),
              ),
            ],
          ),
        ),
        if (_otherSelected && selected != DashboardPeriodPreset.custom)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('بازه: ${kDashboardPeriodLabels[selected]!}', style: AppTextStyles.caption),
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

class _Segment extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final Widget child;
  final String? semanticLabel;

  const _Segment({required this.selected, required this.onTap, required this.child, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.brassLight : AppColors.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel,
      child: Material(
        color: selected ? AppColors.brass.withValues(alpha: 0.18) : Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 44,
            child: Center(
              child: IconTheme(
                data: IconThemeData(color: color),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
