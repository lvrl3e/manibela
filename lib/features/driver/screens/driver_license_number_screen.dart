import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_session.dart';
import '../../../core/utils/platform_utils.dart';

enum _PhotoAction { camera, gallery }

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
        return 'Submit clear photos of the front and back of your driver\'s license. An admin will review them and verify your license number.';
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

    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            if (!isDesktopPlatform)
              ListTile(
                leading: const Icon(Icons.photo_camera_rounded),
                title: const Text('Take Photo'),
                onTap: () => Navigator.pop(sheetContext, _PhotoAction.camera),
              ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(sheetContext, _PhotoAction.gallery),
            ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;

    setState(() => _isPickingImage = true);
    try {
      final source = action == _PhotoAction.camera ? ImageSource.camera : ImageSource.gallery;
      final picker = ImagePicker();
      final XFile? picked = await picker.pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 85,
      );
      if (picked == null || !mounted) return;

      setState(() {
        if (isFront) {
          _frontImage = File(picked.path);
        } else {
          _backImage = File(picked.path);
        }
      });
    } finally {
      if (mounted) setState(() => _isPickingImage = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (_frontImage == null || _backImage == null) return;

    setState(() => _isSubmitting = true);

    try {
      await ApiClient.uploadFiles(
        '/api/driver/me/license-photo',
        files: {
          'licenseFront': _frontImage!.path,
          'licenseBack': _backImage!.path,
        },
        token: DriverSession.instance.authToken,
      );

      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _frontImage = null;
        _backImage = null;
        _status = 'PENDING';
        _licenseNumber = null;
      });

      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Submitted'),
          content: const Text(
            "Your license photos have been submitted. An admin will review them and verify your license number.",
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
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: (_frontImage == null || _backImage == null || _isSubmitting)
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

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null;

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Container(
        width: double.infinity,
        height: 160,
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
                      'Tap to upload or take a photo',
                      style: TextStyle(fontWeight: FontWeight.w600, color: Colors.black38, fontSize: 11),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
