import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

/// A small jeepney icon riding back and forth along a dashed road line —
/// the loading indicator shared by [LoadingScreen] and [SigningOutScreen]
/// in place of a generic spinner. One [AnimationController] drives both the
/// jeep's ping-pong position and the dash scroll, so the two stay in sync
/// (two dash-scroll cycles per one jeep round-trip, matching the design's
/// own 0.9s/1.8s ratio) without needing separate tickers.
class RollingRoadLoader extends StatefulWidget {
  const RollingRoadLoader({super.key});

  @override
  State<RollingRoadLoader> createState() => _RollingRoadLoaderState();
}

class _RollingRoadLoaderState extends State<RollingRoadLoader>
    with SingleTickerProviderStateMixin {
  static const _width = 108.0;
  static const _jeepSize = 17.0;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        // Triangular 0 -> 1 -> 0 wave over one full cycle, eased — the jeep
        // slides to the right edge at the cycle's midpoint, then back.
        final jeepLinear = t < 0.5 ? t * 2 : 2 - t * 2;
        final jeepProgress = Curves.easeInOut.transform(jeepLinear);
        // Two dash-scroll loops per jeep round-trip.
        final dashPhase = (t * 2) % 1.0;

        return SizedBox(
          width: _width,
          height: _jeepSize,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: (_jeepSize - 3) / 2,
                left: 0,
                right: 0,
                child: CustomPaint(
                  size: const Size(_width, 3),
                  painter: _DashedRoadPainter(
                    phase: dashPhase,
                    color: AppColors.onPrimary.withValues(alpha: 0.55),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: jeepProgress * (_width - _jeepSize),
                child: Container(
                  width: _jeepSize,
                  height: _jeepSize,
                  decoration: const BoxDecoration(
                    color: AppColors.onPrimary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.directions_bus_filled_rounded,
                    size: 10,
                    color: AppColors.splashBackground,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashedRoadPainter extends CustomPainter {
  static const _dashWidth = 10.0;
  static const _gapWidth = 10.0;
  static const _period = _dashWidth + _gapWidth;

  final double phase;
  final Color color;

  const _DashedRoadPainter({required this.phase, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.height
      ..strokeCap = StrokeCap.round;
    final y = size.height / 2;
    var x = -phase * _period;
    while (x < size.width) {
      final start = x.clamp(0.0, size.width);
      final end = (x + _dashWidth).clamp(0.0, size.width);
      if (end > start) {
        canvas.drawLine(Offset(start, y), Offset(end, y), paint);
      }
      x += _period;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRoadPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.color != color;
}
