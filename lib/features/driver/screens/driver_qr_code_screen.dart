import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/driver_session.dart';

/// Shows the driver's scannable ID — conductors/inspectors (or a future
/// commuter-facing verification flow) can scan this to confirm who's
/// driving. There's no backend to issue a real encoded code yet, so the
/// "QR" here is a deterministic decorative grid seeded from the driver's
/// ID — visually a QR code, but not actually decodable. Swap
/// [_QrPainter] for a real QR-generation package once a backend exists to
/// give it something meaningful to encode.
class DriverQrCodeScreen extends StatelessWidget {
  const DriverQrCodeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final driverName = DriverSession.instance.fullName ?? 'Driver';
    final driverId = DriverSession.instance.driverId ?? '—';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.06),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        AspectRatio(
                          aspectRatio: 1,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFE1E4E8)),
                            ),
                            child: CustomPaint(
                              painter: _QrPainter(seed: driverId),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          driverName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppColors.qrTileBg,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            driverId,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.qrIconColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.qrTileBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.qrTileBorder),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, color: AppColors.qrIconColor, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Show this code to conductors, inspectors, or passengers who want to verify your identity.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                              color: AppColors.qrIconColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, Color(0xFFFFDE7A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 2,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).maybePop(),
              child: const Padding(
                padding: EdgeInsets.all(13),
                child: Icon(Icons.arrow_back, size: 22, color: Colors.black87),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Your QR Code',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onPrimary,
                  ),
                ),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws a deterministic QR-look-alike grid, complete with the three
/// finder-pattern corner squares real QR codes use, seeded from [seed] so
/// the same driver always sees the same pattern.
class _QrPainter extends CustomPainter {
  final String seed;

  const _QrPainter({required this.seed});

  static const int _modules = 21;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / _modules;
    final random = Random(seed.hashCode);
    final darkPaint = Paint()..color = Colors.black;

    bool isInFinderZone(int row, int col) {
      bool inCorner(int r0, int c0) =>
          row >= r0 && row < r0 + 7 && col >= c0 && col < c0 + 7;
      return inCorner(0, 0) ||
          inCorner(0, _modules - 7) ||
          inCorner(_modules - 7, 0);
    }

    for (int row = 0; row < _modules; row++) {
      for (int col = 0; col < _modules; col++) {
        if (isInFinderZone(row, col)) continue;
        if (random.nextDouble() < 0.42) {
          canvas.drawRect(
            Rect.fromLTWH(col * cell, row * cell, cell, cell),
            darkPaint,
          );
        }
      }
    }

    void drawFinderPattern(double left, double top) {
      canvas.drawRect(Rect.fromLTWH(left, top, cell * 7, cell * 7), darkPaint);
      canvas.drawRect(
        Rect.fromLTWH(left + cell, top + cell, cell * 5, cell * 5),
        Paint()..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromLTWH(left + cell * 2, top + cell * 2, cell * 3, cell * 3),
        darkPaint,
      );
    }

    drawFinderPattern(0, 0);
    drawFinderPattern((_modules - 7) * cell, 0);
    drawFinderPattern(0, (_modules - 7) * cell);
  }

  @override
  bool shouldRepaint(covariant _QrPainter oldDelegate) => oldDelegate.seed != seed;
}
