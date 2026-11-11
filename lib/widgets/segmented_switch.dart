import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// سوییچ چندحالته هم‌ظاهر با انتخاب‌گر بازه (قاب مستطیلی، بخش انتخاب‌شده
/// با زمینه برنزی کم‌رنگ) - برای جابه‌جایی بین چند نما در یک صفحه، مثل
/// «دفترکل / چارت حساب‌ها».
class SegmentedSwitch<T> extends StatelessWidget {
  final Map<T, String> options;
  final T selected;
  final ValueChanged<T> onChanged;

  const SegmentedSwitch({super.key, required this.options, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.gridLine),
      ),
      child: Row(
        children: [
          for (final entry in options.entries)
            Expanded(
              child: Semantics(
                button: true,
                selected: entry.key == selected,
                child: Material(
                  color: entry.key == selected ? AppColors.brass.withValues(alpha: 0.18) : Colors.transparent,
                  child: InkWell(
                    onTap: () => onChanged(entry.key),
                    child: SizedBox(
                      height: 44,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: entry.key == selected ? FontWeight.w700 : FontWeight.w400,
                              color: entry.key == selected ? AppColors.brassLight : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
