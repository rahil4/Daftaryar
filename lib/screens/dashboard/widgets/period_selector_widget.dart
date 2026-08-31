import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/dashboard_period.dart';

class PeriodSelectorWidget extends StatelessWidget {
  final DashboardPeriodPreset selected;
  final ValueChanged<DashboardPeriodPreset> onChanged;

  const PeriodSelectorWidget({super.key, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
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
    );
  }
}
