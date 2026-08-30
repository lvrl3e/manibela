import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_session.dart';
import '../../../core/widgets/in_app_camera_capture.dart';

/// Settings -> License Number. The driver submits front + back photos of
/// their license here; an admin then reviews them and types the license
/// number in themselves from the Driver Detail Panel — no OCR/auto-detect
/// (see TODO.md for why that was considered and dropped in favor of this
/// simpler manual-review flow). Once approved, the actual number the
/// admin typed in is shown here too, not just a bare "Verified" status.
class DriverLicenseNumberScreen extends StatefulWidget {
  const DriverLicenseNumberScreen({super.key});

  @override
  State<DriverLicenseNumberScreen> createState() => _DriverLicenseNumberScreenState();
}

class _DriverLicenseNumberScreenState extends State<DriverLicenseNumberScreen> {
  String? _status; // null | 'PENDING' | 'APPROVED' | 'REJECTED'
  String? _licenseNumber;
  File? _frontImage;
  File? _backImage;
  File? _selfieImage;
  bool _isLoadingStatus = true;
  bool _isPickingImage = false;
  bool _isSubmitting = false;

  // Nothing to upload while still loading, and nothing left to upload
  // once there's a submission an admin hasn't rejected — a rejection is
  // the one status that reopens this for a resubmit.
  bool get _canSubmit => !_isLoadingStatus && _status != 'PENDING' && _status != 'APPROVED';

  String get _headerText {
    switch (_status) {
      case 'PENDING':
        return 'Your license photos have been submitted and are waiting for admin review.';
      case 'APPROVED':
        return 'Your driver\'s license has been verified.';
      case 'REJECTED':
        return 'Your submission was rejected. Submit clearer photos of the front and back of your license.';
      default:
        return 'Submit clear photos of the front and back of your driver\'s license, plus a selfie — a match against your license photo may verify you instantly, otherwise an admin will review it.';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadStatus();
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

  Future<void> _pickImage({required bool isFront}) async {
    if (_isPickingImage) return;

    setState(() => _isPickingImage = true);
    try {
      // The app's own live camera view (rectangular guide matching an ID
      // card's proportions), not a gallery pick — see InAppCameraCapture's
      // own doc comment.
      final File? picked = await InAppCameraCapture.capture(
        context,
        lensDirection: CameraLensDirection.back,
        guideShape: CaptureGuideShape.rectangle,
        guideAspectRatio: _LicensePhotoTile.licenseCardAspectRatio,
        instruction: isFront
            ? 'Line up the front of your license within the frame'
            : 'Line up the back of your license within the frame',
      );
      if (picked == null || !mounted) return;

      setState(() {
        if (isFront) {
          _frontImage = picked;
        } else {
          _backImage = picked;
        }
      });
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _pickSelfie() async {
    if (_isPickingImage) return;

    setState(() => _isPickingImage = true);
    try {
      final File? picked = await InAppCameraCapture.capture(
        context,
        lensDirection: CameraLensDirection.front,
        guideShape: CaptureGuideShape.oval,
        instruction: 'Position your face within the frame',
        requireLiveness: true,
      );
      if (picked == null || !mounted) return;

      setState(() => _selfieImage = picked);
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (_frontImage == null || _backImage == null || _selfieImage == null) return;

    setState(() => _isSubmitting = true);

    try {
      final response = await ApiClient.uploadFiles(
        '/api/driver/me/license-photo',
        files: {
          'licenseFront': _frontImage!.path,
          'licenseBack': _backImage!.path,
          'selfie': _selfieImage!.path,
        },
        token: DriverSession.instance.authToken,
      );

      if (!mounted) return;
      final driver = response['driver'] as Map<String, dynamic>;
      final newStatus = driver['licenseVerificationStatus'] as String?;
      setState(() {
        _isSubmitting = false;
        _frontImage = null;
        _backImage = null;
        _selfieImage = null;
        _status = newStatus;
        _licenseNumber = driver['licenseNumber'] as String?;
      });

      final autoCleared = newStatus == 'APPROVED';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(autoCleared ? "You're Verified!" : 'Submitted'),
          content: Text(
            autoCleared
                ? 'Your selfie matched your license photo — your license is verified, no review needed.'
                : "Your license photos have been submitted. An admin will review them and verify your license number.",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
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
        label = 'Waiting for admin review';
        break;
      case 'APPROVED':
        bg = const Color(0xFFDDF7E3);
        fg = const Color(0xFF1B7A3D);
        label = _licenseNumber != null ? 'Verified — $_licenseNumber' : 'Verified';
        break;
      case 'REJECTED':
        bg = const Color(0xFFFDE2E2);
        fg = const Color(0xFFB91C1C);
        label = 'Rejected — please submit clearer photos';
        break;
      default:
        bg = const Color(0xFFF2F2F3);
        fg = Colors.black54;
        label = 'Not submitted yet';
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
            const SizedBox(height: 20),
            // Once a submission is pending review or already verified,
            // there's nothing left to upload — hide the picker/submit
            // entirely rather than letting a driver keep re-submitting on
            // top of one an admin hasn't looked at yet. A rejection
            // reopens it so they can try again.
            if (_canSubmit) ...[
              _LicensePhotoTile(
                label: 'Front of License',
                file: _frontImage,
                disabled: _isPickingImage,
                onTap: () => _pickImage(isFront: true),
              ),
              const SizedBox(height: 12),
              _LicensePhotoTile(
                label: 'Back of License',
                file: _backImage,
                disabled: _isPickingImage,
                onTap: () => _pickImage(isFront: false),
              ),
              const SizedBox(height: 20),
              Center(
                child: _SelfieTile(
                  file: _selfieImage,
                  disabled: _isPickingImage,
                  onTap: _pickSelfie,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_frontImage == null || _backImage == null || _selfieImage == null || _isSubmitting)
                      ? null
                      : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(color: AppColors.onPrimary, strokeWidth: 2.5),
                        )
                      : const Text(
                          'Submit',
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

class _LicensePhotoTile extends StatelessWidget {
  const _LicensePhotoTile({
    required this.label,
    required this.file,
    required this.onTap,
    this.disabled = false,
  });

  final String label;
  final File? file;
  final bool disabled;
  final VoidCallback onTap;

  // Standard CR80 card ratio (85.6mm × 53.98mm — the physical size of a PH
  // driver's license) — matches CommuterVerificationScreen's own ID
  // preview so both read as "a card", not an arbitrary photo thumbnail.
  static const double licenseCardAspectRatio = 85.6 / 53.98;

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null;

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AspectRatio(
        aspectRatio: licenseCardAspectRatio,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F3),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: hasImage ? AppColors.primary : const Color(0xFFE6E6E7)),
          ),
          clipBehavior: Clip.antiAlias,
          child: hasImage
              ? Image.file(file!, fit: BoxFit.cover)
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_a_photo_outlined, size: 30, color: AppColors.secondary),
                      const SizedBox(height: 8),
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54, fontSize: 13),
                      ),
                      const Text(
                        'Tap to take a photo',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _SelfieTile extends StatelessWidget {
  const _SelfieTile({
    required this.file,
    required this.onTap,
    this.disabled = false,
  });

  final File? file;
  final bool disabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null;

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: 160,
        height: 200,
        // A true ellipse via ShapeDecoration/OvalBorder — matches the
        // same oval treatment used for the commuter/driver face frames
        // elsewhere (BorderRadius.circular can't produce a real oval on
        // a non-square box, only a rounded "stadium" shape).
        decoration: ShapeDecoration(
          color: hasImage ? AppColors.qrTileBg : const Color(0xFFF2F2F3),
          shape: OvalBorder(
            side: BorderSide(color: hasImage ? AppColors.primary : const Color(0xFFE6E6E7), width: hasImage ? 2 : 1),
          ),
        ),
        child: ClipOval(
          child: hasImage
              ? Image.file(file!, fit: BoxFit.cover)
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.face_retouching_natural_rounded, size: 30, color: AppColors.secondary),
                      const SizedBox(height: 8),
                      const Text(
                        'Selfie',
                        style: TextStyle(fontWeight: FontWeight.w800, color: Colors.black54, fontSize: 13),
                      ),
                      const Text(
                        'Tap to take a photo',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black38, fontSize: 11),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}
