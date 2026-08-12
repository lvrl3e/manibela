import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import 'driver_history_screen.dart';
import 'driver_notifications_screen.dart';

/// ---------------------------------------------------------------------------
/// ACTIVE TRIP CONTROLLER
/// ---------------------------------------------------------------------------
///
/// This controller owns the active trip instead of the trip screen.
///
/// That means:
/// - Leaving the trip screen does NOT end the trip.
/// - GPS tracking continues while navigating around the app.
/// - The Dashboard can check DriverActiveTrip.isActive.
/// - The driver can return to the trip later.
/// - Only "End Trip" stops the active trip.
///
/// This is an in-memory controller. If the app is completely killed,
/// the active trip will not survive the process being terminated.
/// ---------------------------------------------------------------------------

class DriverActiveTrip {
  DriverActiveTrip._();

  static final DriverActiveTrip instance = DriverActiveTrip._();

  StreamSubscription<Position>? _positionSubscription;
  Timer? _elapsedTimer;

  String? route;
  String? plateNumber;
  DateTime? startTime;

  LatLng? currentLocation;

  bool isActive = false;
  bool hasRealFix = false;

  final ValueNotifier<int> updateNotifier = ValueNotifier<int>(0);

  Duration get elapsed {
    if (startTime == null) {
      return Duration.zero;
    }

    return DateTime.now().difference(startTime!);
  }

  /// Start a new trip.
  Future<void> startTrip({
    required String route,
    required String plateNumber,
    required DateTime startTime,
    required LatLng initialLocation,
  }) async {
    // If a trip is already active, don't start another one.
    if (isActive) {
      return;
    }

    this.route = route;
    this.plateNumber = plateNumber;
    this.startTime = startTime;

    currentLocation = initialLocation;
    hasRealFix = false;
    isActive = true;

    updateNotifier.value++;

    _startElapsedTimer();
    await _startLocationTracking();
  }

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();

    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (!isActive) return;

        updateNotifier.value++;
      },
    );
  }

  Future<void> _startLocationTracking() async {
    try {
      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        return;
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      // Prevent duplicate subscriptions.
      await _positionSubscription?.cancel();

      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (position) {
          if (!isActive) return;

          currentLocation = LatLng(
            position.latitude,
            position.longitude,
          );

          hasRealFix = true;

          updateNotifier.value++;
        },
      );
    } catch (_) {
      // If live tracking isn't available,
      // the initial location is still retained.
    }
  }

  /// End the current trip.
  ///
  /// This is the ONLY method that should stop the active trip.
  Future<void> endTrip() async {
    isActive = false;

    await _positionSubscription?.cancel();
    _positionSubscription = null;

    _elapsedTimer?.cancel();
    _elapsedTimer = null;

    updateNotifier.value++;
  }

  /// Reconnect GPS tracking if needed.
  ///
  /// Useful when the driver returns to the trip screen.
  Future<void> resumeTracking() async {
    if (!isActive) return;

    if (_positionSubscription != null) {
      return;
    }

    await _startLocationTracking();
  }

  String get elapsedLabel {
    final duration = elapsed;

    final h = duration.inHours;
    final m = duration.inMinutes % 60;
    final s = duration.inSeconds % 60;

    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');

    if (h > 0) {
      return '${h}h ${mm}m';
    }

    return '$mm:$ss';
  }
}

/// ---------------------------------------------------------------------------
/// DRIVER TRIP IN PROGRESS SCREEN
/// ---------------------------------------------------------------------------

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
  State<DriverTripInProgressScreen> createState() =>
      _DriverTripInProgressScreenState();
}

class _DriverTripInProgressScreenState
    extends State<DriverTripInProgressScreen> {
  final MapController _mapController = MapController();

  DriverActiveTrip get _activeTrip => DriverActiveTrip.instance;

  @override
  void initState() {
    super.initState();

    _initializeTrip();
  }

  Future<void> _initializeTrip() async {
    // If this is a brand-new trip, start it.
    if (!_activeTrip.isActive) {
      await _activeTrip.startTrip(
        route: widget.route,
        plateNumber: widget.plateNumber,
        startTime: widget.startTime,
        initialLocation: widget.initialLocation,
      );
    } else {
      // If the trip is already active,
      // we are simply returning to the trip screen.
      await _activeTrip.resumeTracking();
    }

    if (!mounted) return;

    final location =
        _activeTrip.currentLocation ?? widget.initialLocation;

    try {
      _mapController.move(location, 16);
    } catch (_) {}
  }

  @override
  void dispose() {
    // IMPORTANT:
    //
    // DO NOT stop the trip here.
    //
    // The trip controller owns the GPS subscription.
    // Therefore navigating back to Dashboard will NOT end the trip.
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // WAITING STOPS
  // -------------------------------------------------------------------------

  List<_WaitingStop> get _waitingStops {
    final location =
        _activeTrip.currentLocation ?? widget.initialLocation;

    return [
      _WaitingStop(
        point: LatLng(
          location.latitude + 0.004,
          location.longitude + 0.003,
        ),
        count: 5,
      ),
      _WaitingStop(
        point: LatLng(
          location.latitude - 0.003,
          location.longitude - 0.004,
        ),
        count: 8,
      ),
      _WaitingStop(
        point: LatLng(
          location.latitude + 0.002,
          location.longitude - 0.005,
        ),
        count: 3,
      ),
    ];
  }

  // -------------------------------------------------------------------------
  // FORMATTING
  // -------------------------------------------------------------------------

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }

    return '${minutes}m';
  }

  String _formatDateTime(DateTime dt) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');

    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · '
        '$hour12:$minute $period';
  }

  // -------------------------------------------------------------------------
  // BACK TO DASHBOARD
  // -------------------------------------------------------------------------

  void _handleBackToDashboard() {
    // IMPORTANT:
    //
    // We are NOT calling:
    //   _activeTrip.endTrip();
    //
    // We are simply leaving this screen.
    //
    // The active trip controller continues tracking GPS.
    Navigator.of(context).pop();
  }

  // -------------------------------------------------------------------------
  // END TRIP
  // -------------------------------------------------------------------------

  Future<void> _handleEndTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'End this trip?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            'You are about to stop broadcasting '
            '${_activeTrip.route ?? widget.route}.',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
          actionsPadding: const EdgeInsets.only(
            right: 12,
            bottom: 8,
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.errorRed,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'End Trip',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    final now = DateTime.now();

    final startTime =
        _activeTrip.startTime ?? widget.startTime;

    final route =
        _activeTrip.route ?? widget.route;

    final plateNumber =
        _activeTrip.plateNumber ?? widget.plateNumber;

    final durationLabel =
        _formatDuration(now.difference(startTime));

    // Stop the active trip.
    await _activeTrip.endTrip();

    // Save trip to history.
    await DriverHistoryScreen.addTrip(
      DriverTripHistoryItem(
        tripId:
            'TRP-${now.millisecondsSinceEpoch % 1000000}',
        route: route,
        plateNumber: plateNumber,
        dateTime: _formatDateTime(startTime),
        duration: durationLabel,
        completedAt: now,
      ),
    );

    // Push notification.
    await DriverNotificationsScreen.push(
      DriverAppNotification(
        icon: Icons.check_circle_rounded,
        iconBackground: AppColors.logoBlue,
        title: 'Trip Completed',
        message: '$route · $durationLabel',
        time: now,
      ),
    );

    if (!mounted) return;

    // Show completed dialog.
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) {
        return _TripCompletedDialog(
          route: route,
          plateNumber: plateNumber,
          duration: durationLabel,
        );
      },
    );

    if (!mounted) return;

    // Now that the trip has actually ended,
    // return to Dashboard.
    Navigator.of(context).pop(true);
  }

  // -------------------------------------------------------------------------
  // BUILD
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: _activeTrip.updateNotifier,
      builder: (context, _, __) {
        final currentLocation =
            _activeTrip.currentLocation ??
                widget.initialLocation;

        final route =
            _activeTrip.route ?? widget.route;

        final plateNumber =
            _activeTrip.plateNumber ??
                widget.plateNumber;

        return Scaffold(
          backgroundColor: const Color(0xFFE5E7EB),
          body: Stack(
            children: [
              // =============================================================
              // MAP
              // =============================================================

              Positioned.fill(
                child: FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: currentLocation,
                    initialZoom: 16,
                    minZoom: 3,
                    maxZoom: 19,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName:
                          'com.manibel.app',
                      maxZoom: 19,
                    ),

                    RichAttributionWidget(
                      attributions: [
                        TextSourceAttribution(
                          '© OpenStreetMap contributors',
                          onTap: () {},
                        ),
                      ],
                    ),

                    MarkerLayer(
                      markers: [
                        // Waiting passenger stops.
                        for (final stop in _waitingStops)
                          Marker(
                            point: stop.point,
                            width: 34,
                            height: 34,
                            child: _WaitingStopPin(
                              count: stop.count,
                            ),
                          ),

                        // Driver vehicle.
                        Marker(
                          point: currentLocation,
                          width: 40,
                          height: 40,
                          child: _VehicleMarker(
                            hasRealFix:
                                _activeTrip.hasRealFix,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // =============================================================
              // TOP BAR
              // =============================================================

              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        // ---------------------------------------------------
                        // BACK BUTTON
                        // ---------------------------------------------------

                        Container(
                          width: 46,
                          height: 46,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    Colors.black.withOpacity(0.15),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: IconButton(
                            onPressed:
                                _handleBackToDashboard,
                            icon: const Icon(
                              Icons.arrow_back_rounded,
                              color: AppColors.textPrimary,
                            ),
                            tooltip:
                                'Back to Dashboard',
                          ),
                        ),

                        const SizedBox(width: 10),

                        // ---------------------------------------------------
                        // TRIP STATUS
                        // ---------------------------------------------------

                        Expanded(
                          child: Container(
                            padding:
                                const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.circular(18),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withOpacity(0.15),
                                  blurRadius: 12,
                                  offset:
                                      const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 36,
                                  height: 36,
                                  decoration:
                                      const BoxDecoration(
                                    color:
                                        AppColors.logoBlue,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment:
                                      Alignment.center,
                                  child: const Icon(
                                    Icons
                                        .directions_bus_rounded,
                                    color: Colors.white,
                                    size: 18,
                                  ),
                                ),

                                const SizedBox(width: 10),

                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment
                                            .start,
                                    children: [
                                      Text(
                                        route,
                                        maxLines: 1,
                                        overflow:
                                            TextOverflow.ellipsis,
                                        style:
                                            const TextStyle(
                                          fontSize: 14,
                                          fontWeight:
                                              FontWeight.w800,
                                          color: AppColors
                                              .textPrimary,
                                        ),
                                      ),
                                      Text(
                                        plateNumber,
                                        style:
                                            const TextStyle(
                                          fontSize: 10,
                                          color:
                                              Colors.black54,
                                          fontWeight:
                                              FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(width: 8),

                                Container(
                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration:
                                      BoxDecoration(
                                    color:
                                        const Color(
                                      0xFFDCFCE7,
                                    ),
                                    borderRadius:
                                        BorderRadius.circular(
                                      20,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize:
                                        MainAxisSize.min,
                                    children: [
                                      const CircleAvatar(
                                        radius: 3,
                                        backgroundColor:
                                            Colors.green,
                                      ),
                                      const SizedBox(
                                        width: 6,
                                      ),
                                      Text(
                                        _activeTrip
                                            .elapsedLabel,
                                        style:
                                            const TextStyle(
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight.w800,
                                          color:
                                              Colors.green,
                                        ),
                                      ),
                                    ],
                                  ),
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

              // =============================================================
              // END TRIP BUTTON
              // =============================================================

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
                      icon: const Icon(
                        Icons.stop_circle_rounded,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'End Trip',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.errorRed,
                        elevation: 4,
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(28),
                        ),
                      ),
                    ),
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

// ===========================================================================
// VEHICLE MARKER
// ===========================================================================

class _VehicleMarker extends StatelessWidget {
  final bool hasRealFix;

  const _VehicleMarker({
    required this.hasRealFix,
  });

  @override
  Widget build(BuildContext context) {
    final markerColor = hasRealFix
        ? AppColors.logoBlue
        : Colors.black38;

    return Container(
      decoration: BoxDecoration(
        color: markerColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color: markerColor.withOpacity(0.5),
            blurRadius: 10,
            spreadRadius: 3,
          ),
        ],
      ),
      child: const Icon(
        Icons.directions_bus_rounded,
        color: Colors.white,
        size: 20,
      ),
    );
  }
}

// ===========================================================================
// WAITING STOP
// ===========================================================================

class _WaitingStop {
  final LatLng point;
  final int count;

  const _WaitingStop({
    required this.point,
    required this.count,
  });
}

// ===========================================================================
// WAITING STOP PIN
// ===========================================================================

class _WaitingStopPin extends StatelessWidget {
  final int count;

  const _WaitingStopPin({
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 17,
      backgroundColor: AppColors.logoRed,
      child: CircleAvatar(
        radius: 15,
        backgroundColor:
            AppColors.splashBackground,
        child: Text(
          '$count',
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// TRIP COMPLETED DIALOG
// ===========================================================================

class _TripCompletedDialog extends StatelessWidget {
  final String route;
  final String plateNumber;
  final String duration;

  const _TripCompletedDialog({
    required this.route,
    required this.plateNumber,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          24,
          24,
          24,
          20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                color: AppColors.qrTileBg,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.qrIconColor,
                size: 28,
              ),
            ),

            const SizedBox(height: 12),

            const Text(
              'Trip Completed',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 8),

            _DetailRow(
              label: 'Route',
              value: route,
            ),

            const SizedBox(height: 4),

            _DetailRow(
              label: 'Vehicle',
              value: plateNumber,
            ),

            const SizedBox(height: 4),

            _DetailRow(
              label: 'Duration',
              value: duration,
            ),

            const SizedBox(height: 10),

            const Text(
              'Tap outside to dismiss',
              style: TextStyle(
                fontSize: 10,
                color: Colors.black38,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// DETAIL ROW
// ===========================================================================

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black45,
            fontWeight: FontWeight.w500,
          ),
        ),

        const SizedBox(width: 6),

        Flexible(
          child: Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}