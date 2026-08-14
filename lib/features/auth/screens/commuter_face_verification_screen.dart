import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import '../../../core/utils/platform_utils.dart';
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
  final ImagePicker _picker = ImagePicker();

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
      // Front camera, since this is a selfie for identity verification —
      // not a photo library pick, so the user can't submit an old/unrelated
      // photo here the way they can for the ID front/back uploads. Desktop
      // is the one exception: image_picker has no webcam support there at
      // all (see isDesktopPlatform), so ImageSource.camera would just
      // throw — fall back to a file pick so the flow is at least usable
      // for local testing.
      final XFile? picked = await _picker.pickImage(
        source: isDesktopPlatform ? ImageSource.gallery : ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
      );

      if (!mounted) return;

      if (picked == null) {
        // User backed out of the camera without taking a photo.
        setState(() => _isProcessing = false);
        return;
      }

      setState(() {
        _capturedPhoto = File(picked.path);
        _isProcessing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _error = 'Could not capture your photo. Please try again.';
      });
    }
  }

  void _handleRetake() {
    if (_isProcessing) return; // don't allow retake mid-request
    setState(() {
      _capturedPhoto = null;
      _error = null;
    });
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
      // Uploads and persists the selfie against the pending signup — but
      // doesn't itself verify anything. TODO: run an actual face-match
      // against the ID photos uploaded on the previous screen once a
      // provider for that is chosen; right now this step only proves a
      // selfie was captured, not that it matches the ID.
      await ApiClient.uploadFiles(
        '/api/commuter/signup/${widget.signupTicket}/selfie',
        files: {'selfie': _capturedPhoto!.path},
      );
      if (!mounted) return;

      // This is the actual account-creation call — nothing about the
      // commuter's account exists in the database until this succeeds.
      // It deliberately doesn't return an auth token: a fresh account is
      // never APPROVED yet, so there's nothing to log in to (see
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
                  child: _FaceFrame(
                    photo: _capturedPhoto,
                    isProcessing: _isProcessing && !_isCaptured,
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

class _FaceFrame extends StatelessWidget {
  const _FaceFrame({required this.photo, required this.isProcessing});

  final File? photo;
  final bool isProcessing;

  @override
  Widget build(BuildContext context) {
    final isCaptured = photo != null;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 240,
          height: 300,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: isCaptured ? AppColors.qrTileBg : const Color(0xFFECEDEF),
            borderRadius: BorderRadius.circular(140),
            border: Border.all(
              color: AppColors.primary,
              width: 3,
            ),
          ),
          child: isCaptured
              ? Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(photo!, fit: BoxFit.cover),
                    Positioned(
                      right: 10,
                      bottom: 10,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check_rounded, size: 18, color: AppColors.onPrimary),
                      ),
                    ),
                  ],
                )
              : const Icon(
                  Icons.face_retouching_natural_rounded,
                  size: 72,
                  color: Colors.black26,
                ),
        ),
        if (isProcessing)
          const CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
      ],
    );
  }
}