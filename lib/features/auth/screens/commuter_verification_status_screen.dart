import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import 'about_app_screen.dart';
import 'commuter_login_screen.dart';

/// Shown instead of the dashboard whenever a commuter's account isn't
/// APPROVED yet — right after sign-up, or whenever a later login attempt
/// gets blocked (see POST /api/commuter/login, which withholds the auth
/// token entirely until an admin approves the account).
///
/// Polls GET /api/commuter/verification-status in the background so this
/// screen updates itself the moment an admin approves or rejects the
/// account — no need to back out and retry a login just to re-check.
class CommuterVerificationStatusScreen extends StatefulWidget {
  const CommuterVerificationStatusScreen({
    super.key,
    required this.status,
    required this.mobileNumber,
  });

  /// Raw value from the backend: 'PENDING', 'REJECTED', 'APPROVED', or
  /// null (no ID submitted at all — shouldn't happen given the current
  /// sign-up flow, but treated the same as PENDING rather than crashing
  /// on it).
  final String? status;

  /// Already normalized to `+63XXXXXXXXXX` — used to poll the status
  /// endpoint, which is public and needs no password.
  final String mobileNumber;

  @override
  State<CommuterVerificationStatusScreen> createState() => _CommuterVerificationStatusScreenState();
}

class _CommuterVerificationStatusScreenState extends State<CommuterVerificationStatusScreen> {
  static const _pollInterval = Duration(seconds: 5);

  late String? _status = widget.status;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _checkStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    try {
      final response = await ApiClient.get(
        '/api/commuter/verification-status?mobileNumber=${Uri.encodeQueryComponent(widget.mobileNumber)}',
      );
      if (!mounted) return;
      final nextStatus = response['verificationStatus'] as String?;
      if (nextStatus != _status) {
        setState(() => _status = nextStatus);
      }
      if (nextStatus == 'APPROVED' || nextStatus == 'REJECTED') {
        _pollTimer?.cancel();
      }
    } catch (_) {
      // Best-effort — a failed poll just tries again on the next tick,
      // it never blocks or errors out this screen.
    }
  }

  bool get _isRejected => _status == 'REJECTED';
  bool get _isApproved => _status == 'APPROVED';

  void _handleClose() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AboutAppScreen()),
      (route) => false,
    );
  }

  void _handleContinueToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CommuterLoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final iconBg = _isRejected
        ? AppColors.logoutTileBg
        : _isApproved
            ? const Color(0xFFDCFCE7)
            : AppColors.qrTileBg;
    final iconColor = _isRejected
        ? AppColors.logoutIconColor
        : _isApproved
            ? const Color(0xFF16A34A)
            : AppColors.qrIconColor;
    final icon = _isRejected
        ? Icons.close_rounded
        : _isApproved
            ? Icons.check_rounded
            : Icons.hourglass_top_rounded;
    final title = _isRejected
        ? 'Verification Unsuccessful'
        : _isApproved
            ? "You're Verified!"
            : 'Verification In Progress';
    final message = _isRejected
        ? "We couldn't verify the ID and selfie you submitted. Please contact support for help getting this resolved."
        : _isApproved
            ? 'Your account has been approved. You can now log in and start using ManibelApp.'
            : "We're reviewing the ID and selfie you submitted. This usually only takes a short while — please check back later.";

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
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 44),
              ),
              const SizedBox(height: 24),
              Text(
                title,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.black54, height: 1.4),
              ),
              if (!_isApproved) ...[
                const SizedBox(height: 8),
                const Text(
                  "You won't be able to log in until this is approved.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black38),
                ),
              ],
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isApproved ? _handleContinueToLogin : _handleClose,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _isApproved ? 'Continue to Login' : 'Close',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.onPrimary),
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
