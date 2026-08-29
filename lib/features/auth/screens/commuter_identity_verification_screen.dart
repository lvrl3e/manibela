import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import 'commuter_verification_status_screen.dart';

/// Replaces the old two-screen ID-photos → selfie capture flow. ID/face
/// verification now happens entirely on Didit's own hosted page (see
/// backend/src/lib/didit.ts) — this screen starts that session, opens it
/// in an in-app browser tab, and polls for a result once the user
/// finishes there, same as CommuterVerificationStatusScreen's own
/// polling pattern for the later admin-review step.
class CommuterIdentityVerificationScreen extends StatefulWidget {
  const CommuterIdentityVerificationScreen({
    super.key,
    required this.signupTicket,
  });

  final String signupTicket;

  @override
  State<CommuterIdentityVerificationScreen> createState() => _CommuterIdentityVerificationScreenState();
}

class _CommuterIdentityVerificationScreenState extends State<CommuterIdentityVerificationScreen> {
  Timer? _pollTimer;

  // Distinct stages rather than one bool, since the button/spinner/copy
  // all differ across "haven't started yet", "waiting on Didit's page",
  // and "wrapping up account creation".
  bool _isStartingSession = false;
  bool _isWaitingOnDidit = false;
  bool _isFinishing = false;
  String? _error;

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  bool get _isBusy => _isStartingSession || _isWaitingOnDidit || _isFinishing;

  Future<void> _startVerification() async {
    if (_isBusy) return;

    setState(() {
      _isStartingSession = true;
      _error = null;
    });

    try {
      final response = await ApiClient.post(
        '/api/commuter/signup/${widget.signupTicket}/verification-session',
        {},
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
        _isWaitingOnDidit = true;
      });
      _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _checkStatus());
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

  Future<void> _checkStatus() async {
    try {
      final response = await ApiClient.get(
        '/api/commuter/signup/${widget.signupTicket}/verification-status',
      );
      final decision = response['decision'] as String?;
      if (decision == null) return; // Still waiting on Didit's webhook — keep polling.

      _pollTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _isWaitingOnDidit = false;
        _isFinishing = true;
      });
      await _completeSignup();
    } catch (_) {
      // A single failed poll isn't fatal — the next tick just tries again.
    }
  }

  Future<void> _completeSignup() async {
    try {
      // This is the actual account-creation call — nothing about the
      // commuter's account exists in the database until this succeeds.
      // It deliberately doesn't return an auth token: even an
      // auto-approved account still logs in normally afterward (see
      // POST /api/commuter/login, which enforces the same rule).
      final response = await ApiClient.post('/api/commuter/signup', {
        'ticket': widget.signupTicket,
      });

      final mobileNumber = (response['commuter'] as Map<String, dynamic>)['mobileNumber'] as String;
      await UserSession.instance.setPendingVerification(mobileNumber);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
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
        _isFinishing = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isFinishing = false;
        _error = 'Something went wrong finishing sign-up. Please try again.';
      });
    }
  }

  String get _statusText {
    if (_isStartingSession) return 'Preparing verification…';
    if (_isWaitingOnDidit) return 'Complete verification in the page that just opened, then come back here.';
    if (_isFinishing) return 'Finishing up…';
    return 'You\'ll verify your ID and take a quick selfie on a secure page — it only takes a minute.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF5F6F8),
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          'Identity Verification',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            children: [
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: const BoxDecoration(
                          color: AppColors.qrTileBg,
                          shape: BoxShape.circle,
                        ),
                        child: _isBusy
                            ? const Padding(
                                padding: EdgeInsets.all(28),
                                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary),
                              )
                            : const Icon(Icons.verified_user_outlined, size: 44, color: AppColors.primary),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _statusText,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.black54, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ),
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
                  onPressed: _isBusy ? null : _startVerification,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _isWaitingOnDidit ? 'Waiting for verification…' : 'Start Verification',
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
