import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
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
    // A blink-detection liveness check before the selfie is accepted —
    // nothing currently stops someone holding up a printed photo or
    // another screen to the camera and having it read as a match
    // otherwise, since the face-match step (see backend/src/lib/
    // faceMatch.ts) only ever compares two static photos. Only meant for
    // a genuine selfie (guideShape.oval, front camera) — never pass this
    // for an ID/license document capture, which has no face to blink.
    bool requireLiveness = false,
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
          requireLiveness: requireLiveness,
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
    required this.requireLiveness,
  });

  final CameraLensDirection lensDirection;
  final CaptureGuideShape guideShape;
  final String instruction;
  final double guideAspectRatio;
  final bool requireLiveness;

  @override
  State<_InAppCameraScreen> createState() => _InAppCameraScreenState();
}

class _InAppCameraScreenState extends State<_InAppCameraScreen> {
  CameraController? _controller;
  _CameraStatus _status = _CameraStatus.initializing;
  bool _isCapturing = false;

  // --- Liveness (see InAppCameraCapture.capture's requireLiveness doc) ---
  FaceDetector? _faceDetector;
  bool _isProcessingFrame = false; // drops a frame rather than queueing behind a slow one
  bool _eyesSeenClosed = false; // becomes true once a frame reads both eyes as closed
  bool _livenessConfirmed = false;
  Timer? _livenessTimeoutTimer;
  // After this long without a detected blink, reveal a manual fallback —
  // never leave someone permanently stuck behind a check that isn't
  // working for them (bad lighting, a face shape the model reads
  // differently, or simply this feature not having been exercised on
  // their exact device before).
  static const _livenessTimeout = Duration(seconds: 15);
  bool _livenessTimedOut = false;

  bool get _needsLivenessGate => widget.requireLiveness && !_livenessConfirmed && !_livenessTimedOut;

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
        // Only matters for the liveness stream (see
        // _inputImageFromCameraImage) — nv21/bgra8888 are what ML Kit
        // expects and, critically, are the formats that make the camera
        // plugin deliver a single image plane instead of multiple,
        // which that conversion depends on. Left as the plugin's own
        // default for a plain document capture, which never reads the
        // stream at all.
        imageFormatGroup: widget.requireLiveness
            ? (Platform.isAndroid ? ImageFormatGroup.nv21 : ImageFormatGroup.bgra8888)
            : null,
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
      if (widget.requireLiveness) _startLivenessCheck(controller);
    } on CameraException catch (e) {
      if (!mounted) return;
      const deniedCodes = {'CameraAccessDenied', 'CameraAccessDeniedWithoutPrompt', 'CameraAccessRestricted'};
      setState(() => _status = deniedCodes.contains(e.code) ? _CameraStatus.denied : _CameraStatus.unavailable);
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = _CameraStatus.unavailable);
    }
  }

  // Runs face detection on the live preview stream (not the eventual
  // captured photo — liveness has to come from something changing over
  // time, which a single still frame can't prove) looking for a
  // close-then-open blink. If anything here fails to even get started
  // (model load, stream start, an unsupported image format on this
  // device), it degrades to the same manual-fallback path as a timeout —
  // never blocks capture outright over a liveness-detection problem.
  Future<void> _startLivenessCheck(CameraController controller) async {
    try {
      _faceDetector = FaceDetector(
        options: FaceDetectorOptions(enableClassification: true, performanceMode: FaceDetectorMode.fast),
      );
      await controller.startImageStream(_processCameraImage);
      _livenessTimeoutTimer = Timer(_livenessTimeout, () {
        if (!mounted || _livenessConfirmed) return;
        setState(() => _livenessTimedOut = true);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _livenessTimedOut = true);
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    if (_isProcessingFrame || _livenessConfirmed || !mounted) return;
    _isProcessingFrame = true;
    try {
      final controller = _controller;
      final detector = _faceDetector;
      if (controller == null || detector == null) return;

      final inputImage = _inputImageFromCameraImage(image, controller.description);
      if (inputImage == null) return;

      final faces = await detector.processImage(inputImage);
      if (faces.isEmpty || _livenessConfirmed || !mounted) return;

      final face = faces.first;
      final leftOpen = face.leftEyeOpenProbability;
      final rightOpen = face.rightEyeOpenProbability;
      if (leftOpen == null || rightOpen == null) return;
      final avgOpen = (leftOpen + rightOpen) / 2;

      if (!_eyesSeenClosed) {
        if (avgOpen < 0.35) _eyesSeenClosed = true;
      } else if (avgOpen > 0.65) {
        // Eyes were closed on an earlier frame and are open again now —
        // a completed blink. Stop watching the stream and capture
        // immediately, same as a manual shutter tap.
        _livenessConfirmed = true;
        unawaited(_finishLivenessCheck());
        if (mounted) setState(() {});
        unawaited(_handleCapture());
      }
    } catch (_) {
      // A single bad frame isn't fatal — the next one just gets tried
      // normally. Only the setup failure above (or the timeout) gives up
      // on liveness entirely.
    } finally {
      _isProcessingFrame = false;
    }
  }

  Future<void> _finishLivenessCheck() async {
    _livenessTimeoutTimer?.cancel();
    _livenessTimeoutTimer = null;
    final controller = _controller;
    try {
      if (controller != null && controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (_) {
      // Best-effort — takePicture() below will surface any real problem.
    }
  }

  // Converts a raw camera stream frame into ML Kit's InputImage format.
  // Deliberately assumes the capture screen stays portrait-locked (it
  // has no rotation UI) rather than tracking live device orientation —
  // under that assumption the platform-specific rotation compensation
  // this normally needs collapses to just the camera's own fixed sensor
  // angle. Requesting nv21 (Android) / bgra8888 (iOS) as the stream
  // format up front (see CameraController below) is what guarantees a
  // single image plane here, matching ML Kit's own official example.
  InputImage? _inputImageFromCameraImage(CameraImage image, CameraDescription camera) {
    final rotation = InputImageRotationValue.fromRawValue(camera.sensorOrientation);
    if (rotation == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;

    if (image.planes.length != 1) return null;
    final plane = image.planes.first;

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _livenessTimeoutTimer?.cancel();
    unawaited(_finishLivenessCheck());
    unawaited(_faceDetector?.close());
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _handleCapture() async {
    final controller = _controller;
    if (controller == null || _isCapturing) return;
    setState(() => _isCapturing = true);
    try {
      await _finishLivenessCheck();
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
            onCapture: _handleCapture,
            awaitingLiveness: _needsLivenessGate,
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
    required this.onCapture,
    required this.awaitingLiveness,
  });

  final CameraController controller;
  final CaptureGuideShape guideShape;
  final double guideAspectRatio;
  final String instruction;
  final bool isCapturing;
  final VoidCallback onCapture;
  // True only between a requireLiveness capture starting and either a
  // detected blink or the safety-valve timeout — see
  // _InAppCameraScreenState._needsLivenessGate. Swaps the shutter button
  // for a "blink to continue" prompt so tapping through without blinking
  // isn't possible under normal operation, while still guaranteeing a
  // manual way out once the timeout flips this back to false.
  final bool awaitingLiveness;

  // Fills the whole screen the way a real camera app's viewfinder does,
  // cropping the overflow — CameraPreview alone only ever renders at its
  // native aspect ratio (a landscape sensor ratio like 4:3 or 16:9, wrapped
  // in its own internal AspectRatio), which on a portrait phone screen
  // leaves large empty bars above and below rather than filling it.
  //
  // controller.value.aspectRatio is the RAW sensor ratio (width/height in
  // landscape terms, e.g. ~1.78 for 16:9) — it is not yet the shape the
  // preview should take on a portrait screen. The box FittedBox scales
  // from has to be built with that ratio *inverted* (height = width *
  // aspectRatio, not width / aspectRatio) so it's already portrait-shaped
  // (tall, not wide) going in. Getting this backwards was tried first and
  // was wrong two different ways: un-inverted with no scaling produced a
  // wide/short box letterboxed onto a portrait screen (thin strip); the
  // same un-inverted box run through BoxFit.cover instead required a
  // ~3.8x scale to fill the screen, cropping away most of the width
  // (looked "zoomed in"). Inverted, cover only needs a modest ~1.2x scale
  // — the same crop amount a real camera app's viewfinder uses.
  Widget _scaledPreview() {
    return SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          // The absolute number is arbitrary — FittedBox only cares about
          // the ratio it establishes (matching the camera's own), not the
          // literal size.
          width: 100,
          height: 100 * controller.value.aspectRatio,
          child: CameraPreview(controller),
        ),
      ),
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
                      awaitingLiveness ? 'Blink to continue' : instruction,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 6)],
                      ),
                    ),
                    const SizedBox(height: 18),
                    // While awaiting a blink, the shutter is replaced
                    // entirely (not just disabled) — tapping through
                    // without blinking shouldn't be possible under normal
                    // operation, only once the timeout hands control
                    // back via awaitingLiveness turning false.
                    if (awaitingLiveness)
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black45,
                          border: Border.all(color: Colors.white38, width: 3),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.remove_red_eye_outlined, color: Colors.white70, size: 28),
                      )
                    else
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
