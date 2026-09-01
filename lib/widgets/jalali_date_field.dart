import 'package:flutter/material.dart';
import 'package:shamsi_date/shamsi_date.dart';
import '../theme/app_theme.dart';
import '../utils/formatters.dart';

class JalaliDateField extends StatelessWidget {
  final String label;
  final String value; // yyyy/mm/dd
  final ValueChanged<String> onChanged;

  const JalaliDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  Future<void> _pick(BuildContext context) async {
    final current = parseJalaliString(value) ?? Jalali.now();
    final result = await showModalBottomSheet<Jalali>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _JalaliPickerSheet(initial: current),
    );
    if (result != null) {
      onChanged(jalaliToString(result));
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.brass),
        ),
        child: Text(
          value.isEmpty ? 'انتخاب تاریخ' : formatJalaliLong(value),
          style: const TextStyle(color: AppColors.textPrimary),
        ),
      ),
    );
  }
}

class _JalaliPickerSheet extends StatefulWidget {
  final Jalali initial;
  const _JalaliPickerSheet({required this.initial});

  @override
  State<_JalaliPickerSheet> createState() => _JalaliPickerSheetState();
}

class _JalaliPickerSheetState extends State<_JalaliPickerSheet> {
  late int year = widget.initial.year;
  late int month = widget.initial.month;
  late int day = widget.initial.day;

  @override
  Widget build(BuildContext context) {
    final years = List.generate(20, (i) => Jalali.now().year - 10 + i);
    final daysInMonth = Jalali(year, month, 1).monthLength;
    if (day > daysInMonth) day = daysInMonth;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('انتخاب تاریخ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _dropdown(
                    value: day,
                    items: List.generate(daysInMonth, (i) => i + 1),
                    onChanged: (v) => setState(() => day = v),
                    label: 'روز',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _dropdown(
                    value: month,
                    items: List.generate(12, (i) => i + 1),
                    onChanged: (v) => setState(() => month = v),
                    label: 'ماه',
                    display: (m) => jalaliMonthName(m),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _dropdown(
                    value: year,
                    items: years,
                    onChanged: (v) => setState(() => year = v),
                    label: 'سال',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, Jalali(year, month, day)),
                child: const Text('تأیید'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dropdown({
    required int value,
    required List<int> items,
    required ValueChanged<int> onChanged,
    required String label,
    String Function(int)? display,
  }) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(display != null ? display(e) : pn(e))))
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}
