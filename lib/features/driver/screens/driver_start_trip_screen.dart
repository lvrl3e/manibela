import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/driver_session.dart';

/// The only two routes this fleet actually services.
const List<String> kDriverRoutes = [
  'Pasig – Quiapo',
  'Quiapo – Pasig',
];

class DriverStartTripResult {
  final String route;
  final String plateNumber;

  const DriverStartTripResult({required this.route, required this.plateNumber});
}

/// Full-screen "Start Trip" flow: pick which of the two routes to
/// broadcast, glance at where passengers are currently waiting on a real
/// live map, then confirm. The vehicle plate is shown but not editable —
/// it's fixed to whatever's on file for this driver's account.
class DriverStartTripScreen extends StatefulWidget {
  final LatLng currentLocation;
  final bool hasRealFix;

  const DriverStartTripScreen({
    super.key,
    required this.currentLocation,
    required this.hasRealFix,
  });

  @override
  State<DriverStartTripScreen> createState() => _DriverStartTripScreenState();
}

class _DriverStartTripScreenState extends State<DriverStartTripScreen> {
  String? _selectedRoute;
  final MapController _mapController = MapController();

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  // A few nearby points, offset from the current location, standing in for
  // passengers waiting along the route until a real feed is wired up.
  List<_WaitingStop> get _waitingStops => [
        _WaitingStop(
          point: LatLng(widget.currentLocation.latitude + 0.004, widget.currentLocation.longitude + 0.003),
          count: 5,
        ),
        _WaitingStop(
          point: LatLng(widget.currentLocation.latitude - 0.003, widget.currentLocation.longitude - 0.004),
          count: 8,
        ),
        _WaitingStop(
          point: LatLng(widget.currentLocation.latitude + 0.002, widget.currentLocation.longitude - 0.005),
          count: 3,
        ),
      ];

  void _confirm() {
    if (_selectedRoute == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a route to broadcast.')),
      );
      return;
    }
    final plate = DriverSession.instance.plateNumber ?? '—';
    Navigator.pop(context, DriverStartTripResult(route: _selectedRoute!, plateNumber: plate));
  }

  @override
  Widget build(BuildContext context) {
    final plate = DriverSession.instance.plateNumber ?? '—';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Route', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (int i = 0; i < kDriverRoutes.length; i++)
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: i == 0 ? 8 : 0),
                            child: _RouteChoiceChip(
                              label: kDriverRoutes[i],
                              selected: _selectedRoute == kDriverRoutes[i],
                              onTap: () => setState(() => _selectedRoute = kDriverRoutes[i]),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF2F2F3),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE6E6E7)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.directions_car_filled_rounded, size: 18, color: AppColors.textSecondary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text('Vehicle Plate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87)),
                        ),
                        Text(plate, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                        const SizedBox(width: 6),
                        const Icon(Icons.lock_outline_rounded, size: 14, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: const Color(0xFFE5E7EB),
                    child: Stack(
                    children: [
                      Positioned.fill(
                        child: FlutterMap(
                        mapController: _mapController,
                        options: MapOptions(
                          initialCenter: widget.currentLocation,
                          initialZoom: 15,
                          minZoom: 3,
                          maxZoom: 19,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.manibel.app',
                            maxZoom: 19,
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: widget.currentLocation,
                                width: 24,
                                height: 24,
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: widget.hasRealFix ? AppColors.logoBlue : Colors.black38,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 3),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (widget.hasRealFix ? AppColors.logoBlue : Colors.black38).withOpacity(0.4),
                                        blurRadius: 8,
                                        spreadRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              for (final stop in _waitingStops)
                                Marker(
                                  point: stop.point,
                                  width: 34,
                                  height: 34,
                                  child: _WaitingStopPin(count: stop.count),
                                ),
                            ],
                          ),
                        ],
                        ),
                      ),
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.92),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.groups_rounded, size: 14, color: AppColors.logoRed),
                              SizedBox(width: 4),
                              Text(
                                'Passengers waiting nearby',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: const Text(
                    'Start Trip',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.onPrimary),
                  ),
                ),
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
                  'Start Trip',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.onPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  'See waiting passengers before you go',
                  style: TextStyle(fontSize: 10, color: Colors.black.withOpacity(0.55)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RouteChoiceChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RouteChoiceChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        borderRadius: BorderRadius.circular(13),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? AppColors.primary : const Color(0xFFE1E4E8),
              width: selected ? 1.5 : 1,
            ),
            color: selected ? AppColors.qrTileBorder : AppColors.qrTileBg,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? AppColors.onPrimary : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}

class _WaitingStop {
  final LatLng point;
  final int count;

  const _WaitingStop({required this.point, required this.count});
}

class _WaitingStopPin extends StatelessWidget {
  final int count;

  const _WaitingStopPin({required this.count});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 17,
      backgroundColor: AppColors.logoRed,
      child: CircleAvatar(
        radius: 15,
        backgroundColor: AppColors.splashBackground,
        child: Text(
          '$count',
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
    );
  }
}
