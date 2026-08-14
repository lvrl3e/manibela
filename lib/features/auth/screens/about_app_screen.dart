import 'package:flutter/material.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import 'commuter_verification_status_screen.dart';
import 'role_selection_screen.dart';

/// Landing spot for a commuter whose account is still awaiting ID
/// verification — shown when they close CommuterVerificationStatusScreen,
/// and again on every cold start while UserSession.pendingVerificationMobileNumber
/// is still set (see LoadingScreen). Keeps them out of the
/// signup/role-selection loop while they wait, without pretending they're
/// logged in.
class AboutAppScreen extends StatefulWidget {
  const AboutAppScreen({super.key});

  @override
  State<AboutAppScreen> createState() => _AboutAppScreenState();
}

class _AboutAppScreenState extends State<AboutAppScreen> {
  bool _isChecking = false;
  String? _error;

  Future<void> _handleCheckStatus() async {
    final mobileNumber = UserSession.instance.pendingVerificationMobileNumber;
    if (mobileNumber == null) return;

    setState(() {
      _isChecking = true;
      _error = null;
    });

    try {
      final response = await ApiClient.get(
        '/api/commuter/verification-status?mobileNumber=${Uri.encodeQueryComponent(mobileNumber)}',
      );
      if (!mounted) return;
      setState(() => _isChecking = false);

      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CommuterVerificationStatusScreen(
            status: response['verificationStatus'] as String?,
            mobileNumber: mobileNumber,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isChecking = false;
        _error = e.message;
      });
    }
  }

  Future<void> _handleBackToRoleSelection() async {
    await UserSession.instance.clearPendingVerification();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                AppAssets.jeepneyLogo,
                width: 110,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(Icons.directions_bus_filled_rounded, size: 70, color: AppColors.logoBlue);
                },
              ),
              const SizedBox(height: 12),
              RichText(
                text: const TextSpan(
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  children: [
                    TextSpan(text: 'Manibel', style: TextStyle(color: AppColors.logoBlue)),
                    TextSpan(text: 'App', style: TextStyle(color: AppColors.logoRed)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Sakay na, ano tara?',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 28),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'While you wait',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  "Here's what you'll be able to do once your account is approved:",
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4),
                ),
              ),
              const SizedBox(height: 20),
              const _FeatureRow(
                icon: Icons.map_rounded,
                title: 'Track jeepneys live',
                subtitle: "See where nearby jeepneys are on the map, in real time.",
              ),
              const _FeatureRow(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scan and ride',
                subtitle: 'Confirm your ride by scanning your driver\'s QR code.',
              ),
              const _FeatureRow(
                icon: Icons.report_gmailerrorred_rounded,
                title: 'Report an issue',
                subtitle: 'File a complaint about a driver, with photo evidence if you need it.',
                isLast: true,
              ),
              const SizedBox(height: 28),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE23F3F)),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isChecking ? null : _handleCheckStatus,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isChecking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary),
                        )
                      : const Text(
                          'Check Verification Status',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.onPrimary),
                        ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _handleBackToRoleSelection,
                child: const Text(
                  'Not you? Go back to role selection',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.isLast = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: AppColors.qrTileBg, shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Icon(icon, size: 20, color: AppColors.qrIconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
