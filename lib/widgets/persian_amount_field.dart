import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/formatters.dart';

/// در حین تایپ، عدد را با ارقام فارسی و جداکننده سه‌رقمی («٬») فرمت می‌کند
class PersianAmountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final parsed = parsePersianAmount(newValue.text);
    if (parsed == null) {
      return const TextEditingValue(text: '');
    }
    final formatted = formatMoney(parsed, withSuffix: false);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// فیلد استاندارد ورود مبلغ در سراسر برنامه: ارقام فارسی + جداکننده سه‌رقمی
/// حین تایپ، با فرمت خودکار. عدد خام را با parsePersianAmount(controller.text) بخوانید.
class PersianAmountField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onChanged;
  final bool isDense;

  const PersianAmountField({
    super.key,
    required this.controller,
    required this.label,
    this.validator,
    this.onChanged,
    this.isDense = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label, isDense: isDense),
      keyboardType: TextInputType.number,
      inputFormatters: [PersianAmountInputFormatter()],
      validator: validator,
      onChanged: onChanged,
    );
  }
}
