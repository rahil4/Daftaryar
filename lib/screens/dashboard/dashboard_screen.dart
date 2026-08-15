import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../db/database_helper.dart';
import '../../utils/formatters.dart';
import '../../widgets/quick_add_sheet.dart';
import '../settings/settings_screen.dart';

// ============== پالت رنگی محلی این صفحه (طراحی روشن مدرن) ==============
class _LightPalette {
  static const background = Color(0xFFF5F7FA);
  static const cardWhite = Colors.white;
  static const textDark = Color(0xFF1E293B);
  static const textGrey = Color(0xFF94A3B8);
  static const iconGreenBg = Color(0xFFDCFCE7);
  static const iconGreenFg = Color(0xFF16A34A);
  static const iconRedBg = Color(0xFFFEE2E2);
  static const iconRedFg = Color(0xFFDC2626);
  static const iconBlueBg = Color(0xFFDBEAFE);
  static const iconBlueFg = Color(0xFF2563EB);
  static const iconTealBg = Color(0xFFCCFBF1);
  static const iconTealFg = Color(0xFF0D9488);
}

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
    final vazir = GoogleFonts.vazirmatn();
    return Scaffold(
      // ۱) پس‌زمینه ملایم صفحه
      backgroundColor: _LightPalette.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _DashboardHeader(fontFamily: vazir.fontFamily),
                    const SizedBox(height: 20),

                    // ۳) کارت‌های خلاصه مالی — گرید ۲ در ۲
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 14,
                      childAspectRatio: 1.35,
                      children: [
                        _SummaryCard(
                          fontFamily: vazir.fontFamily,
                          icon: Icons.account_balance_wallet_outlined,
                          iconBg: _LightPalette.iconGreenBg,
                          iconColor: _LightPalette.iconGreenFg,
                          label: 'دارایی‌ها',
                          value: _assets,
                        ),
                        _SummaryCard(
                          fontFamily: vazir.fontFamily,
                          icon: Icons.credit_card_outlined,
                          iconBg: _LightPalette.iconRedBg,
                          iconColor: _LightPalette.iconRedFg,
                          label: 'بدهی‌ها',
                          value: _liabilities,
                        ),
                        _SummaryCard(
                          fontFamily: vazir.fontFamily,
                          icon: Icons.show_chart_rounded,
                          iconBg: _LightPalette.iconBlueBg,
                          iconColor: _LightPalette.iconBlueFg,
                          label: 'خالص ارزش',
                          value: _netWorth,
                        ),
                        _SummaryCard(
                          fontFamily: vazir.fontFamily,
                          icon: Icons.balance_outlined,
                          iconBg: _LightPalette.iconTealBg,
                          iconColor: _LightPalette.iconTealFg,
                          label: 'حقوق صاحبان سهام',
                          value: _equity,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ۴) دکمه‌های اقدام سریع: دریافت / پرداخت
                    Row(
                      children: [
                        Expanded(
                          child: _QuickActionButton(
                            fontFamily: vazir.fontFamily,
                            label: 'دریافت',
                            icon: Icons.arrow_downward_rounded,
                            color: const Color(0xFF16A34A),
                            onTap: () => showQuickAddSheet(context, onDone: _load),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _QuickActionButton(
                            fontFamily: vazir.fontFamily,
                            label: 'پرداخت',
                            icon: Icons.arrow_upward_rounded,
                            color: const Color(0xFFDC2626),
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

/// ۲) هدر داشبورد: عنوان + زیرعنوان در راست، دکمه اعلان دایره‌ای در چپ
class _DashboardHeader extends StatelessWidget {
  final String? fontFamily;
  const _DashboardHeader({required this.fontFamily});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _LightPalette.cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'داشبورد',
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: _LightPalette.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'نمای کلی کسب‌وکار',
                  style: TextStyle(
                    fontFamily: fontFamily,
                    fontSize: 13,
                    color: _LightPalette.textGrey,
                  ),
                ),
              ],
            ),
          ),
          // دکمه اعلان
          InkWell(
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
            borderRadius: BorderRadius.circular(24),
            child: Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.notifications_none_rounded,
                  color: _LightPalette.textDark, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

/// کارت خلاصه مالی قابل استفاده مجدد (دارایی/بدهی/خالص ارزش/حقوق سهام)
class _SummaryCard extends StatelessWidget {
  final String? fontFamily;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final double value;

  const _SummaryCard({
    required this.fontFamily,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _LightPalette.cardWhite,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const Spacer(),
          Text(
            label,
            style: TextStyle(fontFamily: fontFamily, fontSize: 12, color: _LightPalette.textGrey),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(
              formatMoney(value, withSuffix: false),
              style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _LightPalette.textDark,
              ),
            ),
          ),
          Text(
            'تومان',
            style: TextStyle(fontFamily: fontFamily, fontSize: 10, color: _LightPalette.textGrey),
          ),
        ],
      ),
    );
  }
}

/// دکمه اقدام سریع (دریافت/پرداخت) با رنگ، سایه هم‌رنگ و آیکون
class _QuickActionButton extends StatelessWidget {
  final String? fontFamily;
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.fontFamily,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontFamily: fontFamily,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
