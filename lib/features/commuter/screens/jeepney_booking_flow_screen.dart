import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/qr_constants.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import '../../../core/utils/avatar_image.dart';
import '../../../core/utils/fare_calculator.dart';
import 'commuter_history_screen.dart';
import 'notifications_screen.dart';
import 'qr_scanner_screen.dart';

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
  findingJeepneys,
  scanQr,
  boardingStatus,
  tripCompleted,
}

class _JeepneyOption {
  final String plateNumber;
  final String driverName;

  /// A straight-line-distance estimate from GET /api/commuter/nearby-jeepneys
  /// (see its own doc comment in commuter.ts for why this is presented as
  /// an estimate, not real routing/traffic data) — 0 until that real call
  /// resolves this option, same as [driverRating] below.
  final int etaMinutes;
  final int distanceMeters;

  /// Real live-averaged rating from GET /api/commuter/nearby-jeepneys
  /// (pre-scan) or GET /api/driver/verify-qr (post-scan) — 0/null means
  /// "no ratings yet", never a placeholder (see _DriverRatingLabel).
  final double driverRating;
  final int ratingCount;

  final String? photoUrl;

  /// The underlying Trip id — null for an option resolved from a QR scan
  /// (verify-qr doesn't return one; that path boards by qrToken instead,
  /// see _handleScanQr), set for one resolved from GET /nearby-jeepneys,
  /// which is what lets proximity-based boarding call POST /board with a
  /// tripId directly, with nothing to scan.
  final String? tripId;

  /// This jeepney's live position, from GET /api/commuter/nearby-jeepneys —
  /// null for an option resolved from a QR scan (verify-qr doesn't return
  /// one). Lets the findingJeepneys step plot it on the map, not just list
  /// it, while the commuter is actively searching.
  final LatLng? position;

  const _JeepneyOption({
    required this.plateNumber,
    required this.driverName,
    required this.etaMinutes,
    this.distanceMeters = 0,
    required this.driverRating,
    this.ratingCount = 0,
    this.photoUrl,
    this.tripId,
    this.position,
  });
}

/// An already-in-progress trip from GET /api/commuter/active-trip — lets
/// [JeepneyBookingFlowScreen] resume straight into the live boarding-status
/// view instead of starting a new booking, for a boarding that happened in
/// another session (the app was force-closed mid-ride, or reopened after
/// boarding was recorded some other way).
class ResumedTrip {
  final String tripId;
  final String route;
  final String driverName;
  final String plateNumber;
  final String? photoUrl;
  final double driverRating;
  final int ratingCount;
  final int regularRiders;
  final int studentRiders;
  final int seniorRiders;

  const ResumedTrip({
    required this.tripId,
    required this.route,
    required this.driverName,
    required this.plateNumber,
    required this.photoUrl,
    required this.driverRating,
    required this.ratingCount,
    required this.regularRiders,
    required this.studentRiders,
    required this.seniorRiders,
  });
}

/// Walks a commuter through: choosing a route and declaring companions,
/// finding a nearby jeepney, scanning a QR code to board, live boarding
/// status with an End Trip action, and finally trip completion with
/// separate rate/report actions for the driver.
class JeepneyBookingFlowScreen extends StatefulWidget {
  final String commuterName;

  /// Skips straight to the live boarding-status step for this trip
  /// instead of starting a fresh booking — see [ResumedTrip].
  final ResumedTrip? resumedTrip;

  const JeepneyBookingFlowScreen({super.key, required this.commuterName, this.resumedTrip});

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

    final resumed = widget.resumedTrip;
    if (resumed != null) {
      _selectedRoute = resumed.route;
      _totalRiders = resumed.regularRiders + resumed.studentRiders + resumed.seniorRiders;
      _studentRiders = resumed.studentRiders;
      _seniorRiders = resumed.seniorRiders;
      _selectedJeepney = _JeepneyOption(
        plateNumber: resumed.plateNumber,
        driverName: resumed.driverName,
        etaMinutes: 0,
        driverRating: resumed.driverRating,
        ratingCount: resumed.ratingCount,
        photoUrl: resumed.photoUrl,
      );
      _boardedTripId = resumed.tripId;
      _step = _BookingStep.boardingStatus;
      _startBoardingStatusPoll();
    }
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

  // En-dash, not a hyphen — must match the backend's own DRIVER_ROUTES
  // (driver.ts/admin.ts) exactly, character for character, since this is
  // now sent as a literal filter to GET /api/commuter/nearby-jeepneys.
  static const _routes = [
    'Pasig – Quiapo',
    'Quiapo – Pasig',
  ];

  List<_JeepneyOption> _nearbyJeepneys = [];
  bool _isLoadingNearby = false;
  String? _nearbyError;

  final TextEditingController _routeSearchController = TextEditingController();
  bool _routeDropdownOpen = false;
  String? _selectedRoute;

  // Total riders always includes the commuter themself; student/senior are
  // a subset of that total — whatever's left over rides at the regular fare.
  int _totalRiders = 1;
  int _studentRiders = 0;
  int _seniorRiders = 0;

  _JeepneyOption? _selectedJeepney;

  // The real backend Trip id this booking was matched to, from /board's
  // response — null if that call failed (offline, driver has no active
  // trip, etc.), in which case this booking just won't sync anywhere.
  String? _boardedTripId;

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

  // The X button never ends the trip itself — it only ever closes this
  // screen (dispose() below is what cancels the demand-signal watch, see
  // _stopProximityPolling; there's no /alight call anywhere near this). If
  // the commuter is genuinely on board (_BookingStep.boardingStatus), the
  // trip stays open server-side and the dashboard correctly shows the
  // resume-trip banner on return (see _handleBook's own doc comment in
  // commuter_dashboard_screen.dart) — no confirmation needed here.
  void _handleCloseButton() => Navigator.of(context).pop();

  Future<void> _startFindingJeepneys(LatLng position) async {
    _goTo(_BookingStep.findingJeepneys);
    setState(() {
      _isLoadingNearby = true;
      _nearbyError = null;
    });

    try {
      final route = _selectedRoute;
      final response = await ApiClient.get(
        '/api/commuter/nearby-jeepneys'
        '?lat=${position.latitude}&lng=${position.longitude}'
        '${route != null ? '&route=${Uri.encodeQueryComponent(route)}' : ''}',
        token: UserSession.instance.authToken,
      );
      if (!mounted) return;
      final raw = response['jeepneys'] as List<dynamic>? ?? const [];
      setState(() {
        _nearbyJeepneys = raw.map((j) {
          final map = j as Map<String, dynamic>;
          return _JeepneyOption(
            plateNumber: map['plateNumber'] as String,
            driverName: map['driverName'] as String,
            etaMinutes: map['etaMinutes'] as int,
            distanceMeters: map['distanceMeters'] as int,
            driverRating: (map['averageRating'] as num?)?.toDouble() ?? 0,
            ratingCount: map['ratingCount'] as int? ?? 0,
            photoUrl: map['photoUrl'] as String?,
            tripId: map['tripId'] as String?,
            position: LatLng((map['lat'] as num).toDouble(), (map['lng'] as num).toDouble()),
          );
        }).toList();
        _isLoadingNearby = false;
      });
      // Restarts the 5s watch on every successful fetch (including the
      // timer's own tick) — keeps checks spaced out from when the last one
      // actually finished, rather than firing on a fixed clock regardless
      // of how long the network call took.
      if (_step == _BookingStep.findingJeepneys) {
        _startProximityPolling();
        _startDemandSignalKeepAlive();
      }
      _maybeAutoPromptProximityBoard();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingNearby = false;
        _nearbyError = e.message;
      });
    }
  }

  // Refreshes the nearby list every few seconds while the commuter is
  // sitting on the findingJeepneys step — this is what makes proximity
  // detection actually "live" instead of a one-time snapshot from the
  // moment the step opened, since a jeepney (and the commuter) keep moving.
  Timer? _proximityPollTimer;

  void _startProximityPolling() {
    _proximityPollTimer?.cancel();
    _proximityPollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _locateUser(moveMap: false);
      if (!mounted) return;
      await _startFindingJeepneys(_center);
    });
  }

  void _stopProximityPolling() {
    _proximityPollTimer?.cancel();
    _proximityPollTimer = null;
    _proximityFirstSeenAt.clear();
    _stopDemandSignalKeepAlive();
  }

  // The demand signal fires the moment a route is picked (right here, not
  // from the dashboard's "Sakay na" tap — the route isn't known yet at that
  // point, and GET /driver/demand-signals needs one to filter by, see its
  // own doc comment in driver.ts) and keeps re-sending every 10 minutes
  // while still looking. Each send refreshes the same backend row rather
  // than creating a new one (see POST /demand-signals in commuter.ts), so a
  // long wait never inflates a cluster's count — and re-sending well inside
  // the 15-minute staleness window (see DEMAND_SIGNAL_WINDOW_MS in
  // driver.ts/admin.ts) means it never actually goes dark as long as
  // they're still here.
  Timer? _demandSignalKeepAliveTimer;

  void _startDemandSignalKeepAlive() {
    if (_demandSignalKeepAliveTimer != null) return;
    _sendDemandSignal();
    _demandSignalKeepAliveTimer = Timer.periodic(const Duration(minutes: 10), (_) => _sendDemandSignal());
  }

  void _sendDemandSignal() {
    unawaited(
      ApiClient.post(
        '/api/commuter/demand-signals',
        {
          'lat': _center.latitude,
          'lng': _center.longitude,
          if (_selectedRoute != null) 'route': _selectedRoute,
        },
        token: UserSession.instance.authToken,
      ).catchError((_) => <String, dynamic>{}),
    );
  }

  void _stopDemandSignalKeepAlive() {
    if (_demandSignalKeepAliveTimer == null) return;
    _demandSignalKeepAliveTimer?.cancel();
    _demandSignalKeepAliveTimer = null;

    // They were actively looking and now aren't — tell the backend so a
    // driver's map doesn't keep showing them as "still waiting" for
    // however long is left of the staleness window. A safe no-op if they
    // got here because they just successfully boarded (see
    // _boardByTripId/_handleScanQr) — POST /board already fulfilled the
    // signal itself, so there's nothing left outstanding to cancel.
    unawaited(
      ApiClient.post(
        '/api/commuter/demand-signals/cancel',
        {},
        token: UserSession.instance.authToken,
      ).catchError((_) => <String, dynamic>{}),
    );
  }

  // A jeepney this close is treated as "the commuter is at/near it right
  // now" rather than just nearby on the map — close enough that GPS
  // imprecision (5-20m typical in the city, see nearby-jeepneys' own doc
  // comment) is unlikely to be confusing it with a different stopped
  // vehicle a full stop-width away.
  static const double _proximityThresholdMeters = 30;

  bool _proximityPromptShowing = false;

  // Declining (or ignoring, see the auto-dismiss timer below) a specific
  // jeepney silences the *auto*-prompt for it for a while — otherwise a
  // commuter standing near a jeepney they deliberately don't want to board
  // (wrong route, waiting for a friend, whatever) would get re-asked every
  // 5s for as long as they stayed in range. "Book This Jeepney" on the
  // manual list bypasses this entirely — a deliberate tap always works,
  // cooldown or not.
  final Map<String, DateTime> _proximitySnoozedUntil = {};
  static const Duration _proximitySnoozeDuration = Duration(minutes: 2);

  // A dialog nobody answers (phone in a pocket, not actually looking) would
  // otherwise sit open indefinitely — auto-treated as a decline after this
  // long so watching resumes instead of silently stalling.
  static const Duration _proximityPromptTimeout = Duration(seconds: 12);

  // How long the closest jeepney has to *stay* within
  // [_proximityThresholdMeters] before it's trusted enough to auto-prompt —
  // a single close poll could just be GPS jitter or a jeepney momentarily
  // passing within range without actually stopping; requiring it to hold
  // for a while (a handful of 5s polls) filters that out. Keyed by tripId
  // so a different jeepney becoming closest starts its own count from zero
  // rather than inheriting time built up by whichever one was closest before.
  final Map<String, DateTime> _proximityFirstSeenAt = {};
  static const Duration _proximitySustainedDuration = Duration(seconds: 30);

  // Auto-offers to board the closest jeepney once it's been within
  // [_proximityThresholdMeters] for [_proximitySustainedDuration] — no
  // manual "scan" tap required. Only ever proposes one at a time (guarded
  // by [_proximityPromptShowing]) and only while still choosing (a
  // boarded/boarding commuter shouldn't be re-prompted mid-ride).
  void _maybeAutoPromptProximityBoard() {
    if (_proximityPromptShowing || _step != _BookingStep.findingJeepneys) return;
    if (_nearbyJeepneys.isEmpty) {
      _proximityFirstSeenAt.clear();
      return;
    }

    final closest = _nearbyJeepneys.reduce(
      (a, b) => a.distanceMeters <= b.distanceMeters ? a : b,
    );
    final tripId = closest.tripId;
    if (tripId == null || closest.distanceMeters > _proximityThresholdMeters) {
      _proximityFirstSeenAt.clear();
      return;
    }

    // Only the current closest jeepney's "how long have they been this
    // close" timer keeps running.
    _proximityFirstSeenAt.removeWhere((id, _) => id != tripId);
    final firstSeenAt = _proximityFirstSeenAt.putIfAbsent(tripId, () => DateTime.now());
    if (DateTime.now().difference(firstSeenAt) < _proximitySustainedDuration) return;

    final snoozedUntil = _proximitySnoozedUntil[tripId];
    if (snoozedUntil != null && DateTime.now().isBefore(snoozedUntil)) return;

    _proximityPromptShowing = true;
    _proximityFirstSeenAt.remove(tripId);
    _stopProximityPolling();

    var answered = false;
    Timer(_proximityPromptTimeout, () {
      if (!answered && mounted) Navigator.of(context, rootNavigator: true).maybePop(false);
    });

    showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Board This Jeepney?'),
        content: Text(
          "You're right next to ${closest.plateNumber} · ${closest.driverName}. "
          "Tap Board to confirm — no need to scan anything.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Not This One'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Board', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    ).then((confirmed) {
      answered = true;
      _proximityPromptShowing = false;
      if (!mounted) return;
      if (confirmed == true) {
        _proximitySnoozedUntil.remove(tripId);
        _boardByTripId(closest);
      } else {
        // Declined, dismissed, or timed out unanswered — silence just this
        // jeepney for a while, then resume watching for it (re-approaching
        // later is still worth another prompt) or anything else nearby.
        _proximitySnoozedUntil[tripId] = DateTime.now().add(_proximitySnoozeDuration);
        _startProximityPolling();
      }
    });
  }

  // Boards without a QR scan — used by both the proximity auto-prompt above
  // and "Book This Jeepney" on the manual list (tapping a jeepney the
  // commuter can already see in the live list is itself a deliberate,
  // specific choice, same trust level as scanning that jeepney's own code).
  // A failure (e.g. the driver's trip ended in between) shows an error and
  // resumes watching instead of pretending it worked — see _handleScanQr's
  // matching fix for why silently proceeding to "You're on Board!" here
  // was a real bug, not just a cosmetic one.
  Future<void> _boardByTripId(_JeepneyOption jeepney) async {
    if (jeepney.tripId == null) return;
    setState(() => _selectedJeepney = jeepney);

    try {
      await ApiClient.post(
        '/api/commuter/board',
        {
          'tripId': jeepney.tripId,
          'regularRiders': _fareBreakdown.regularRiders,
          'studentRiders': _fareBreakdown.studentRiders,
          'seniorRiders': _fareBreakdown.seniorRiders,
        },
        token: UserSession.instance.authToken,
      );
      _boardedTripId = jeepney.tripId;
      if (!mounted) return;
      _simulateQrScan();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      // Resume watching rather than leaving the commuter stuck with
      // polling stopped and no path forward except manually backing out.
      _startFindingJeepneys(_center);
    }
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
          // The real, live-averaged rating for this driver — null/0 for a
          // driver with no ratings yet, shown as "New" rather than a fake
          // number (see _DriverRatingLabel).
          driverRating: (driver['averageRating'] as num?)?.toDouble() ?? 0,
          ratingCount: driver['ratingCount'] as int? ?? 0,
          photoUrl: driver['photoUrl'] as String?,
        );
      });

      // Records the actual boarding (see TripBoarding's doc comment in
      // schema.prisma) so admin's Passenger Monitoring can show who's
      // really on board, and — via the returned tripId — so this booking's
      // history entry, rating, and report all reference the real trip.
      // A failure here now DOES block the "You're on Board!" UX below —
      // it used to be swallowed silently (the driver's trip having just
      // ended, a network hiccup, etc.), which showed a commuter as
      // boarded with nothing actually recorded server-side: no history
      // entry, no fare, and their demand signal (see fulfilledAt's doc
      // comment in schema.prisma) staying stuck as "still waiting"
      // forever since the thing that clears it never ran.
      final boardResponse = await ApiClient.post(
        '/api/commuter/board',
        {
          'qrToken': token,
          'regularRiders': _fareBreakdown.regularRiders,
          'studentRiders': _fareBreakdown.studentRiders,
          'seniorRiders': _fareBreakdown.seniorRiders,
        },
        token: UserSession.instance.authToken,
      );
      _boardedTripId = boardResponse['tripId'] as String?;

      if (!mounted) return;
      _simulateQrScan();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // Shows a compact "You're on Board!" popup right after the QR scan.
  // Tapping the dimmed background dismisses it and advances straight to
  // the boarding-status step — the panel underneath doesn't change until
  // the popup is dismissed.
  void _simulateQrScan() {
    final jeepney = _selectedJeepney;
    final route = _selectedRoute;
    if (jeepney == null || route == null) return;

    _stopProximityPolling();

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.45),
      builder: (_) => _OnBoardDialog(
        route: route,
        jeepney: jeepney,
        fare: _fareBreakdown,
      ),
    ).then((_) {
      if (!mounted) return;
      _goTo(_BookingStep.boardingStatus);
      _startBoardingStatusPoll();
    });
  }

  // Ends this commuter's own ride — the driver doesn't need to be told:
  // they're physically present when someone gets off, so there's nothing
  // for a popup to tell them that they wouldn't already know firsthand.
  // This just closes out the boarding server-side and moves the commuter
  // on to the trip-completed step.
  void _handleEndTrip() {
    final jeepney = _selectedJeepney;
    if (jeepney == null) return;

    _stopBoardingStatusPoll();

    // Best-effort — this is the "I'm about to get off" signal (see
    // TripBoarding.alightedAt's doc comment in schema.prisma), so admin's
    // Passenger Monitoring drops this commuter from "Currently On Board"
    // right away instead of waiting for the whole trip to end.
    unawaited(
      ApiClient.post(
        '/api/commuter/alight',
        {},
        token: UserSession.instance.authToken,
      ).catchError((_) => <String, dynamic>{}),
    );

    _recordTripInHistory();
    _goTo(_BookingStep.tripCompleted);
  }

  // While genuinely on board, checks every few seconds whether the *driver*
  // has ended the trip (see POST /api/driver/trips/:id/end's own cascade,
  // which closes out every still-open boarding the moment that happens) —
  // without this, a commuter sitting on this screen would have no way to
  // find out their ride is over except backing out and back in. Detecting
  // it here means the transition to "trip completed" happens on its own,
  // same screen, no navigation required from them. The same poll also
  // pulls the jeepney's live position (see GET /commuter/active-trip's own
  // doc comment) so the boarding-status map shows it actually moving,
  // instead of frozen wherever it was at the moment of boarding.
  Timer? _boardingStatusPollTimer;

  /// The boarded jeepney's live position — null until the first poll
  /// resolves. Drawn on the main map only while _step is boardingStatus
  /// (see the MarkerLayer in build()).
  LatLng? _boardedJeepneyPosition;

  void _startBoardingStatusPoll() {
    _boardingStatusPollTimer?.cancel();
    _pollActiveTrip(); // fire immediately — no reason to wait 5s for the
    // first position fix or end-trip check.
    _boardingStatusPollTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _pollActiveTrip(),
    );
  }

  void _stopBoardingStatusPoll() {
    _boardingStatusPollTimer?.cancel();
    _boardingStatusPollTimer = null;
    _boardedJeepneyPosition = null;
  }

  Future<void> _pollActiveTrip() async {
    if (!mounted || _step != _BookingStep.boardingStatus) return;
    try {
      final response = await ApiClient.get(
        '/api/commuter/active-trip',
        token: UserSession.instance.authToken,
      );
      if (!mounted || _step != _BookingStep.boardingStatus) return;
      final activeTrip = response['activeTrip'] as Map<String, dynamic>?;
      if (activeTrip == null) {
        // No /alight call here — the driver's own end-trip cascade already
        // closed this boarding server-side; this is purely catching the
        // local UI up to what already happened.
        _stopBoardingStatusPoll();
        _recordTripInHistory();
        _goTo(_BookingStep.tripCompleted);
        return;
      }

      final lat = activeTrip['lat'] as num?;
      final lng = activeTrip['lng'] as num?;
      if (lat != null && lng != null) {
        final position = LatLng(lat.toDouble(), lng.toDouble());
        setState(() => _boardedJeepneyPosition = position);
        // Keeps the jeepney in view as it actually moves, rather than
        // requiring the commuter to manually pan/zoom to follow it.
        try {
          _mapController.move(position, _mapController.camera.zoom);
        } catch (_) {
          // Map not laid out yet on the very first tick — safe to skip.
        }
      }
    } catch (_) {
      // Best-effort — just try again on the next tick.
    }
  }

  // Adds this booking to the commuter's trip history as soon as the trip is
  // marked complete, so every booking — not just this session's view of it
  // — shows up on the History screen afterwards. The "Trip Completed"
  // notification itself now comes from the backend (triggered by the
  // /alight call in _handleEndTrip above), fetched the same way every
  // other server-triggered notification is — no local push needed here
  // anymore.
  void _recordTripInHistory() {
    final jeepney = _selectedJeepney;
    final route = _selectedRoute;
    if (jeepney == null || route == null) return;

    final now = DateTime.now();
    final fare = _fareBreakdown;

    CommuterHistoryScreen.addTrip(
      TripHistoryItem(
        tripId: _boardedTripId ?? 'TRIP-${now.millisecondsSinceEpoch}',
        driverName: jeepney.driverName,
        plateNumber: jeepney.plateNumber,
        photoUrl: jeepney.photoUrl,
        route: route,
        regularRiders: fare.regularRiders,
        studentRiders: fare.studentRiders,
        seniorRiders: fare.seniorRiders,
        dateTime: _formatHistoryDateTime(now),
        fare: fare.totalLabel,
        boardedAt: now,
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
        tripId: _boardedTripId,
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
              // Matches the server's own notifyCommuter call in
              // POST /trips/:tripId/rating — lets the feed de-dup this
              // local copy against that durable one once it syncs in.
              type: 'RATING_SUBMITTED',
              referenceId: _boardedTripId,
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
        tripId: _boardedTripId,
        onSubmit: (reason, details, photo, complaintId) {
          Navigator.of(ctx).pop();
          setState(() => _hasReported = true);
          NotificationsScreen.push(
            AppNotification(
              icon: Icons.shield_rounded,
              iconBackground: AppColors.qrIconColor,
              title: 'Report Received',
              message: 'Your report about ${jeepney.driverName} has been received. Thank you for helping us improve.',
              time: DateTime.now(),
              // Matches the server's own notifyCommuter call in
              // POST /complaints — lets the feed de-dup this local copy
              // against that durable one once it syncs in.
              type: 'COMPLAINT_FILED',
              referenceId: complaintId,
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
                      width: 28,
                      height: 28,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _kBlue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(Icons.person_rounded, size: 15, color: Colors.white),
                      ),
                    ),
                    // Live jeepney positions while actively searching — see
                    // _startFindingJeepneys. Only meaningful during that
                    // step; _nearbyJeepneys is empty everywhere else, so
                    // this naturally shows nothing on the other steps.
                    if (_step == _BookingStep.findingJeepneys)
                      for (final jeepney in _nearbyJeepneys)
                        if (jeepney.position != null)
                          Marker(
                            point: jeepney.position!,
                            width: 30,
                            height: 30,
                            child: GestureDetector(
                              onTap: () => setState(() => _selectedJeepney = jeepney),
                              child: _JeepneyMapPin(
                                selected: jeepney == _selectedJeepney,
                              ),
                            ),
                          ),
                    // The boarded jeepney's live position while riding —
                    // see _pollActiveTrip, which refreshes this every 5s
                    // from the same currentLat/currentLng the driver's own
                    // location pings keep fresh — so it actually moves on
                    // the map instead of sitting frozen at boarding time.
                    if (_step == _BookingStep.boardingStatus && _boardedJeepneyPosition != null)
                      Marker(
                        point: _boardedJeepneyPosition!,
                        width: 30,
                        height: 30,
                        child: const _JeepneyMapPin(selected: true),
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
                    onTap: _handleCloseButton,
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
              : () => _startFindingJeepneys(_center),
        );

      case _BookingStep.findingJeepneys:
        return _FindJeepneysStep(
          jeepneys: _nearbyJeepneys,
          isLoading: _isLoadingNearby,
          error: _nearbyError,
          onRetry: () => _startFindingJeepneys(_center),
          selected: _selectedJeepney,
          onSelect: (jeepney) => setState(() => _selectedJeepney = jeepney),
          onBack: () {
            _stopProximityPolling();
            _goTo(_BookingStep.routeAndCompanions);
          },
          // Tapping a jeepney the commuter can already see live on this list
          // boards it directly — no QR needed, same trust level as the
          // proximity auto-prompt above. "Scan QR Instead" (below) stays
          // as the deterministic fallback for when the list looks wrong.
          onBook: _selectedJeepney?.tripId == null
              ? null
              : () => _boardByTripId(_selectedJeepney!),
          onScanQrInstead: _selectedJeepney == null
              ? null
              : () {
                  _stopProximityPolling();
                  _goTo(_BookingStep.scanQr);
                },
        );

      case _BookingStep.scanQr:
        return _ScanQrStep(
          jeepney: _selectedJeepney!,
          onScan: _handleScanQr,
          onBack: () {
            _goTo(_BookingStep.findingJeepneys);
            _startFindingJeepneys(_center);
          },
        );

      case _BookingStep.boardingStatus:
        return _BoardingStatusStep(
          route: _selectedRoute!,
          jeepney: _selectedJeepney!,
          fare: _fareBreakdown,
          onEndTrip: _handleEndTrip,
        );

      case _BookingStep.tripCompleted:
        return _TripCompletedStep(
          route: _selectedRoute!,
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
    _stopProximityPolling();
    _stopBoardingStatusPoll();
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

/// A jeepney silhouette on a colored circle for the findingJeepneys map —
/// matches the admin website's own jeepney marker (see
/// admin/src/components/LiveMap.tsx's jeepneyIcon) and the driver app's
/// own-position marker, so every surface uses the same glyph for "a
/// jeepney is here." Highlights when this is the currently selected one
/// (tapped from the map, or from the list below).
class _JeepneyMapPin extends StatelessWidget {
  final bool selected;
  const _JeepneyMapPin({required this.selected});

  @override
  Widget build(BuildContext context) {
    final color = selected ? _kBlue : Colors.black87;
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: selected ? 3 : 2),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.4), blurRadius: 6, spreadRadius: 1),
        ],
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.directions_bus_filled_rounded, size: 16, color: Colors.white),
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
              hintText: 'e.g. Pasig – Quiapo',
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

/// "120m away" under 1km, "1.2km away" beyond it — matches how the
/// backend's own distanceMeters (straight-line, see nearby-jeepneys' doc
/// comment in commuter.ts) is best presented: precise enough to be
/// useful, not implying GPS accuracy it doesn't have.
String _formatDistance(int meters) {
  if (meters < 1000) return '${meters}m away';
  return '${(meters / 1000).toStringAsFixed(1)}km away';
}

class _FindJeepneysStep extends StatelessWidget {
  final List<_JeepneyOption> jeepneys;
  final bool isLoading;
  final String? error;
  final VoidCallback onRetry;
  final _JeepneyOption? selected;
  final ValueChanged<_JeepneyOption> onSelect;
  final VoidCallback onBack;
  final VoidCallback? onBook;

  /// Deterministic fallback for when proximity/list matching doesn't cut
  /// it (ambiguous — two jeepneys stopped near each other — or the list
  /// just hasn't picked up the right one yet). Null (hidden) until a
  /// jeepney is selected, same gating as [onBook].
  final VoidCallback? onScanQrInstead;

  const _FindJeepneysStep({
    required this.jeepneys,
    required this.isLoading,
    required this.error,
    required this.onRetry,
    required this.selected,
    required this.onSelect,
    required this.onBack,
    required this.onBook,
    required this.onScanQrInstead,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          title: 'Nearby Jeepneys',
          subtitle: "We'll offer to board automatically once you're right next to one",
          onBack: onBack,
        ),
        const SizedBox(height: 20),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2.4, color: _kBlue)),
          )
        else if (error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                Text(error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 12),
                TextButton(onPressed: onRetry, child: const Text('Try Again')),
              ],
            ),
          )
        else if (jeepneys.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Column(
              children: [
                const Icon(Icons.directions_bus_outlined, size: 32, color: Colors.black26),
                const SizedBox(height: 10),
                const Text(
                  'No jeepneys nearby right now',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                const Text(
                  "Once a driver on this route is close by and active, they'll show up here.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.black45),
                ),
                const SizedBox(height: 12),
                TextButton(onPressed: onRetry, child: const Text('Refresh')),
              ],
            ),
          )
        else
          ...jeepneys.map((jeepney) {
            final isSelected = jeepney == selected;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: isSelected ? const Color(0xFFEAF1FF) : const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  onTap: () => onSelect(jeepney),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: isSelected ? _kBlue : Colors.transparent, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        _DriverAvatar(photoUrl: jeepney.photoUrl, radius: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${jeepney.plateNumber} · ${jeepney.driverName}',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? _kBlue : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_formatDistance(jeepney.distanceMeters)} · ~${jeepney.etaMinutes} min',
                                style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                        _DriverRatingLabel(rating: jeepney.driverRating, ratingCount: jeepney.ratingCount, fontSize: 11),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        const SizedBox(height: 8),
        _PrimaryButton(label: 'Board This Jeepney', onTap: onBook),
        if (onScanQrInstead != null) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: onScanQrInstead,
              child: const Text(
                'Scan QR Instead',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kBlue),
              ),
            ),
          ),
        ],
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
          subtitle: 'Scan any driver\'s QR code to board their jeepney',
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
// `.then()`).
// ---------------------------------------------------------------------------

class _OnBoardDialog extends StatelessWidget {
  final String route;
  final _JeepneyOption jeepney;
  final FareBreakdown fare;

  const _OnBoardDialog({
    required this.route,
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
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _DriverAvatar(photoUrl: jeepney.photoUrl, radius: 14),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${jeepney.plateNumber} · ${jeepney.driverName}',
                        style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600),
                      ),
                      _DriverRatingLabel(rating: jeepney.driverRating, ratingCount: jeepney.ratingCount, fontSize: 11),
                    ],
                  ),
                ),
              ],
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

/// A driver's real profile photo (resolved via [avatarImageProvider]),
/// falling back to a plain person icon for a driver who hasn't uploaded
/// one, or before a QR scan has revealed the real driver at all.
class _DriverAvatar extends StatelessWidget {
  final String? photoUrl;
  final double radius;

  const _DriverAvatar({required this.photoUrl, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final image = avatarImageProvider(photoUrl: photoUrl);
    return CircleAvatar(
      radius: radius,
      backgroundColor: _kBlue,
      backgroundImage: image,
      child: image == null ? Icon(Icons.person, color: Colors.white, size: radius) : null,
    );
  }
}

/// "4.8 · 23 ratings" once this driver's had at least one, otherwise just
/// "New" — never a fake placeholder number (see driverRating's own doc
/// comment on _JeepneyOption for why 0 unambiguously means "no ratings
/// yet": a real average is always >= 1).
class _DriverRatingLabel extends StatelessWidget {
  final double rating;
  final int ratingCount;
  final double fontSize;

  const _DriverRatingLabel({required this.rating, required this.ratingCount, this.fontSize = 12});

  @override
  Widget build(BuildContext context) {
    if (rating <= 0) {
      return Text(
        'New',
        style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: Colors.black45),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.star_rounded, size: fontSize + 2, color: _kYellowDark),
        const SizedBox(width: 2),
        Text(
          '${rating.toStringAsFixed(1)} · $ratingCount rating${ratingCount == 1 ? '' : 's'}',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700, color: Colors.black54),
        ),
      ],
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
// Step 7 — Boarding status. Now shows the full trip recap (route, jeepney,
// companions) alongside the live status and the End Trip button, instead
// of just the plate/driver.
// ---------------------------------------------------------------------------

class _BoardingStatusStep extends StatelessWidget {
  final String route;
  final _JeepneyOption jeepney;
  final FareBreakdown fare;
  final VoidCallback onEndTrip;

  const _BoardingStatusStep({
    required this.route,
    required this.jeepney,
    required this.fare,
    required this.onEndTrip,
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
        const SizedBox(height: 8),
        Row(
          children: [
            _DriverAvatar(photoUrl: jeepney.photoUrl, radius: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${jeepney.plateNumber} · ${jeepney.driverName}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  _DriverRatingLabel(rating: jeepney.driverRating, ratingCount: jeepney.ratingCount),
                ],
              ),
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
              _SummaryRow(label: 'Passengers', value: fare.ridersLabel),
              _SummaryRow(label: 'Fare', value: fare.totalLabel),
            ],
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          "Tap End Trip once you've gotten off.",
          style: TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 64,
          child: ElevatedButton(
            onPressed: onEndTrip,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kYellow,
              foregroundColor: _kBlueDark,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
              elevation: 0,
            ),
            child: const Text(
              'End Trip',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Step 8 — Trip completed. Shows the full trip recap and separates rating
// the driver from reporting them into two distinct actions.
// ---------------------------------------------------------------------------

class _TripCompletedStep extends StatelessWidget {
  final String route;
  final _JeepneyOption jeepney;
  final FareBreakdown fare;
  final bool hasRated;
  final bool hasReported;
  final VoidCallback onRateDriver;
  final VoidCallback onReportDriver;
  final VoidCallback onDone;

  const _TripCompletedStep({
    required this.route,
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
          color: AppColors.secondary,
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
  final String? tripId;
  final ValueChanged<int> onSubmit;

  const _RateDriverSheet({required this.jeepney, required this.tripId, required this.onSubmit});

  @override
  State<_RateDriverSheet> createState() => _RateDriverSheetState();
}

class _RateDriverSheetState extends State<_RateDriverSheet> {
  int _stars = 5;
  bool _isSubmitting = false;
  String? _error;

  Future<void> _handleSubmit() async {
    final tripId = widget.tripId;
    if (tripId == null) {
      setState(() => _error = "This trip couldn't be verified — try rating it from Trip History instead.");
      return;
    }

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      await ApiClient.post(
        '/api/commuter/trips/$tripId/rating',
        {'stars': _stars},
        token: UserSession.instance.authToken,
      );
      if (!mounted) return;
      widget.onSubmit(_stars);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.message;
      });
    }
  }

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
            const SizedBox(height: 10),
            Row(
              children: [
                _DriverAvatar(photoUrl: widget.jeepney.photoUrl, radius: 16),
                const SizedBox(width: 8),
                Text(
                  '${widget.jeepney.driverName} · ${widget.jeepney.plateNumber}',
                  style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600),
                ),
              ],
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
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 20),
            _PrimaryButton(
              label: _isSubmitting ? 'Submitting...' : 'Submit Rating',
              onTap: _isSubmitting ? null : _handleSubmit,
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
  final String? tripId;
  final void Function(String reason, String details, File? photo, String complaintId) onSubmit;

  const _ReportDriverSheet({required this.jeepney, required this.tripId, required this.onSubmit});

  @override
  State<_ReportDriverSheet> createState() => _ReportDriverSheetState();
}

class _ReportDriverSheetState extends State<_ReportDriverSheet> {
  // Matches the backend's COMPLAINT_TYPES enum exactly (see
  // POST /api/commuter/complaints in commuter.ts) — sent as-is as
  // complaintType, so this list can't drift from what the backend accepts.
  static const _reasons = [
    'Reckless Driving',
    'Overcharging',
    'Rude Behavior',
    'Route Deviation',
    'Other',
  ];

  String? _selectedReason;
  final TextEditingController _detailsController = TextEditingController();
  final ImagePicker _picker = ImagePicker();
  File? _photo;
  bool _isSubmitting = false;
  String? _error;

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

  Future<void> _handleSubmit() async {
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

    setState(() {
      _isSubmitting = true;
      _error = null;
    });

    try {
      final response = await ApiClient.uploadFiles(
        '/api/commuter/complaints',
        files: _photo != null ? {'attachment': _photo!.path} : {},
        fields: {
          'plateNumber': widget.jeepney.plateNumber,
          if (widget.tripId != null) 'tripId': widget.tripId!,
          'complaintType': _selectedReason!,
          'description': _detailsController.text.trim(),
        },
        token: UserSession.instance.authToken,
      );
      if (!mounted) return;
      final complaintId = (response['complaint'] as Map<String, dynamic>)['id'] as String;
      widget.onSubmit(_selectedReason!, _detailsController.text.trim(), _photo, complaintId);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _error = e.message;
      });
    }
  }

  // Matches _FileComplaintScreenState's own _fieldDecoration exactly — this
  // sheet and the standalone File a Complaint screen file the exact same
  // report (POST /api/commuter/complaints), just from two different entry
  // points, so they're deliberately styled as the same form.
  InputDecoration _fieldDecoration(String hintText) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Colors.black38, fontWeight: FontWeight.w600, fontSize: 13),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEDEDED)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEDEDED)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.logoBlue, width: 1.5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        decoration: const BoxDecoration(
          color: Color(0xFFF5F6F8),
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
              const SizedBox(height: 10),
              Row(
                children: [
                  _DriverAvatar(photoUrl: widget.jeepney.photoUrl, radius: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.jeepney.driverName} · ${widget.jeepney.plateNumber}',
                    style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.settingsTileBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.settingsIconColor, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'An admin will review this report before any action is taken.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.settingsIconColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text('What Happened?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _selectedReason,
                onChanged: (v) => setState(() => _selectedReason = v),
                decoration: _fieldDecoration('Select a reason'),
                items: _reasons.map((reason) => DropdownMenuItem(value: reason, child: Text(reason))).toList(),
              ),
              const SizedBox(height: 20),
              const Text('Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black)),
              const SizedBox(height: 10),
              TextField(
                controller: _detailsController,
                minLines: 3,
                maxLines: 5,
                decoration: _fieldDecoration('Describe what happened...'),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 20),
              const Text('Photo Evidence (optional)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Colors.black)),
              const SizedBox(height: 10),
              InkWell(
                onTap: _showImageSourceSheet,
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  height: 140,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFEDEDED)),
                    color: Colors.white,
                  ),
                  child: _photo != null
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Image.file(_photo!, fit: BoxFit.cover, width: double.infinity),
                        )
                      : const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_a_photo_outlined, color: Colors.black38, size: 28),
                              SizedBox(height: 6),
                              Text('Tap to add a photo', style: TextStyle(fontSize: 12, color: Colors.black45)),
                            ],
                          ),
                        ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFE23F3F)),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.onPrimary),
                        )
                      : const Text(
                          'Submit Report',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.onPrimary),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

