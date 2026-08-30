import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants/app_colors.dart';
import '../utils/platform_utils.dart';

enum CaptureGuideShape { rectangle, oval }

/// Opens a full-screen live camera view with a guide overlay (a rectangle
/// for ID documents, an oval for a face/selfie) drawn over the feed, so the
/// user lines up the shot correctly before capturing — instead of aiming
/// blind in the phone's own separate camera app via image_picker and only
/// finding out afterward whether it lined up.
///
/// Returns the captured photo as a [File], or null if the user backed out
/// without capturing one. The calling screen is still responsible for its
/// own "review this photo" step (every screen that uses this already has
/// one, in the same rectangle/oval shape as the guide here) — this widget
/// only owns the live-aiming step, not a second review cycle on top of it.
class InAppCameraCapture {
  const InAppCameraCapture._();

  static Future<File?> capture(
    BuildContext context, {
    required CameraLensDirection lensDirection,
    required CaptureGuideShape guideShape,
    required String instruction,
    double guideAspectRatio = 1,
  }) async {
    // camera has no reliable desktop (Windows/Linux/macOS) support in this
    // app — same reasoning as isDesktopPlatform's other use sites — so
    // desktop falls back to a plain file pick, which is enough to keep the
    // flow usable for local testing.
    if (isDesktopPlatform) {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
      return picked == null ? null : File(picked.path);
    }

    if (!context.mounted) return null;
    return Navigator.of(context).push<File?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _InAppCameraScreen(
          lensDirection: lensDirection,
          guideShape: guideShape,
          instruction: instruction,
          guideAspectRatio: guideAspectRatio,
        ),
      ),
    );
  }
}

enum _CameraStatus { initializing, ready, denied, unavailable }

class _InAppCameraScreen extends StatefulWidget {
  const _InAppCameraScreen({
    required this.lensDirection,
    required this.guideShape,
    required this.instruction,
    required this.guideAspectRatio,
  });

  final CameraLensDirection lensDirection;
  final CaptureGuideShape guideShape;
  final String instruction;
  final double guideAspectRatio;

  @override
  State<_InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<_InAppCameraScreen> {
  CameraController? _controller;
  _CameraStatus _status = _CameraStatus.initializing;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _setUp();
  }

  // Deliberately doesn't use permission_handler to request/check camera
  // access up front — CameraController.initialize() below already
  // triggers the native OS permission prompt itself on both Android and
  // iOS, so a separate request is redundant. Denial is instead detected
  // from the CameraException it throws.
  Future<void> _setUp() async {
    setState(() => _status = _CameraStatus.initializing);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (!mounted) return;
        setState(() => _status = _CameraStatus.unavailable);
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == widget.lensDirection,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        unawaited(controller.dispose());
        return;
      }
      setState(() {
        _controller = controller;
        _status = _CameraStatus.ready;
      });
    } on CameraException catch (e) {
      if (!mounted) return;
      const deniedCodes = {'CameraAccessDenied', 'CameraAccessDeniedWithoutPrompt', 'CameraAccessRestricted'};
      setState(() => _status = deniedCodes.contains(e.code) ? _CameraStatus.denied : _CameraStatus.unavailable);
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CameraStatus.unavailable);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _handleCapture() async {
    final controller = _controller;
    if (controller == null || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      final file = await controller.takePicture();
      if (!mounted) return;
      Navigator.of(context).pop(File(file.path));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCapturing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: switch (_status) {
        _CameraStatus.initializing => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
        _CameraStatus.denied => _CameraBlockedView(
            icon: Icons.camera_alt_outlined,
            title: 'Camera access needed',
            message:
                'ManibelaApp needs camera access to capture this photo. '
                'Enable it in your phone\'s Settings, then try again.',
            primaryLabel: 'Try Again',
            onPrimary: _setUp,
          ),
        _CameraStatus.unavailable => _CameraBlockedView(
            icon: Icons.no_photography_outlined,
            title: 'Camera unavailable',
            message: 'We could not access a camera on this device. Please try again.',
            primaryLabel: 'Close',
            onPrimary: () => Navigator.of(context).pop(),
          ),
        _CameraStatus.ready => _LiveCaptureView(
            controller: _controller!,
            guideShape: widget.guideShape,
            guideAspectRatio: widget.guideAspectRatio,
            instruction: widget.instruction,
            isCapturing: _isCapturing,
            isFrontCamera: widget.lensDirection == CameraLensDirection.front,
            onCapture: _handleCapture,
          ),
      },
    );
  }
}

class _CameraBlockedView extends StatelessWidget {
  const _CameraBlockedView({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: Colors.white54),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPrimary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  primaryLabel,
                  style: const TextStyle(color: AppColors.onPrimary, fontWeight: FontWeight.w800, fontSize: 14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveCaptureView extends StatelessWidget {
  const _LiveCaptureView({
    required this.controller,
    required this.guideShape,
    required this.guideAspectRatio,
    required this.instruction,
    required this.isCapturing,
    required this.isFrontCamera,
    required this.onCapture,
  });

  final CameraController controller;
  final CaptureGuideShape guideShape;
  final double guideAspectRatio;
  final String instruction;
  final bool isCapturing;
  final bool isFrontCamera;
  final VoidCallback onCapture;

  // Fills the whole screen the way a real camera app's viewfinder does,
  // cropping the overflow — CameraPreview alone only ever renders at its
  // native aspect ratio (a landscape sensor ratio like 4:3 or 16:9, wrapped
  // in its own internal AspectRatio), which on a portrait phone screen
  // leaves large empty bars above and below rather than filling it. A
  // hand-rolled Transform.scale factor was tried first and was simply
  // wrong — verified by hand: for a ~0.46 (portrait) screen aspect against
  // a ~1.78 (16:9) camera aspect, that formula computed a ~1.2x scale
  // when ~3.8x is what's actually needed to cover the screen. FittedBox
  // with BoxFit.cover computes this correctly regardless of the specific
  // ratios involved, so there's no formula here to get wrong.
  Widget _scaledPreview() {
    final preview = FittedBox(
      fit: BoxFit.cover,
      child: SizedBox(
        // The absolute number is arbitrary — FittedBox only cares about
        // the ratio it establishes (matching the camera's own), not the
        // literal size.
        width: 100,
        height: 100 / controller.value.aspectRatio,
        child: CameraPreview(controller),
      ),
    );
    return SizedBox.expand(
      // Mirrors the front camera so it reads as a mirror while lining up
      // a selfie, matching how every other camera app previews it.
      child: isFrontCamera
          ? Transform(
              alignment: Alignment.center,
              transform: Matrix4.rotationY(math.pi),
              child: preview,
            )
          : preview,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.biggest;
          final center = size.center(Offset.zero);
          late final Rect guideRect;
          if (guideShape == CaptureGuideShape.oval) {
            final width = size.width * 0.62;
            final height = width * 1.25;
            guideRect = Rect.fromCenter(center: center, width: width, height: height);
          } else {
            final width = size.width * 0.85;
            final height = width / guideAspectRatio;
            guideRect = Rect.fromCenter(center: center, width: width, height: height);
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              _scaledPreview(),
              CustomPaint(
                painter: _GuideOverlayPainter(shape: guideShape, guideRect: guideRect),
                size: size,
              ),
              Positioned(
                left: 4,
                top: 4,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                ),
              ),
              Positioned(
                left: 24,
                right: 24,
                bottom: 36,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      instruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(height: 18),
                    GestureDetector(
                      onTap: isCapturing ? null : onCapture,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: Colors.white54, width: 4),
                        ),
                        alignment: Alignment.center,
                        child: isCapturing
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(strokeWidth: 2.6, color: AppColors.primary),
                              )
                            : Container(
                                width: 58,
                                height: 58,
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _GuideOverlayPainter extends CustomPainter {
  _GuideOverlayPainter({required this.shape, required this.guideRect});

  final CaptureGuideShape shape;
  final Rect guideRect;

  @override
  void paint(Canvas canvas, Size size) {
    final dimPaint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final borderPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final guidePath = shape == CaptureGuideShape.oval
        ? (Path()..addOval(guideRect))
        : (Path()..addRRect(RRect.fromRectAndRadius(guideRect, const Radius.circular(14))));

    canvas.drawPath(Path.combine(PathOperation.difference, outer, guidePath), dimPaint);
    canvas.drawPath(guidePath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _GuideOverlayPainter oldDelegate) =>
      oldDelegate.shape != shape || oldDelegate.guideRect != guideRect;
}
