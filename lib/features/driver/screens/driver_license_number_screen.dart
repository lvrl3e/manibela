import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_session.dart';

/// Settings -> License Number. Verification happens entirely on Didit's
/// own hosted page (license authenticity + liveness + face-match, all
/// captured there — see backend/src/lib/didit.ts), not through an
/// upload here — this screen starts that session, opens it in an
/// in-app browser tab, and briefly polls GET /driver/me afterward in
/// case a clean pass auto-approves right away. An admin only needs to
/// type in the license number when Didit didn't confidently resolve it
/// — see the Driver Detail Panel.
class DriverLicenseNumberScreen extends StatefulWidget {
  const DriverLicenseNumberScreen({super.key});

  @override
  State<DriverLicenseNumberScreen> createState() => _DriverLicenseNumberScreenState();
}

class _DriverLicenseNumberScreenState extends State<DriverLicenseNumberScreen> {
  String? _status; // null | 'PENDING' | 'APPROVED' | 'REJECTED'
  String? _licenseNumber;
  bool _isLoadingStatus = true;
  bool _isStartingSession = false;
  bool _isPolling = false;
  String? _error;

  Timer? _pollTimer;
  int _pollAttempts = 0;
  static const int _maxPollAttempts = 40; // ~2 minutes at 3s apart

  // Nothing to start while still loading, and nothing left to start once
  // there's a submission an admin hasn't rejected — a rejection reopens
  // this for another attempt.
  bool get _canStart => !_isLoadingStatus && _status != 'PENDING' && _status != 'APPROVED';

  String get _headerText {
    switch (_status) {
      case 'PENDING':
        return 'Your verification is in progress. If it needs manual review, an admin will check it soon.';
      case 'APPROVED':
        return 'Your driver\'s license has been verified.';
      case 'REJECTED':
        return 'Your submission was rejected. Start verification again with a clearer license and selfie.';
      default:
        return 'Verify your driver\'s license on a secure page — you\'ll show your license and take a quick selfie. This confirms both that your license is genuine and that it\'s really you.';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStatus() async {
    try {
      final response = await ApiClient.get(
        '/api/driver/me',
        token: DriverSession.instance.authToken,
      );
      final driver = response['driver'] as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _status = driver['licenseVerificationStatus'] as String?;
        _licenseNumber = driver['licenseNumber'] as String?;
        _isLoadingStatus = false;
      });
    } on ApiException {
      if (!mounted) return;
      setState(() => _isLoadingStatus = false);
    }
  }

  Future<void> _startVerification() async {
    if (_isStartingSession || _isPolling) return;

    setState(() {
      _isStartingSession = true;
      _error = null;
    });

    try {
      final response = await ApiClient.post(
        '/api/driver/me/verification-session',
        {},
        token: DriverSession.instance.authToken,
      );
      final url = response['url'] as String;
      if (!mounted) return;

      final launched = await launchUrl(Uri.parse(url), mode: LaunchMode.inAppBrowserView);
      if (!mounted) return;

      if (!launched) {
        setState(() {
          _isStartingSession = false;
          _error = 'Could not open the verification page. Please try again.';
        });
        return;
      }

      setState(() {
        _isStartingSession = false;
        _isPolling = true;
        _status = 'PENDING';
      });
      _pollAttempts = 0;
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _pollStatus());
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isStartingSession = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isStartingSession = false;
        _error = 'Something went wrong starting verification. Please try again.';
      });
    }
  }

  Future<void> _pollStatus() async {
    _pollAttempts++;
    if (_pollAttempts > _maxPollAttempts) {
      _pollTimer?.cancel();
      if (mounted) setState(() => _isPolling = false);
      return;
    }

    try {
      final response = await ApiClient.get(
        '/api/driver/me',
        token: DriverSession.instance.authToken,
      );
      final driver = response['driver'] as Map<String, dynamic>;
      final newStatus = driver['licenseVerificationStatus'] as String?;
      if (newStatus == 'PENDING') return; // Still waiting on Didit's webhook.

      _pollTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isPolling = false;
        _status = newStatus;
        _licenseNumber = driver['licenseNumber'] as String?;
      });
    } catch (_) {
      // A single failed poll isn't fatal — the next tick just tries again.
    }
  }

  Widget _statusBadge() {
    if (_isLoadingStatus) return const SizedBox.shrink();

    late final Color bg;
    late final Color fg;
    late final String label;
    switch (_status) {
      case 'PENDING':
        bg = const Color(0xFFFFF4CC);
        fg = const Color(0xFF92600A);
        label = _isPolling ? 'Verifying…' : 'Waiting for admin review';
        break;
      case 'APPROVED':
        bg = const Color(0xFFDDF7E3);
        fg = const Color(0xFF1B7A3D);
        label = _licenseNumber != null ? 'Verified — $_licenseNumber' : 'Verified';
        break;
      case 'REJECTED':
        bg = const Color(0xFFFDE2E2);
        fg = const Color(0xFFB91C1C);
        label = 'Rejected — please try again';
        break;
      default:
        bg = const Color(0xFFF2F2F3);
        fg = Colors.black54;
        label = 'Not verified yet';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 13),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = _isStartingSession || _isPolling;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
        title: const Text(
          'License Number',
          style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              _headerText,
              style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            _statusBadge(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE23F3F)),
                ),
              ),
            // Once verification is pending review or already approved,
            // there's nothing left to start — hide the button entirely
            // rather than letting a driver keep re-starting on top of one
            // an admin hasn't looked at yet. A rejection reopens it so
            // they can try again.
            if (_canStart) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: isBusy ? null : _startVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: isBusy
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2.5),
                        )
                      : const Text(
                          'Verify License',
                          style: TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w800, fontSize: 16),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
