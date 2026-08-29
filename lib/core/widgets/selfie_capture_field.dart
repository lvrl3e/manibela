import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../constants/app_colors.dart';
import '../utils/platform_utils.dart';

/// Camera-only selfie capture in an oval frame — shared by commuter
/// face verification (a dedicated full-screen step) and driver license
/// submission (one tile alongside the license photos), since both need
/// the exact same "prove this is a live selfie, not an old photo"
/// behavior, previously only implemented once as commuter's own private
/// `_FaceFrame`.
///
/// Exposes [capture]/[retake] via a [GlobalKey] rather than owning its
/// own submit button — each screen's own Capture/Retake/Confirm buttons
/// (or, for driver, a single shared Submit button covering multiple
/// fields) call into this, so the two screens can keep their own
/// different layouts around the same capture behavior.
class SelfieCaptureField extends StatefulWidget {
  const SelfieCaptureField({
    super.key,
    required this.onChanged,
    this.width = 240,
    this.height = 300,
  });

  /// Called with the captured file, or null after a retake.
  final ValueChanged<File?> onChanged;
  final double width;
  final double height;

  @override
  State<SelfieCaptureField> createState() => SelfieCaptureFieldState();
}

class SelfieCaptureFieldState extends State<SelfieCaptureField> {
  final ImagePicker _picker = ImagePicker();

  File? _capturedPhoto;
  bool _isCapturing = false;

  bool get isCaptured => _capturedPhoto != null;

  Future<void> capture() async {
    if (_isCapturing) return;

    setState(() => _isCapturing = true);

    try {
      // Front camera, since this is a selfie for identity verification —
      // not a photo library pick, so the user can't submit an old/
      // unrelated photo the way ID/license photos allow. Desktop is the
      // one exception: image_picker has no webcam support there at all
      // (see isDesktopPlatform), so ImageSource.camera would just throw
      // — fall back to a file pick so the flow is at least usable for
      // local testing.
      final XFile? picked = await _picker.pickImage(
        source: isDesktopPlatform ? ImageSource.gallery : ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        imageQuality: 85,
      );

      if (!mounted) return;

      if (picked == null) {
        // User backed out of the camera without taking a photo.
        setState(() => _isCapturing = false);
        return;
      }

      final file = File(picked.path);
      setState(() {
        _capturedPhoto = file;
        _isCapturing = false;
      });
      widget.onChanged(file);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCapturing = false);
      rethrow;
    }
  }

  void retake() {
    if (_isCapturing) return; // don't allow retake mid-capture
    setState(() => _capturedPhoto = null);
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final isCaptured = _capturedPhoto != null;

    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: widget.width,
          height: widget.height,
          // A true ellipse via ShapeDecoration/OvalBorder — BorderRadius.circular
          // can only round corners, so on a non-square box like this one it
          // produces a flat-sided "stadium" shape rather than a real oval, no
          // matter how large the radius. ClipOval below matches the same math
          // for the content inside, so the photo and its border are cut
          // identically.
          decoration: ShapeDecoration(
            color: isCaptured ? AppColors.qrTileBg : const Color(0xFFECEDEF),
            shape: const OvalBorder(
              side: BorderSide(color: AppColors.primary, width: 3),
            ),
          ),
          child: ClipOval(
            child: isCaptured
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.file(_capturedPhoto!, fit: BoxFit.cover),
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
        ),
        if (_isCapturing)
          const CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
      ],
    );
  }
}
