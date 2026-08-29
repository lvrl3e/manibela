import 'dart:io';

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import '../../../core/widgets/selfie_capture_field.dart';
import 'commuter_verification_status_screen.dart';

class CommuterFaceVerificationScreen extends StatefulWidget {
  const CommuterFaceVerificationScreen({
    super.key,
    required this.signupTicket,
  });

  /// Redeemed into the actual account on a successful confirm below — this
  /// is the last step of sign-up, so it's the only place a Commuter row
  /// ever gets created.
  final String signupTicket;

  @override
  State<CommuterFaceVerificationScreen> createState() => _CommuterFaceVerificationScreenState();
}

class _CommuterFaceVerificationScreenState extends State<CommuterFaceVerificationScreen> {
  final GlobalKey<SelfieCaptureFieldState> _selfieKey = GlobalKey<SelfieCaptureFieldState>();

  File? _capturedPhoto;
  bool get _isCaptured => _capturedPhoto != null;

  bool _isProcessing = false; // covers both the capture and confirm requests
  String? _error;

  Future<void> _handleCapture() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      await _selfieKey.currentState?.capture();
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Could not capture your photo. Please try again.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _handleRetake() {
    if (_isProcessing) return; // don't allow retake mid-request
    _selfieKey.currentState?.retake();
    setState(() => _error = null);
  }

  Future<void> _handleConfirm() async {
    if (_isProcessing) return;

    // --- Validation ---------------------------------------------------
    if (!_isCaptured) {
      setState(() => _error = 'Please capture a photo first');
      return;
    }

    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      // Uploads and persists the selfie against the pending signup —
      // POST /signup (below) is what actually runs Didit's automated
      // face-match against the ID photos uploaded on the previous
      // screen, once that account row is created.
      await ApiClient.uploadFiles(
        '/api/commuter/signup/${widget.signupTicket}/selfie',
        files: {'selfie': _capturedPhoto!.path},
      );
      if (!mounted) return;

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
        _isProcessing = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = 'We could not verify your face. Please retake and try again.';
      });
    }
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
          'Face Verification',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          child: Column(
            children: [
              Text(
                _isCaptured
                    ? 'Review your photo before confirming'
                    : 'Position your face within the frame and hold still',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black54),
              ),
              const SizedBox(height: 28),
              Expanded(
                child: Center(
                  child: SelfieCaptureField(
                    key: _selfieKey,
                    onChanged: (file) => setState(() => _capturedPhoto = file),
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
              if (!_isCaptured)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isProcessing ? null : _handleCapture,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary),
                          )
                        : const Text(
                            'Capture',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.onPrimary),
                          ),
                  ),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isProcessing ? null : _handleRetake,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.logoBlue),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text(
                          'Retake',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.logoBlue),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _isProcessing ? null : _handleConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _isProcessing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary),
                              )
                            : const Text(
                                'Confirm',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.onPrimary),
                              ),
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
