import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import 'driver_history_screen.dart';
import 'driver_notifications_screen.dart';

/// The dedicated "on trip" screen — shown full-screen for as long as a
/// trip is active. Tracks the driver's live position (the vehicle marker
/// actually moves as they drive), shows where passengers are waiting, and
/// is the only place "End Trip" lives once a trip has started.
class DriverTripInProgressScreen extends StatefulWidget {
  final String route;
  final String plateNumber;
  final DateTime startTime;
  final LatLng initialLocation;

  const DriverTripInProgressScreen({
    super.key,
    required this.route,
    required this.plateNumber,
    required this.startTime,
    required this.initialLocation,
  });

  @override
  State<DriverTripInProgressScreen> createState() => _DriverTripInProgressScreenState();
}

class _DriverTripInProgressScreenState extends State<DriverTripInProgressScreen> {
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionSubscription;
  Timer? _elapsedTimer;

  late LatLng _currentLocation = widget.initialLocation;
  bool _hasRealFix = false;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _elapsed = DateTime.now().difference(widget.startTime);
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(widget.startTime));
    });
    _startTracking();
  }

  Future<void> _startTracking() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        return;
      }

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).listen((position) {
        if (!mounted) return;
        final updated = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentLocation = updated;
          _hasRealFix = true;
        });
        // Fixed zoom (not read from _mapController.camera) — the camera
        // isn't guaranteed to be attached yet the first time a position
        // update arrives, and reading it too early throws.
        try {
          _mapController.move(updated, 16);
        } catch (_) {
          // Map not attached yet — it'll pick up the new center on its
          // own next build via initialCenter.
        }
      });
    } catch (_) {
      // No live tracking available — the map still shows the last known
      // (initial) position.
    }
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _elapsedTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  // A few nearby points, offset from the current location, standing in for
  // passengers waiting along the route until a real feed is wired up.
  List<_WaitingStop> get _waitingStops => [
        _WaitingStop(
          point: LatLng(widget.initialLocation.latitude + 0.004, widget.initialLocation.longitude + 0.003),
          count: 5,
        ),
        _WaitingStop(
          point: LatLng(widget.initialLocation.latitude - 0.003, widget.initialLocation.longitude - 0.004),
          count: 8,
        ),
        _WaitingStop(
          point: LatLng(widget.initialLocation.latitude + 0.002, widget.initialLocation.longitude - 0.005),
          count: 3,
        ),
      ];

  String get _elapsedLabel {
    final h = _elapsed.inHours;
    final m = _elapsed.inMinutes % 60;
    final s = _elapsed.inSeconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '${h}h ${mm}m' : '$mm:$ss';
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour12:$minute $period';
  }

  Future<void> _handleEndTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text('End this trip?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        content: Text(
          'You are about to stop broadcasting ${widget.route}.',
          style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500),
        ),
        actionsPadding: const EdgeInsets.only(right: 12, bottom: 8),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorRed,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('End Trip', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final now = DateTime.now();
    final durationLabel = _formatDuration(now.difference(widget.startTime));

    await DriverHistoryScreen.addTrip(
      DriverTripHistoryItem(
        tripId: 'TRP-${now.millisecondsSinceEpoch % 1000000}',
        route: widget.route,
        plateNumber: widget.plateNumber,
        dateTime: _formatDateTime(widget.startTime),
        duration: durationLabel,
        completedAt: now,
      ),
    );

    await DriverNotificationsScreen.push(
      DriverAppNotification(
        icon: Icons.check_circle_rounded,
        iconBackground: AppColors.logoBlue,
        title: 'Trip Completed',
        message: '${widget.route} · $durationLabel',
        time: now,
      ),
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => _TripCompletedDialog(route: widget.route, plateNumber: widget.plateNumber, duration: durationLabel),
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // A neutral background, not solid black — the map fills this via
      // Positioned.fill, but until tiles finish loading this color is
      // what's actually visible, and a full-bleed black screen there
      // reads as a broken/blank overlay rather than "a map is loading".
      backgroundColor: const Color(0xFFE5E7EB),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _currentLocation,
                initialZoom: 16,
                minZoom: 3,
                maxZoom: 19,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.manibel.app',
                  maxZoom: 19,
                ),
                RichAttributionWidget(
                  attributions: [TextSourceAttribution('© OpenStreetMap contributors', onTap: () {})],
                ),
                MarkerLayer(
                  markers: [
                    for (final stop in _waitingStops)
                      Marker(
                        point: stop.point,
                        width: 34,
                        height: 34,
                        child: _WaitingStopPin(count: stop.count),
                      ),
                    // The vehicle — this marker actually moves as the
                    // driver's GPS position updates.
                    Marker(
                      point: _currentLocation,
                      width: 40,
                      height: 40,
                      child: _VehicleMarker(hasRealFix: _hasRealFix),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Top status bar.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 12, offset: const Offset(0, 4)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: const BoxDecoration(color: AppColors.logoBlue, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.route,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                          ),
                          Text(
                            widget.plateNumber,
                            style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(20)),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircleAvatar(radius: 3, backgroundColor: Colors.green),
                          const SizedBox(width: 6),
                          Text(
                            _elapsedLabel,
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.green),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            ),
          ),

          // End Trip button.
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _handleEndTrip,
                  icon: const Icon(Icons.stop_circle_rounded, color: Colors.white),
                  label: const Text(
                    'End Trip',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.errorRed,
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VehicleMarker extends StatelessWidget {
  final bool hasRealFix;

  const _VehicleMarker({required this.hasRealFix});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: hasRealFix ? AppColors.logoBlue : Colors.black38,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: (hasRealFix ? AppColors.logoBlue : Colors.black38).withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 3,
          ),
        ],
      ),
      child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 20),
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

class _TripCompletedDialog extends StatelessWidget {
  final String route;
  final String plateNumber;
  final String duration;

  const _TripCompletedDialog({required this.route, required this.plateNumber, required this.duration});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(color: AppColors.qrTileBg, shape: BoxShape.circle),
              child: const Icon(Icons.check_circle_rounded, color: AppColors.qrIconColor, size: 28),
            ),
            const SizedBox(height: 12),
            const Text('Trip Completed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _DetailRow(label: 'Route', value: route),
            const SizedBox(height: 4),
            _DetailRow(label: 'Vehicle', value: plateNumber),
            const SizedBox(height: 4),
            _DetailRow(label: 'Duration', value: duration),
            const SizedBox(height: 10),
            const Text(
              'Tap outside to dismiss',
              style: TextStyle(fontSize: 10, color: Colors.black38, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w500)),
        const SizedBox(width: 6),
        Text(value, style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w800)),
      ],
    );
  }
}
