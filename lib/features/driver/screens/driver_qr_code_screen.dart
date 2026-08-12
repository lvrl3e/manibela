import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/qr_constants.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_session.dart';

/// Shows the driver's scannable QR code — conductors/inspectors or a
/// commuter's booking flow can scan this to confirm who's driving. The QR
/// encodes an opaque token issued by the backend (`/api/driver/me/qr-token`),
/// not the driverId directly, so a photo of it can't just be forged by
/// writing a plausible-looking ID — only a token the backend actually
/// issued verifies via `/api/driver/verify-qr/:token`.
class DriverQrCodeScreen extends StatefulWidget {
  const DriverQrCodeScreen({super.key});

  @override
  State<DriverQrCodeScreen> createState() => _DriverQrCodeScreenState();
}

class _DriverQrCodeScreenState extends State<DriverQrCodeScreen> {
  String? _qrToken;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadQrToken();
  }

  Future<void> _loadQrToken() async {
    // Permanent for the account's lifetime — once cached on this device,
    // never needs fetching again.
    final cached = DriverSession.instance.qrToken;
    if (cached != null) {
      setState(() {
        _qrToken = cached;
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final response = await ApiClient.get(
        '/api/driver/me/qr-token',
        token: DriverSession.instance.authToken,
      );
      final qrToken = response['qrToken'] as String;
      await DriverSession.instance.cacheQrToken(qrToken);

      if (!mounted) return;
      setState(() {
        _qrToken = qrToken;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    }
  }

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
                            child: _buildQrContent(),
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

  Widget _buildQrContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 32),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: _loadQrToken, child: const Text('Retry')),
          ],
        ),
      );
    }

    return QrImageView(
      data: '$kDriverQrPrefix$_qrToken',
      version: QrVersions.auto,
      backgroundColor: Colors.white,
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
