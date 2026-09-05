import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';

/// صفحه تأیید سلامت پشتیبان.
///
/// چرا لازم است: کد بازیابی پشتیبان تست واحد دارد، ولی هیچ‌کس تا امروز
/// عملاً یک پشتیبان نگرفته، برنامه را پاک کرده، و دوباره بازیابی نکرده
/// است. تا آن آزمون واقعی انجام نشود، داده کاربر عملاً گروگان یک دستگاه
/// است. این صفحه آن آزمون را ممکن و قابل‌اتکا می‌کند: «اثر انگشت داده»
/// را نشان می‌دهد تا کاربر بتواند پیش و پس از بازیابی، عدد به عدد مقایسه
/// کند - نه اینکه به «به‌نظر درست می‌آید» تکیه کند.
class BackupVerifyScreen extends StatefulWidget {
  const BackupVerifyScreen({super.key});

  @override
  State<BackupVerifyScreen> createState() => _BackupVerifyScreenState();
}

class _BackupVerifyScreenState extends State<BackupVerifyScreen> {
  final _db = DatabaseHelper.instance;
  Map<String, num>? _fingerprint;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fp = await _db.dataFingerprint();
      if (mounted) {
        setState(() {
          _fingerprint = fp;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceAll('Exception: ', '');
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('تأیید سلامت پشتیبان'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'به‌روزرسانی', onPressed: _load),
        ],
      ),
      body: BlueprintGridBackground(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(_error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.negative)),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const _GuideCard(),
                      const SizedBox(height: 16),
                      const Text('اثر انگشت داده‌های فعلی',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                      const SizedBox(height: 4),
                      const Text(
                        'این اعداد را پیش از بازیابی یادداشت کنید و پس از آن دوباره اینجا مقایسه کنید.'
                        ' اگر همه یکسان بودند، بازیابی کامل و درست بوده است.',
                        style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Column(
                            children: _fingerprint!.entries
                                .map((e) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 5),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(e.key, style: const TextStyle(fontSize: 12.5)),
                                          Text(
                                            e.key.startsWith('جمع')
                                                ? formatMoney(e.value, withSuffix: false)
                                                : pn(e.value),
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.brass),
                                          ),
                                        ],
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  const _GuideCard();

  @override
  Widget build(BuildContext context) {
    const steps = [
      'یک فایل پشتیبان تهیه کنید و آن را جایی امن (خارج از گوشی) ذخیره کنید.',
      'اعداد «اثر انگشت داده» را در پایین همین صفحه یادداشت یا از آن عکس بگیرید.',
      'روی یک دستگاه دیگر (یا پس از حذف و نصب دوباره برنامه)، فایل پشتیبان را بازیابی کنید.',
      'دوباره به همین صفحه بیایید و اعداد را با یادداشتتان مقایسه کنید.',
      'اگر همه اعداد دقیقاً یکسان بودند، چرخه پشتیبان‌گیری شما قابل‌اتکاست.',
    ];

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.brass, width: 0.8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.verified_outlined, color: AppColors.brass, size: 18),
                const SizedBox(width: 7),
                Text('آزمون چرخه پشتیبان‌گیری',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800, color: AppColors.brass)),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'پشتیبانی که هرگز بازیابی نشده، پشتیبان نیست. این آزمون را حداقل یک‌بار انجام دهید:',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 10),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.brass.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(pn(i + 1),
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.brass)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(steps[i], style: const TextStyle(fontSize: 12.5))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
