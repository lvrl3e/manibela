import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_session.dart';
import '../../../core/utils/distance_format.dart';

/// Shown when a driver taps a waiting-passenger pin on the live map — real
/// road-network distance + ETA to that cluster via GET
/// /driver/route-to-passenger (falls back to the backend's own haversine
/// estimate if the free OSRM routing call is unavailable, see
/// routingService.ts). Deliberately has no action buttons (no
/// Navigate/Accept/Track/Request) — a driver shouldn't need to interact
/// with the phone beyond this glance.
class PassengerInfoSheet extends StatefulWidget {
  final LatLng origin;
  final LatLng destination;
  final int count;

  const PassengerInfoSheet({
    super.key,
    required this.origin,
    required this.destination,
    required this.count,
  });

  @override
  State<PassengerInfoSheet> createState() => _PassengerInfoSheetState();
}

class _PassengerInfoSheetState extends State<PassengerInfoSheet> {
  bool _isLoading = true;
  String? _error;
  int? _distanceMeters;
  int? _etaMinutes;

  @override
  void initState() {
    super.initState();
    _fetchRoute();
  }

  Future<void> _fetchRoute() async {
    final token = DriverSession.instance.authToken;
    if (token == null) {
      setState(() {
        _isLoading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    try {
      final response = await ApiClient.get(
        '/api/driver/route-to-passenger'
        '?lat=${widget.origin.latitude}&lng=${widget.origin.longitude}'
        '&passengerLat=${widget.destination.latitude}&passengerLng=${widget.destination.longitude}',
        token: token,
      );
      if (!mounted) return;
      setState(() {
        _distanceMeters = response['distanceMeters'] as int;
        _etaMinutes = response['etaMinutes'] as int;
        _isLoading = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = "Couldn't get distance right now.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFDADDE1),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: widget.count > 1 ? AppColors.logoRed.withOpacity(0.12) : AppColors.primary.withOpacity(0.16),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.groups_rounded,
                    color: widget.count > 1 ? AppColors.logoRed : AppColors.logoBlue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.count > 1 ? '${widget.count} passengers waiting' : '1 passenger waiting',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                      ),
                      const Text(
                        'Estimated pickup distance',
                        style: TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.logoBlue)),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(_error!, style: const TextStyle(fontSize: 13, color: Colors.black54)),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F6F8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatColumn(label: 'Distance', value: formatDistanceCompact(_distanceMeters!)),
                    Container(width: 1, height: 30, color: const Color(0xFFE2E4E8)),
                    _StatColumn(label: 'ETA', value: '$_etaMinutes min'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatColumn extends StatelessWidget {
  final String label;
  final String value;
  const _StatColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
