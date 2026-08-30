import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/widgets/rolling_road_loader.dart';
import '../../../core/services/driver_operations_log.dart';
import '../../../core/services/driver_session.dart';
import '../../../core/services/user_session.dart';
import '../../auth/screens/about_app_screen.dart';
import '../../auth/screens/role_selection_screen.dart';
import '../../commuter/screens/commuter_dashboard_screen.dart';
import '../../commuter/screens/commuter_history_screen.dart';
import '../../commuter/screens/notifications_screen.dart';
import '../../driver/screens/driver_dashboard_screen.dart';

class LoadingScreen extends StatefulWidget {
  const LoadingScreen({super.key});

  @override
  State<LoadingScreen> createState() => _LoadingScreenState();
}

class _LoadingScreenState extends State<LoadingScreen> {
  @override
  void initState() {
    super.initState();
    _navigateToNextScreen();
  }

  void _navigateToNextScreen() {
    // Delays for 3 seconds, then routes onward. Wrapped in an overall
    // timeout — a platform call below (most likely a secure-storage read;
    // FlutterSecureStorage's Android Keystore backing is known to hang on
    // some devices/OS states) never resolving must never leave the app
    // stuck on this screen forever. A timeout just falls back to the same
    // role-selection screen a brand-new install would see anyway; it
    // can't cancel whatever's still hung in the background, but a late
    // completion is a no-op once `mounted` is false (this screen is
    // already gone by then).
    Future.delayed(const Duration(seconds: 3), () async {
      try {
        await _resolveSessionAndNavigate().timeout(const Duration(seconds: 8));
      } catch (_) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const RoleSelectionScreen()),
        );
      }
    });
  }

  Future<void> _resolveSessionAndNavigate() async {
    // Checks for a "Remember Me" session first (driver, then commuter — a
    // device could in theory have both, though that's rare) and skips
    // straight to that dashboard if found. Otherwise, a commuter who
    // closed the app mid-verification lands back on AboutAppScreen
    // instead of role selection — see UserSession.pendingVerificationMobileNumber.
    await Future.wait([
      DriverSession.instance.loadFromPrefs(),
      UserSession.instance.loadFromPrefs(),
    ]);
    if (!mounted) return;

    if (DriverSession.instance.hasRememberedSession) {
      await DriverOperationsLog.loadFromPrefs();
      unawaited(DriverOperationsLog.syncFromBackend());
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverDashboardScreen()),
      );
      return;
    }

    if (UserSession.instance.hasRememberedSession) {
      await Future.wait([
        CommuterHistoryScreen.loadFromPrefs(),
        NotificationsScreen.loadFromPrefs(),
      ]);
      unawaited(CommuterHistoryScreen.syncFromBackend());
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CommuterDashboardScreen()),
      );
      return;
    }

    final isPendingVerification = UserSession.instance.pendingVerificationMobileNumber != null;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => isPendingVerification ? const AboutAppScreen() : const RoleSelectionScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashBackground,
      body: SafeArea(
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start, // Pushes content upward
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 80), // Controls top offset for logo position

              // Jeepney Graphic
              Image.asset(
                AppAssets.jeepneyLogo,
                width: 140,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.directions_bus_filled_rounded,
                    size: 100,
                    color: AppColors.logoBlue,
                  );
                },
              ),
              
              // Reduced spacing to bring text closer to the logo
              const SizedBox(height: 2),

              // "ManibelaApp" Dual Color Title
              RichText(
                text: const TextSpan(
                  style: TextStyle(
                    fontSize: 35,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                  children: [
                    TextSpan(
                      text: 'Manibela',
                      style: TextStyle(color: AppColors.logoBlue),
                    ),
                    TextSpan(
                      text: 'App',
                      style: TextStyle(color: AppColors.logoRed),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // A jeepney riding a dashed road instead of a generic spinner
              // — the wordmark alone gave no sign the app was actually
              // doing anything for the full 3 seconds, same gap the admin
              // website's own loading screen had before it got one.
              const RollingRoadLoader(),

              const SizedBox(height: 14),
              const Text(
                'Getting your ride ready…',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.onPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}