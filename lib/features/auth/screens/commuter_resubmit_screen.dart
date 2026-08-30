import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/widgets/in_app_camera_capture.dart';
import 'commuter_verification_status_screen.dart';

const List<String> _resubmitIdTypeOptions = [
  'Philippine National ID (PhilSys)',
  "Driver's License",
  'Passport',
  'UMID',
  "Voter's ID",
  'Postal ID',
];

/// Reached from CommuterVerificationStatusScreen's REJECTED state — the
/// one retry path for an account that failed ID/face verification.
/// Unlike a driver's own resubmit (an authenticated /me endpoint, since a
/// driver can still log in), a REJECTED commuter has no session at all
/// (see POST /login, which withholds the token until APPROVED) — so this
/// re-proves mobileNumber+password on the submit call itself, exactly
/// like POST /login/POST /forgot-password already do, rather than
/// carrying a token in from anywhere.
class CommuterResubmitScreen extends StatefulWidget {
  const CommuterResubmitScreen({super.key, required this.mobileNumber});

  /// Already normalized to `+63XXXXXXXXXX`.
  final String mobileNumber;

  @override
  State<CommuterResubmitScreen> createState() => _CommuterResubmitScreenState();
}

class _CommuterResubmitScreenState extends State<CommuterResubmitScreen> {
  final TextEditingController _passwordController = TextEditingController();
  bool _obscurePassword = true;

  String? _selectedId;
  File? _frontImage;
  File? _backImage;
  File? _selfieImage;
  bool _isPickingImage = false;
  bool _isSubmitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _pickImage({required bool isFront}) async {
    if (_isPickingImage) return;
    setState(() => _isPickingImage = true);
    try {
      final File? picked = await InAppCameraCapture.capture(
        context,
        lensDirection: CameraLensDirection.back,
        guideShape: CaptureGuideShape.rectangle,
        guideAspectRatio: 85.6 / 53.98, // CR80 card ratio, same as sign-up's own ID tiles.
        instruction: isFront
            ? 'Line up the front of your ID within the frame'
            : 'Line up the back of your ID within the frame',
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

  bool get _canSubmit =>
      _selectedId != null &&
      _passwordController.text.isNotEmpty &&
      _frontImage != null &&
      _backImage != null &&
      _selfieImage != null &&
      !_isSubmitting;

  Future<void> _handleSubmit() async {
    if (!_canSubmit) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final response = await ApiClient.uploadFiles(
        '/api/commuter/resubmit',
        files: {
          'front': _frontImage!.path,
          'back': _backImage!.path,
          'selfie': _selfieImage!.path,
        },
        fields: {
          'mobileNumber': widget.mobileNumber,
          'password': _passwordController.text,
          'idType': _selectedId!,
        },
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => CommuterVerificationStatusScreen(
            status: response['verificationStatus'] as String?,
            mobileNumber: widget.mobileNumber,
          ),
        ),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = 'Something went wrong. Please try again.';
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
        foregroundColor: Colors.black,
        title: const Text(
          'Resubmit Verification',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.settingsTileBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline_rounded, color: AppColors.settingsIconColor, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Confirm your password and submit clearer photos of your ID and a new selfie.",
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.settingsIconColor),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text('Password', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black)),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Enter your password',
                hintStyle: const TextStyle(color: Colors.black38, fontWeight: FontWeight.w600, fontSize: 13),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 20),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFEDEDED)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFEDEDED)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.logoBlue, width: 1.5),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Government ID Type',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _selectedId,
              onChanged: (value) => setState(() => _selectedId = value),
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black54),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black),
              decoration: InputDecoration(
                hintText: 'Select ID type',
                hintStyle: const TextStyle(color: Colors.black38, fontWeight: FontWeight.w600, fontSize: 13),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFEDEDED)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: Color(0xFFEDEDED)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: AppColors.logoBlue, width: 1.5),
                ),
              ),
              items: _resubmitIdTypeOptions
                  .map((label) => DropdownMenuItem(value: label, child: Text(label)))
                  .toList(),
            ),
            const SizedBox(height: 20),
            const Text(
              'Upload ID Photos',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black),
            ),
            const SizedBox(height: 10),
            _ResubmitPhotoTile(
              label: 'Front of ID',
              file: _frontImage,
              disabled: _isPickingImage,
              onTap: () => _pickImage(isFront: true),
            ),
            const SizedBox(height: 12),
            _ResubmitPhotoTile(
              label: 'Back of ID',
              file: _backImage,
              disabled: _isPickingImage,
              onTap: () => _pickImage(isFront: false),
            ),
            const SizedBox(height: 20),
            const Text('Selfie', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black)),
            const SizedBox(height: 10),
            Center(child: _ResubmitSelfieTile(file: _selfieImage, disabled: _isPickingImage, onTap: _pickSelfie)),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE23F3F)),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _canSubmit ? _handleSubmit : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
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
                        'Resubmit',
                        style: TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResubmitPhotoTile extends StatelessWidget {
  const _ResubmitPhotoTile({
    required this.label,
    required this.file,
    required this.onTap,
    this.disabled = false,
  });

  final String label;
  final File? file;
  final bool disabled;
  final VoidCallback onTap;

  static const double _idCardAspectRatio = 85.6 / 53.98;

  @override
  Widget build(BuildContext context) {
    final hasImage = file != null;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AspectRatio(
        aspectRatio: _idCardAspectRatio,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: hasImage ? AppColors.qrTileBg : const Color(0xFFF5F6F8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(width: hasImage ? 2 : 1, color: hasImage ? AppColors.primary : const Color(0xFFEDEDED)),
          ),
          child: hasImage
              ? Image.file(file!, fit: BoxFit.cover)
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.badge_outlined, color: Colors.black38, size: 30),
                      const SizedBox(height: 6),
                      Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.black45)),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _ResubmitSelfieTile extends StatelessWidget {
  const _ResubmitSelfieTile({required this.file, required this.onTap, this.disabled = false});

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
        decoration: ShapeDecoration(
          color: hasImage ? AppColors.qrTileBg : const Color(0xFFF2F2F3),
          shape: OvalBorder(
            side: BorderSide(color: hasImage ? AppColors.primary : const Color(0xFFE6E6E7), width: hasImage ? 2 : 1),
          ),
        ),
        child: ClipOval(
          child: hasImage
              ? Image.file(file!, fit: BoxFit.cover)
              : const Center(
                  child: Icon(Icons.face_retouching_natural_rounded, color: Colors.black26, size: 30),
                ),
        ),
      ),
    );
  }
}
