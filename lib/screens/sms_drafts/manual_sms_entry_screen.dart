import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../models/sms_draft.dart';
import '../../services/bank_sms_parser.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import 'sms_draft_review_screen.dart';

/// افزودن دستی پیامک بانکی: چسباندن متن پیامک و بررسی نتیجه تشخیص —
/// هم برای عیب‌یابی شنود خودکار، هم به‌عنوان راه پشتیبان همیشگی
class ManualSmsEntryScreen extends StatefulWidget {
  const ManualSmsEntryScreen({super.key});

  @override
  State<ManualSmsEntryScreen> createState() => _ManualSmsEntryScreenState();
}

class _ManualSmsEntryScreenState extends State<ManualSmsEntryScreen> {
  final _controller = TextEditingController();
  BankSmsParseResult? _result;
  bool _checked = false;

  void _analyze() {
    final result = parseBankSms(_controller.text);
    setState(() {
      _result = result;
      _checked = true;
    });
  }

  Future<void> _createDraft() async {
    if (_result == null) return;
    final draft = SmsDraftModel(
      rawBody: _controller.text,
      sender: 'دستی',
      amount: _result!.amount,
      type: _result!.type,
      date: todayJalaliString(),
      createdAt: todayJalaliString(),
    );
    final id = await DatabaseHelper.instance.insertSmsDraft(draft);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SmsDraftReviewScreen(
          draft: SmsDraftModel(
            id: id,
            rawBody: draft.rawBody,
            sender: draft.sender,
            amount: draft.amount,
            type: draft.type,
            date: draft.date,
            createdAt: draft.createdAt,
          ),
        ),
      ),
    );
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('افزودن دستی پیامک بانکی')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'متن پیامک بانک را کامل کپی و اینجا بچسبانید. برنامه سعی می‌کند '
            'مبلغ و نوع تراکنش را تشخیص دهد؛ اگر شنود خودکار پیامک روی گوشی شما '
            'کار نمی‌کند، از همین راه می‌توانید سند بسازید.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.7),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'متن پیامک',
              alignLabelWithHint: true,
            ),
            onChanged: (_) => setState(() => _checked = false),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _controller.text.trim().isEmpty ? null : _analyze,
            child: const Text('بررسی متن'),
          ),
          if (_checked) ...[
            const SizedBox(height: 20),
            if (_result == null)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.negative.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.negative),
                ),
                child: const Text(
                  'تراکنش بانکی در این متن تشخیص داده نشد. یا الگوی پیامک با کلیدواژه‌های '
                  'شناخته‌شده (واریز/برداشت/خرید) مطابقت ندارد، یا هیچ شاهد بانکی '
                  '(مانده/حساب/کارت/ریال/تومان) در متن نیست.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.negative, height: 1.7),
                ),
              )
            else ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.positive.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.positive),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('نوع: ${_result!.type}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('مبلغ تشخیص‌داده‌شده: ${formatMoney(_result!.amount)}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _createDraft,
                child: const Text('ساخت پیش‌نویس از این متن'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
