import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/qr_constants.dart';
import '../../../core/services/api_client.dart';
import '../../../core/utils/fare_calculator.dart';
import 'commuter_history_screen.dart';
import 'notifications_screen.dart';
import 'qr_scanner_screen.dart';

/// Turns a [Placemark] into a short, human-readable label like
/// "Ortigas Center, Pasig" or "Pasig City" — never raw coordinates.
/// Falls back to whatever fields are actually populated, since not every
/// address has a subLocality (barangay/neighborhood level).
String _formatPlacemark(Placemark p) {
  final parts = <String>[];

  if (p.subLocality != null && p.subLocality!.trim().isNotEmpty) {
    parts.add(p.subLocality!.trim());
  }
  if (p.locality != null && p.locality!.trim().isNotEmpty) {
    // Avoid "Pasig, Pasig" if subLocality happened to duplicate the city.
    if (parts.isEmpty || parts.first != p.locality!.trim()) {
      parts.add(p.locality!.trim());
    }
  } else if (p.subAdministrativeArea != null &&
      p.subAdministrativeArea!.trim().isNotEmpty) {
    parts.add(p.subAdministrativeArea!.trim());
  }

  if (parts.isEmpty) {
    // Last resort — still not coordinates, just less specific.
    if (p.administrativeArea != null && p.administrativeArea!.trim().isNotEmpty) {
      return p.administrativeArea!.trim();
    }
    return 'Unknown location';
  }

  return parts.join(', ');
}

/// Formats a [DateTime] as "Aug 10, 2026 · 3:45 PM", matching the style used
/// by the dummy entries already in [CommuterHistoryScreen].
String _formatHistoryDateTime(DateTime dt) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  final minute = dt.minute.toString().padLeft(2, '0');
  return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour12:$minute $period';
}

/// Resolves the device's exact current GPS position, requesting permission
/// if needed. Returns null (rather than throwing) if location services are
/// off or permission is denied, so callers can fall back to a default
/// center instead of crashing the booking flow over a permissions issue.
Future<LatLng?> _resolveCurrentLocation() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) return null;

  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return null;
  }

  try {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LatLng(position.latitude, position.longitude);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Brand palette — yellow & blue only. Swap these two values to retheme.
// ---------------------------------------------------------------------------
const Color _kBlue = Color(0xFF1957DB);
const Color _kBlueDark = Color(0xFF0F3EA6);
const Color _kYellow = Color(0xFFFFC72C);
const Color _kYellowDark = Color(0xFFE0A800);

enum _BookingStep {
  routeAndCompanions,
  boardingPoint,
  findingJeepneys,
  scanQr,
  boardingStatus,
  tripCompleted,
}

class _JeepneyOption {
  final String plateNumber;
  final String driverName;
  final int etaMinutes;
  final int seatsAvailable;
  final double driverRating;
  const _JeepneyOption({
    required this.plateNumber,
    required this.driverName,
    required this.etaMinutes,
    required this.seatsAvailable,
    required this.driverRating,
  });
}

/// Walks a commuter through: choosing a route, picking a boarding point by
/// pinning a location on the map, declaring companions, finding a nearby
/// jeepney, scanning a QR code to board, live boarding status with a
/// "Para po" stop signal, and finally trip completion with separate
/// rate/report actions for the driver.
class JeepneyBookingFlowScreen extends StatefulWidget {
  final String commuterName;

  const JeepneyBookingFlowScreen({super.key, required this.commuterName});

  @override
  State<JeepneyBookingFlowScreen> createState() =>
      _JeepneyBookingFlowScreenState();
}

class _JeepneyBookingFlowScreenState extends State<JeepneyBookingFlowScreen> {
  // Fallback used only until the real GPS fix comes in (or if location is
  // unavailable/denied) — not the source of truth once _center is set.
  static const _fallbackCenter = LatLng(14.6019, 121.0355);

  LatLng _center = _fallbackCenter;
  bool _locatingUser = false;
  final MapController _mapController = MapController();

  _BookingStep _step = _BookingStep.routeAndCompanions;

  @override
  void initState() {
    super.initState();
    _locateUser(moveMap: false); // seed with the real location before the user interacts with the map
  }

  Future<void> _locateUser({bool moveMap = true}) async {
    if (_locatingUser) return;
    setState(() => _locatingUser = true);

    final resolved = await _resolveCurrentLocation();

    if (!mounted) return;
    setState(() => _locatingUser = false);

    if (resolved == null) {
      if (moveMap) {
        // Only surface this when the user explicitly tapped "locate me" —
        // silently keeping the fallback on the initial auto-locate avoids
        // an unprompted permission-denied snackbar on screen load.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get your exact location. Check location permissions.')),
        );
      }
      return;
    }

    setState(() => _center = resolved);
    if (moveMap) {
      _mapController.move(resolved, _mapController.camera.zoom);
    }
  }

  static const _routes = [
    'Pasig - Quiapo',
    'Quiapo - Pasig',
  ];

  static const _availableJeepneys = [
    _JeepneyOption(
      plateNumber: 'NBC 1234',
      driverName: 'R. Santos',
      etaMinutes: 3,
      seatsAvailable: 6,
      driverRating: 4.8,
    ),
    _JeepneyOption(
      plateNumber: 'NBD 5821',
      driverName: 'E. Ramos',
      etaMinutes: 6,
      seatsAvailable: 2,
      driverRating: 4.5,
    ),
    _JeepneyOption(
      plateNumber: 'NBE 7790',
      driverName: 'M. Cruz',
      etaMinutes: 9,
      seatsAvailable: 9,
      driverRating: 4.9,
    ),
  ];

  final TextEditingController _routeSearchController = TextEditingController();
  bool _routeDropdownOpen = false;
  String? _selectedRoute;
  String? _selectedBoardingPoint;

  // Total riders always includes the commuter themself; student/senior are
  // a subset of that total — whatever's left over rides at the regular fare.
  int _totalRiders = 1;
  int _studentRiders = 0;
  int _seniorRiders = 0;

  _JeepneyOption? _selectedJeepney;

  bool _hasRated = false;
  bool _hasReported = false;

  FareBreakdown get _fareBreakdown => FareBreakdown(
        regularRiders: _totalRiders - _studentRiders - _seniorRiders,
        studentRiders: _studentRiders,
        seniorRiders: _seniorRiders,
      );

  void _setTotalRiders(int value) {
    setState(() {
      _totalRiders = value;
      // Trim discounted riders (seniors first) if they no longer fit.
      while (_studentRiders + _seniorRiders > _totalRiders) {
        if (_seniorRiders > 0) {
          _seniorRiders--;
        } else if (_studentRiders > 0) {
          _studentRiders--;
        } else {
          break;
        }
      }
    });
  }

  void _goTo(_BookingStep step) => setState(() => _step = step);

  void _startFindingJeepneys() {
    _goTo(_BookingStep.findingJeepneys);
    // Simulated search delay — swap for a real nearby-jeepney query.
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted || _step != _BookingStep.findingJeepneys) return;
      setState(() {});
    });
  }

  // Opens the real camera scanner, then verifies whatever it decoded
  // against the backend — a photo of someone else's QR, or a code from a
  // completely unrelated app, won't verify. On success the (real, mocked-
  // jeepney-list-independent) driver name/plate from the backend replace
  // the placeholder ones on `_selectedJeepney` before continuing on to the
  // existing "You're on Board!" flow.
  Future<void> _handleScanQr() async {
    final jeepney = _selectedJeepney;
    if (jeepney == null) return;

    final rawValue = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScannerScreen()),
    );
    if (rawValue == null || !mounted) return;

    if (!rawValue.startsWith(kDriverQrPrefix)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("That's not a ManibelApp driver QR code.")),
      );
      return;
    }

    final token = rawValue.substring(kDriverQrPrefix.length);

    try {
      final response = await ApiClient.get('/api/driver/verify-qr/$token');
      final driver = response['driver'] as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _selectedJeepney = _JeepneyOption(
          plateNumber: driver['plateNumber'] as String,
          driverName: driver['fullName'] as String,
          etaMinutes: jeepney.etaMinutes,
          seatsAvailable: jeepney.seatsAvailable,
          driverRating: jeepney.driverRating,
        );
      });

      _simulateQrScan();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // Shows a compact "You're on Board!" popup right after the QR scan.
  // Tapping the dimmed background dismisses it and advances straight to
  // the boarding-status step — the panel underneath doesn't change until
  // the popup is dismissed, same pattern as the Para Po dialog below.
  void _simulateQrScan() {
    final jeepney = _selectedJeepney;
    final route = _selectedRoute;
    final boardingPoint = _selectedBoardingPoint;
    if (jeepney == null || route == null || boardingPoint == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (_) => _OnBoardDialog(
        route: route,
        boardingPoint: boardingPoint,
        jeepney: jeepney,
        fare: _fareBreakdown,
      ),
    ).then((_) {
      if (!mounted) return;
      _goTo(_BookingStep.boardingStatus);
    });
  }

  // Shows a centered "driver notified" dialog with the driver's name and
  // rating. Tapping anywhere on the dimmed background dismisses it (default
  // showDialog barrier behavior); it also auto-dismisses after a few
  // seconds. Either way, dismissing it advances the trip to "completed".
  void _handleParaPo() {
    final jeepney = _selectedJeepney;
    if (jeepney == null) return;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (_) => _DriverNotifiedDialog(jeepney: jeepney),
    ).then((_) {
      if (!mounted) return;
      _recordTripInHistory();
      _goTo(_BookingStep.tripCompleted);
    });

    Future.delayed(const Duration(seconds: 3), () {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).maybePop();
    });
  }

  // Adds this booking to the commuter's trip history as soon as the trip is
  // marked complete, so every booking — not just this session's view of it
  // — shows up on the History screen afterwards.
  void _recordTripInHistory() {
    final jeepney = _selectedJeepney;
    final route = _selectedRoute;
    final boardingPoint = _selectedBoardingPoint;
    if (jeepney == null || route == null || boardingPoint == null) return;

    final now = DateTime.now();
    final fare = _fareBreakdown;

    CommuterHistoryScreen.addTrip(
      TripHistoryItem(
        tripId: 'TRIP-${now.millisecondsSinceEpoch}',
        driverName: jeepney.driverName,
        plateNumber: jeepney.plateNumber,
        route: route,
        boardingPoint: boardingPoint,
        regularRiders: fare.regularRiders,
        studentRiders: fare.studentRiders,
        seniorRiders: fare.seniorRiders,
        dateTime: _formatHistoryDateTime(now),
        fare: fare.totalLabel,
      ),
    );

    NotificationsScreen.push(
      AppNotification(
        icon: Icons.directions_bus_filled_rounded,
        iconBackground: AppColors.logoBlue,
        title: 'Trip Completed',
        message: '$route trip completed. Fare: ${fare.totalLabel}.',
        time: now,
      ),
    );
  }

  void _showRateDriverSheet() {
    final jeepney = _selectedJeepney;
    if (jeepney == null || _hasRated) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _RateDriverSheet(
        jeepney: jeepney,
        onSubmit: (stars) {
          Navigator.of(ctx).pop();
          setState(() => _hasRated = true);
          NotificationsScreen.push(
            AppNotification(
              icon: Icons.star_rounded,
              iconBackground: AppColors.splashBackground,
              title: 'Thank You For Rating!',
              message: 'Thank you! Your rating helps improve our service.',
              time: DateTime.now(),
            ),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
    );
  }

  void _showReportDriverSheet() {
    final jeepney = _selectedJeepney;
    if (jeepney == null || _hasReported) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _ReportDriverSheet(
        jeepney: jeepney,
        onSubmit: (reason, details, photo) {
          Navigator.of(ctx).pop();
          setState(() => _hasReported = true);
          NotificationsScreen.push(
            AppNotification(
              icon: Icons.shield_rounded,
              iconBackground: AppColors.qrIconColor,
              title: 'Report Received',
              message: 'Your report about ${jeepney.driverName} has been received. Thank you for helping us improve.',
              time: DateTime.now(),
            ),
          );
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE9ECEE),
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _center,
                initialZoom: 14.5,
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
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors', onTap: () {}),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _center,
                      width: 22,
                      height: 22,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _kBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.close_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  _RoundIconButton(
                    icon: _locatingUser ? Icons.hourglass_top_rounded : Icons.my_location_rounded,
                    onTap: _locatingUser ? () {} : () => _locateUser(),
                  ),
                ],
              ),
            ),
          ),

          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 16,
                        offset: const Offset(0, -4),
                      ),
                    ],
                  ),
                  child: _buildStepContent(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case _BookingStep.routeAndCompanions:
        return _RouteAndCompanionsStep(
          routes: _routes,
          searchController: _routeSearchController,
          dropdownOpen: _routeDropdownOpen,
          onDropdownToggle: (open) =>
              setState(() => _routeDropdownOpen = open),
          selectedRoute: _selectedRoute,
          onSelectRoute: (route) => setState(() {
            _selectedRoute = route;
            _routeSearchController.text = route;
            _routeDropdownOpen = false;
          }),
          totalRiders: _totalRiders,
          studentRiders: _studentRiders,
          seniorRiders: _seniorRiders,
          onTotalRidersChanged: _setTotalRiders,
          onStudentRidersChanged: (value) => setState(() => _studentRiders = value),
          onSeniorRidersChanged: (value) => setState(() => _seniorRiders = value),
          onContinue: _selectedRoute == null
              ? null
              : () => _goTo(_BookingStep.boardingPoint),
        );

      case _BookingStep.boardingPoint:
        return _BoardingPointStep(
          initialCenter: _center,
          onConfirm: (label) {
            setState(() => _selectedBoardingPoint = label);
            _startFindingJeepneys();
          },
          onBack: () => _goTo(_BookingStep.routeAndCompanions),
        );

      case _BookingStep.findingJeepneys:
        return _FindJeepneysStep(
          jeepneys: _availableJeepneys,
          selected: _selectedJeepney,
          onSelect: (jeepney) => setState(() => _selectedJeepney = jeepney),
          onBack: () => _goTo(_BookingStep.boardingPoint),
          onBook: _selectedJeepney == null
              ? null
              : () => _goTo(_BookingStep.scanQr),
        );

      case _BookingStep.scanQr:
        return _ScanQrStep(
          jeepney: _selectedJeepney!,
          onScan: _handleScanQr,
          onBack: () => _goTo(_BookingStep.findingJeepneys),
        );

      case _BookingStep.boardingStatus:
        return _BoardingStatusStep(
          route: _selectedRoute!,
          boardingPoint: _selectedBoardingPoint!,
          jeepney: _selectedJeepney!,
          fare: _fareBreakdown,
          onParaPo: _handleParaPo,
        );

      case _BookingStep.tripCompleted:
        return _TripCompletedStep(
          route: _selectedRoute!,
          boardingPoint: _selectedBoardingPoint!,
          jeepney: _selectedJeepney!,
          fare: _fareBreakdown,
          hasRated: _hasRated,
          hasReported: _hasReported,
          onRateDriver: _showRateDriverSheet,
          onReportDriver: _showReportDriverSheet,
          onDone: () => Navigator.of(context).popUntil((route) => route.isFirst),
        );
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _routeSearchController.dispose();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: const CircleBorder(),
      elevation: 3,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 22, color: Colors.black87),
        ),
      ),
    );
  }
}

class _StepTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;

  const _StepTitle({required this.title, this.subtitle, this.onBack});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(20),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.arrow_back_rounded, size: 20),
              ),
            ),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w500),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  final Color? textColor;

  const _PrimaryButton({required this.label, required this.onTap, this.color, this.textColor});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: color ?? _kYellow,
          foregroundColor: textColor ?? _kBlueDark,
          disabledBackgroundColor: const Color(0xFFDADDE1),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
          elevation: 0,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

class _OutlinedActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;
  final IconData? icon;

  const _OutlinedActionButton({
    required this.label,
    required this.onTap,
    this.color = _kBlue,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: icon != null ? Icon(icon, size: 18, color: color) : const SizedBox.shrink(),
        label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1 — Select a Route (searchable, compact swipeable carousel) +
// Companions, combined in one stable panel.
// ---------------------------------------------------------------------------

class _RouteAndCompanionsStep extends StatefulWidget {
  final List<String> routes;
  final TextEditingController searchController;
  final bool dropdownOpen;
  final ValueChanged<bool> onDropdownToggle;
  final String? selectedRoute;
  final ValueChanged<String> onSelectRoute;

  final int totalRiders;
  final int studentRiders;
  final int seniorRiders;
  final ValueChanged<int> onTotalRidersChanged;
  final ValueChanged<int> onStudentRidersChanged;
  final ValueChanged<int> onSeniorRidersChanged;

  final VoidCallback? onContinue;

  const _RouteAndCompanionsStep({
    required this.routes,
    required this.searchController,
    required this.dropdownOpen,
    required this.onDropdownToggle,
    required this.selectedRoute,
    required this.onSelectRoute,
    required this.totalRiders,
    required this.studentRiders,
    required this.seniorRiders,
    required this.onTotalRidersChanged,
    required this.onStudentRidersChanged,
    required this.onSeniorRidersChanged,
    required this.onContinue,
  });

  @override
  State<_RouteAndCompanionsStep> createState() => _RouteAndCompanionsStepState();
}

class _RouteAndCompanionsStepState extends State<_RouteAndCompanionsStep> {
  late final PageController _routePageController;

  @override
  void initState() {
    super.initState();
    final initialIndex = widget.selectedRoute == null
        ? 0
        : widget.routes.indexOf(widget.selectedRoute!).clamp(0, widget.routes.length - 1);
    _routePageController = PageController(viewportFraction: 0.62, initialPage: initialIndex);
  }

  @override
  void dispose() {
    _routePageController.dispose();
    super.dispose();
  }

  List<String> get _filteredRoutes {
    final query = widget.searchController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.routes;
    return widget.routes.where((r) => r.toLowerCase().contains(query)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRoutes;
    final fare = FareBreakdown(
      regularRiders: widget.totalRiders - widget.studentRiders - widget.seniorRiders,
      studentRiders: widget.studentRiders,
      seniorRiders: widget.seniorRiders,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepTitle(title: 'Select a Route', subtitle: 'Search or swipe to pick your route'),
        const SizedBox(height: 10),

        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6F8),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.dropdownOpen ? _kBlue : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: TextField(
            controller: widget.searchController,
            onTap: () => widget.onDropdownToggle(true),
            onChanged: (_) => widget.onDropdownToggle(true),
            decoration: const InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              hintText: 'e.g. Pasig - Quiapo',
              hintStyle: TextStyle(fontSize: 13, color: Colors.black38),
              prefixIcon: Icon(Icons.search, size: 20, color: Colors.black45),
              suffixIcon: Icon(Icons.expand_more_rounded, color: Colors.black45),
            ),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),

        ClipRect(
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            alignment: Alignment.topCenter,
            heightFactor: widget.dropdownOpen && filtered.isNotEmpty ? 1 : 0,
            child: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 86,
                child: PageView.builder(
                  controller: _routePageController,
                  itemCount: filtered.length,
                  padEnds: false,
                  onPageChanged: (index) => widget.onSelectRoute(filtered[index]),
                  itemBuilder: (context, index) {
                    final route = filtered[index];
                    final isSelected = route == widget.selectedRoute;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: _RouteCard(
                        route: route,
                        selected: isSelected,
                        onTap: () {
                          _routePageController.animateToPage(
                            index,
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOut,
                          );
                          widget.onSelectRoute(route);
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 18),

        const Text(
          'How many passengers?',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Include yourself in the count.',
          style: TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6F8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: _RiderCounterRow(
            label: 'Total passengers',
            count: widget.totalRiders,
            min: 1,
            max: 5,
            onChanged: widget.onTotalRidersChanged,
          ),
        ),

        const SizedBox(height: 16),

        const Text(
          'Fare Type',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Student and Senior/PWD riders get a discounted fare.',
          style: TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6F8),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _RiderCounterRow(
                  label: 'Student',
                  count: widget.studentRiders,
                  min: 0,
                  max: widget.totalRiders - widget.seniorRiders,
                  onChanged: widget.onStudentRidersChanged,
                ),
              ),
              const Divider(height: 1, color: Color(0xFFE6E6E7)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: _RiderCounterRow(
                  label: 'Senior / PWD',
                  count: widget.seniorRiders,
                  min: 0,
                  max: widget.totalRiders - widget.studentRiders,
                  onChanged: widget.onSeniorRidersChanged,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                fare.ridersLabel,
                style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              'Est. fare: ${fare.totalLabel}',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _kBlue),
            ),
          ],
        ),

        const SizedBox(height: 18),
        _PrimaryButton(label: 'Continue', onTap: widget.onContinue),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  final String route;
  final bool selected;
  final VoidCallback onTap;

  const _RouteCard({required this.route, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: Material(
        color: selected ? const Color(0xFFFFF3D6) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? _kYellowDark : const Color(0xFFE7E7E7),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: selected ? _kYellowDark : _kYellow.withOpacity(0.25),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.alt_route_rounded,
                    size: 16,
                    color: _kBlueDark,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    route,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: selected ? _kBlueDark : Colors.black87,
                    ),
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: _kBlueDark, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2 — Where will you board? Commuter drops a pin on the map instead of
// picking from a fixed list. The pin stays fixed at the center of the
// screen and the map moves underneath it (the common "drag map, pin
// stays put" pattern) — the tracked center is what gets confirmed.
// ---------------------------------------------------------------------------

class _BoardingPointStep extends StatefulWidget {
  final LatLng initialCenter;
  final ValueChanged<String> onConfirm;
  final VoidCallback onBack;

  const _BoardingPointStep({
    required this.initialCenter,
    required this.onConfirm,
    required this.onBack,
  });

  @override
  State<_BoardingPointStep> createState() => _BoardingPointStepState();
}

class _BoardingPointStepState extends State<_BoardingPointStep> {
  late final MapController _pinMapController;
  late LatLng _pinCenter;

  // The GPS fix this step opened with — used only to detect "the pin is
  // still sitting exactly where we started" so we can label that case
  // "Your current location" instead of running it through reverse
  // geocoding like every other dropped pin.
  late final LatLng _startingGpsPosition;

  bool _locatingUser = false;
  bool _isResolvingAddress = true;
  String _addressLabel = 'Detecting your location…';
  Timer? _geocodeDebounce;

  @override
  void initState() {
    super.initState();
    _pinMapController = MapController();
    _pinCenter = widget.initialCenter;
    _startingGpsPosition = widget.initialCenter;
    _resolveAddressFor(_pinCenter);
  }

  @override
  void dispose() {
    _geocodeDebounce?.cancel();
    _pinMapController.dispose();
    super.dispose();
  }

  bool _isAtStartingPosition(LatLng point) {
    // Small tolerance (15m) rather than exact equality — GPS fixes and
    // map-center math both have some jitter even with zero user panning.
    return Geolocator.distanceBetween(
          point.latitude,
          point.longitude,
          _startingGpsPosition.latitude,
          _startingGpsPosition.longitude,
        ) <
        15;
  }

  Future<void> _resolveAddressFor(LatLng point) async {
    if (_isAtStartingPosition(point)) {
      // No need to hit the network for this — we already know where we
      // started, and it's more meaningful to the user as "current
      // location" than as whatever city that GPS fix happens to be in.
      if (!mounted) return;
      setState(() {
        _addressLabel = 'Your current location';
        _isResolvingAddress = false;
      });
      return;
    }

    setState(() => _isResolvingAddress = true);

    try {
      final placemarks = await placemarkFromCoordinates(point.latitude, point.longitude);
      if (!mounted) return;

      setState(() {
        _addressLabel = placemarks.isEmpty ? 'Unknown location' : _formatPlacemark(placemarks.first);
        _isResolvingAddress = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _addressLabel = 'Could not detect address';
        _isResolvingAddress = false;
      });
    }
  }

  Future<void> _locateMe() async {
    if (_locatingUser) return;
    setState(() => _locatingUser = true);

    final resolved = await _resolveCurrentLocation();

    if (!mounted) return;
    setState(() => _locatingUser = false);

    if (resolved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not get your exact location. Check location permissions.')),
      );
      return;
    }

    _geocodeDebounce?.cancel();
    setState(() => _pinCenter = resolved);
    _pinMapController.move(resolved, _pinMapController.camera.zoom);

    // Re-baseline "current location" to this fresh fix, then label it as
    // such immediately rather than waiting on the debounce below.
    setState(() {
      _addressLabel = 'Your current location';
      _isResolvingAddress = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Where will you board?',
          subtitle: 'Drag the map to drop your pin',
          onBack: widget.onBack,
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                FlutterMap(
                  mapController: _pinMapController,
                  options: MapOptions(
                    initialCenter: _pinCenter,
                    initialZoom: 16,
                    minZoom: 3,
                    maxZoom: 19,
                    onPositionChanged: (camera, hasGesture) {
                      if (!hasGesture) return;
                      setState(() {
                        _pinCenter = camera.center;
                        _isResolvingAddress = true; // shows "Detecting…" immediately, resolved once dragging settles
                      });
                      _geocodeDebounce?.cancel();
                      _geocodeDebounce = Timer(
                        const Duration(milliseconds: 700),
                        () => _resolveAddressFor(_pinCenter),
                      );
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.manibel.app',
                      maxZoom: 19,
                    ),
                  ],
                ),
                // Fixed center pin — the map moves underneath it.
                const Padding(
                  padding: EdgeInsets.only(bottom: 28),
                  child: Icon(Icons.location_on_rounded, size: 40, color: _kBlue),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    shadowColor: Colors.black26,
                    child: InkWell(
                      onTap: _locatingUser ? null : _locateMe,
                      customBorder: const CircleBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: _locatingUser
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: _kBlue),
                              )
                            : const Icon(Icons.my_location_rounded, size: 18, color: _kBlueDark),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 10,
                  left: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6),
                      ],
                    ),
                    child: Row(
                      children: [
                        if (_isResolvingAddress)
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: _kBlueDark),
                          )
                        else
                          const Icon(Icons.location_on_rounded, size: 16, color: _kBlueDark),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _isResolvingAddress ? 'Detecting address…' : _addressLabel,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.black87),
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
        const SizedBox(height: 14),
        _PrimaryButton(
          label: 'Confirm This Location',
          color: _kYellow,
          textColor: _kBlueDark,
          onTap: _isResolvingAddress ? null : () => widget.onConfirm(_addressLabel),
        ),
      ],
    );
  }
}

class _RiderCounterRow extends StatelessWidget {
  final String label;
  final int count;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _RiderCounterRow({
    required this.label,
    required this.count,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black87)),
        Row(
          children: [
            _StepperButton(
              icon: Icons.remove,
              onTap: count > min ? () => onChanged(count - 1) : null,
            ),
            SizedBox(
              width: 30,
              child: Text(
                '$count',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
              ),
            ),
            _StepperButton(
              icon: Icons.add,
              onTap: count < max ? () => onChanged(count + 1) : null,
            ),
          ],
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F6F8),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 20, color: onTap == null ? Colors.black26 : Colors.black87),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4 — Find Jeepneys (seats-available is shown here only — this is the
// picking stage, so it's still useful information before boarding).
// ---------------------------------------------------------------------------

class _FindJeepneysStep extends StatelessWidget {
  final List<_JeepneyOption> jeepneys;
  final _JeepneyOption? selected;
  final ValueChanged<_JeepneyOption> onSelect;
  final VoidCallback onBack;
  final VoidCallback? onBook;

  const _FindJeepneysStep({
    required this.jeepneys,
    required this.selected,
    required this.onSelect,
    required this.onBack,
    required this.onBook,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(title: 'Nearby Jeepneys', subtitle: 'Pick one to board', onBack: onBack),
        const SizedBox(height: 12),
        ...jeepneys.map((jeepney) {
          final isSelected = jeepney == selected;
          return _SelectableTile(
            title: '${jeepney.plateNumber} · ${jeepney.driverName}',
            subtitle: '${jeepney.etaMinutes} min away · ${jeepney.seatsAvailable} seats free',
            leadingIcon: Icons.directions_bus_filled_rounded,
            selected: isSelected,
            onTap: () => onSelect(jeepney),
          );
        }),
        const SizedBox(height: 8),
        _PrimaryButton(label: 'Book This Jeepney', onTap: onBook),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 5 — Scan QR to board
// ---------------------------------------------------------------------------

class _ScanQrStep extends StatelessWidget {
  final _JeepneyOption jeepney;
  final VoidCallback onScan;
  final VoidCallback onBack;

  const _ScanQrStep({required this.jeepney, required this.onScan, required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Scan QR to Board',
          subtitle: 'Ask the driver for ${jeepney.plateNumber}\'s QR code',
          onBack: onBack,
        ),
        const SizedBox(height: 14),
        AspectRatio(
          aspectRatio: 1.6,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF11141A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kYellow, width: 2),
            ),
            child: Center(
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  border: Border.all(color: _kYellow, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.qr_code_scanner_rounded, color: Colors.white70, size: 56),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _PrimaryButton(label: 'Scan QR Code', onTap: onScan),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// "You're on Board!" popup — shown right after the QR scan. Tapping the
// dimmed background dismisses it (default showDialog barrier behavior),
// which advances the trip to boarding status (handled by the caller's
// `.then()`), same pattern as the Para Po / Driver Notified dialog below.
// ---------------------------------------------------------------------------

class _OnBoardDialog extends StatelessWidget {
  final String route;
  final String boardingPoint;
  final _JeepneyOption jeepney;
  final FareBreakdown fare;

  const _OnBoardDialog({
    required this.route,
    required this.boardingPoint,
    required this.jeepney,
    required this.fare,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, color: AppColors.logoBlue, size: 28),
            ),
            const SizedBox(height: 14),
            const Text(
              "You're on Board!",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            Text(
              '${jeepney.plateNumber} · ${jeepney.driverName}',
              style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  _SummaryRow(label: 'Route', value: route),
                  _SummaryRow(label: 'Boarding point', value: boardingPoint),
                  _SummaryRow(label: 'Passengers', value: fare.ridersLabel),
                  _SummaryRow(label: 'Fare', value: fare.totalLabel),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tap outside to continue',
              style: TextStyle(fontSize: 11, color: Colors.black38, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 7 — Boarding status. Now shows the full trip recap (route, boarding
// point, jeepney, companions) alongside the live status and the Para Po
// button, instead of just the plate/driver.
// ---------------------------------------------------------------------------

class _BoardingStatusStep extends StatelessWidget {
  final String route;
  final String boardingPoint;
  final _JeepneyOption jeepney;
  final FareBreakdown fare;
  final VoidCallback onParaPo;

  const _BoardingStatusStep({
    required this.route,
    required this.boardingPoint,
    required this.jeepney,
    required this.fare,
    required this.onParaPo,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(color: _kBlue, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            const Text(
              'EN ROUTE',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _kBlue),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '${jeepney.plateNumber} · ${jeepney.driverName}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6F8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _SummaryRow(label: 'Route', value: route),
              _SummaryRow(label: 'Boarding point', value: boardingPoint),
              _SummaryRow(label: 'Passengers', value: fare.ridersLabel),
              _SummaryRow(label: 'Fare', value: fare.totalLabel),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "Tap Para Po when you're ready to alight.",
          style: TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton(
            onPressed: onParaPo,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kYellow,
              foregroundColor: _kBlueDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              elevation: 0,
            ),
            child: const Text(
              'Para po!',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Centered "driver notified" dialog — shown when Para Po is tapped. Tapping
// the dimmed background dismisses it (default barrier behavior); it also
// auto-dismisses after a few seconds. Either way, dismissing moves the trip
// to "completed" (handled by the caller's `.then()`).
// ---------------------------------------------------------------------------

class _DriverNotifiedDialog extends StatelessWidget {
  final _JeepneyOption jeepney;
  const _DriverNotifiedDialog({required this.jeepney});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.notifications_active_rounded, color: AppColors.logoBlue, size: 28),
            ),
            const SizedBox(height: 14),
            const Text(
              'Driver Notified',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              'Stopping shortly',
              style: TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: _kBlue,
                    child: Icon(Icons.person, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          jeepney.driverName,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.star_rounded, size: 14, color: _kYellowDark),
                            const SizedBox(width: 2),
                            Text(
                              jeepney.driverRating.toStringAsFixed(1),
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black54),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Text(
                    jeepney.plateNumber,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Tap outside to dismiss',
              style: TextStyle(fontSize: 11, color: Colors.black38, fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 8 — Trip completed. Shows the full trip recap and separates rating
// the driver from reporting them into two distinct actions.
// ---------------------------------------------------------------------------

class _TripCompletedStep extends StatelessWidget {
  final String route;
  final String boardingPoint;
  final _JeepneyOption jeepney;
  final FareBreakdown fare;
  final bool hasRated;
  final bool hasReported;
  final VoidCallback onRateDriver;
  final VoidCallback onReportDriver;
  final VoidCallback onDone;

  const _TripCompletedStep({
    required this.route,
    required this.boardingPoint,
    required this.jeepney,
    required this.fare,
    required this.hasRated,
    required this.hasReported,
    required this.onRateDriver,
    required this.onReportDriver,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
              child: const Icon(Icons.flag_rounded, color: AppColors.logoBlue, size: 22),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Trip Completed!', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F6F8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              _SummaryRow(label: 'Route', value: route),
              _SummaryRow(label: 'Boarding point', value: boardingPoint),
              _SummaryRow(label: 'Jeepney', value: '${jeepney.plateNumber} · ${jeepney.driverName}'),
              _SummaryRow(label: 'Passengers', value: fare.ridersLabel),
              _SummaryRow(label: 'Fare', value: fare.totalLabel),
            ],
          ),
        ),
        const SizedBox(height: 10),
        _PrimaryButton(
          label: hasRated ? 'Driver Rated' : 'Rate Driver',
          color: hasRated ? const Color(0xFFDADDE1) : _kYellow,
          textColor: hasRated ? Colors.black45 : _kBlueDark,
          onTap: hasRated ? null : onRateDriver,
        ),
        const SizedBox(height: 10),
        _OutlinedActionButton(
          label: hasReported ? 'Driver Reported' : 'Report Driver',
          icon: Icons.flag_outlined,
          color: _kBlue,
          onTap: hasReported ? null : onReportDriver,
        ),
        const SizedBox(height: 10),

      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rate Driver bottom sheet (used from Trip Completed).
// ---------------------------------------------------------------------------

class _RateDriverSheet extends StatefulWidget {
  final _JeepneyOption jeepney;
  final ValueChanged<int> onSubmit;

  const _RateDriverSheet({required this.jeepney, required this.onSubmit});

  @override
  State<_RateDriverSheet> createState() => _RateDriverSheetState();
}

class _RateDriverSheetState extends State<_RateDriverSheet> {
  int _stars = 5;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                decoration: BoxDecoration(color: const Color(0xFFDADDE1), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('How was your driver?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(
              '${widget.jeepney.driverName} · ${widget.jeepney.plateNumber}',
              style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final filled = index < _stars;
                return InkWell(
                  onTap: () => setState(() => _stars = index + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
                      size: 34,
                      color: _kYellowDark,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),
            _PrimaryButton(
              label: 'Submit Rating',
              onTap: () => widget.onSubmit(_stars),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Report Driver bottom sheet (used from Trip Completed) — same slide-up
// pattern as the Rate Driver sheet, plus a reason picker, details field,
// and an optional photo attachment.
// ---------------------------------------------------------------------------

class _ReportDriverSheet extends StatefulWidget {
  final _JeepneyOption jeepney;
  final void Function(String reason, String details, File? photo) onSubmit;

  const _ReportDriverSheet({required this.jeepney, required this.onSubmit});

  @override
  State<_ReportDriverSheet> createState() => _ReportDriverSheetState();
}

class _ReportDriverSheetState extends State<_ReportDriverSheet> {
  static const _reasons = [
    'Reckless driving',
    'Overcharging',
    'Rude behavior',
    'Vehicle condition',
    'Route violation',
    'Other',
  ];

  String? _selectedReason;
  final TextEditingController _detailsController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  File? _photo;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1600,
      );
      if (picked != null && mounted) {
        setState(() => _photo = File(picked.path));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't get image: $e")),
      );
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(ctx);
                _pickImage(ImageSource.gallery);
              },
            ),
            if (_photo != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Remove Photo', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _photo = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  void _handleSubmit() {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a reason.')),
      );
      return;
    }
    if (_detailsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe what happened.')),
      );
      return;
    }
    widget.onSubmit(_selectedReason!, _detailsController.text.trim(), _photo);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFDADDE1), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Report This Driver', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                '${widget.jeepney.driverName} · ${widget.jeepney.plateNumber}',
                style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const Text('What happened?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _reasons.map((reason) {
                  final selected = _selectedReason == reason;
                  return ChoiceChip(
                    label: Text(
                      reason,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: selected ? AppColors.onPrimary : Colors.black87,
                      ),
                    ),
                    selected: selected,
                    onSelected: (_) => setState(() => _selectedReason = reason),
                    selectedColor: AppColors.primary,
                    backgroundColor: const Color(0xFFF5F6F8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide.none,
                    ),
                    showCheckmark: false,
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              const Text('Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(color: const Color(0xFFF5F6F8), borderRadius: BorderRadius.circular(14)),
                child: TextField(
                  controller: _detailsController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText: 'Describe what happened...',
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Add Photo (optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: _showImageSourceSheet,
                child: Container(
                  width: double.infinity,
                  height: _photo == null ? 90 : 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F6F8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFE1E4E8)),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _photo == null
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_outlined, size: 22, color: AppColors.secondary),
                              SizedBox(height: 6),
                              Text(
                                'Tap to attach a photo',
                                style: TextStyle(fontSize: 11, color: Colors.black45),
                              ),
                            ],
                          ),
                        )
                      : Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.file(_photo!, fit: BoxFit.cover),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: GestureDetector(
                                onTap: () => setState(() => _photo = null),
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                  child: const Icon(Icons.close, size: 16, color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 20),
              _PrimaryButton(label: 'Submit Report', onTap: _handleSubmit),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable selectable list tile / toggle chip
// ---------------------------------------------------------------------------

class _SelectableTile extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? leadingIcon;
  final bool selected;
  final VoidCallback onTap;

  const _SelectableTile({
    required this.title,
    this.subtitle,
    this.leadingIcon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? const Color(0xFFEAF1FF) : const Color(0xFFF5F6F8),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? _kBlue : Colors.transparent,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon, size: 20, color: selected ? _kBlue : Colors.black45),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: selected ? _kBlue : Colors.black87,
                        ),
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle!,
                          style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: _kBlue, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
