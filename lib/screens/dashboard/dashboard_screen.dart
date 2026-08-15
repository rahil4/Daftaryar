import 'package:flutter/material.dart';

import '../../db/database_helper.dart';
import '../../theme/app_theme.dart';
import '../../utils/formatters.dart';
import '../../widgets/quick_add_sheet.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/action_button.dart';
import '../settings/settings_screen.dart';

/// داشبورد اصلی دفتریار — طراحی روشن، مدرن و مینیمال
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _db = DatabaseHelper.instance;
  bool _loading = true;

  double _assets = 0;
  double _liabilities = 0;
  double _netWorth = 0;
  double _equity = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final summary = await _db.dashboardSummary();
    setState(() {
      _assets = summary['assetBalance']!;
      _liabilities = summary['liabilityBalance']!;
      _netWorth = summary['netWorth']!;
      _equity = summary['equityBalance']!;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _DashboardHeader(
                      onNotificationTap: () => Navigator.push(
                          context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
                    ),
                    const SizedBox(height: 20),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 1.35,
                      children: [
                        StatCard(
                          icon: Icons.account_balance_wallet_outlined,
                          iconBg: AppColors.pastelGreenBg,
                          iconColor: AppColors.positive,
                          title: 'دارایی‌ها',
                          value: formatMoney(_assets, withSuffix: false),
                          unit: 'تومان',
                        ),
                        StatCard(
                          icon: Icons.credit_card_outlined,
                          iconBg: AppColors.pastelRedBg,
                          iconColor: AppColors.negative,
                          title: 'بدهی‌ها',
                          value: formatMoney(_liabilities, withSuffix: false),
                          unit: 'تومان',
                        ),
                        StatCard(
                          icon: Icons.show_chart_rounded,
                          iconBg: AppColors.pastelBlueBg,
                          iconColor: AppColors.pastelBlueFg,
                          title: 'خالص ارزش',
                          value: formatMoney(_netWorth, withSuffix: false),
                          unit: 'تومان',
                        ),
                        StatCard(
                          icon: Icons.balance_outlined,
                          iconBg: AppColors.pastelTealBg,
                          iconColor: AppColors.pastelTealFg,
                          title: 'حقوق صاحبان سهام',
                          value: formatMoney(_equity, withSuffix: false),
                          unit: 'تومان',
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: AppActionButton(
                            label: 'دریافت',
                            icon: Icons.arrow_downward_rounded,
                            color: AppColors.positive,
                            onTap: () => showQuickAddSheet(context, onDone: _load),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: AppActionButton(
                            label: 'پرداخت',
                            icon: Icons.arrow_upward_rounded,
                            color: AppColors.negative,
                            onTap: () => showQuickAddSheet(context, onDone: _load),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// هدر داشبورد: عنوان و زیرعنوان + دکمه اعلان دایره‌ای
class _DashboardHeader extends StatelessWidget {
  final VoidCallback onNotificationTap;
  const _DashboardHeader({required this.onNotificationTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'داشبورد',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'نمای کلی کسب‌وکار',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: onNotificationTap,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: AppColors.surfaceAlt, shape: BoxShape.circle),
              child: const Icon(Icons.notifications_none_rounded,
                  color: AppColors.textPrimary, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}
