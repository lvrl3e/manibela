import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../commuter/screens/commuter_dashboard_screen.dart';
import '../../commuter/screens/commuter_history_screen.dart';
import '../../commuter/screens/notifications_screen.dart';

class CommuterVerifiedScreen extends StatelessWidget {
  const CommuterVerifiedScreen({super.key, required this.idType});

  final String idType;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: const BoxDecoration(color: AppColors.settingsTileBg, shape: BoxShape.circle),
                child: const Icon(Icons.check_rounded, color: AppColors.logoBlue, size: 52),
              ),
              const SizedBox(height: 24),
              const Text(
                "You're Verified!",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black),
              ),
              const SizedBox(height: 8),
              Text(
                'Your $idType and face verification were successful. You can now book rides as a commuter.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black54, height: 1.4),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    // Load whatever's already persisted for this account
                    // (e.g. re-verifying an existing commuter) before the
                    // dashboard ever builds.
                    await CommuterHistoryScreen.loadFromPrefs();
                    await NotificationsScreen.loadFromPrefs();
                    if (!context.mounted) return;
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const CommuterDashboardScreen()),
                      (route) => false,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Continue to Dashboard',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.onPrimary),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}