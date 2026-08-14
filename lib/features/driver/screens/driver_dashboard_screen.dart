import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_operations_log.dart';
import '../../../core/services/driver_session.dart';
import '../../../core/utils/avatar_image.dart';
import '../../../core/widgets/logout_confirmation_sheet.dart';
import '../../auth/screens/driver_login_screen.dart';
import 'driver_daily_operations_screen.dart';
import 'driver_history_screen.dart';
import 'driver_menu_drawer.dart';
import 'driver_monthly_analytics_screen.dart';
import 'driver_notifications_screen.dart';
import 'driver_qr_code_screen.dart';
import 'driver_settings_screen.dart';
import 'driver_start_trip_screen.dart';
import 'driver_trip_in_progress_screen.dart';
import 'driver_weekly_analytics_screen.dart';

class DriverDashboardScreen extends StatefulWidget {
  const DriverDashboardScreen({super.key});

  @override
  State<DriverDashboardScreen> createState() => _DriverDashboardScreenState();
}

/// A trip currently in progress — exists only in memory between "Start
/// Trip" and "End Trip", same as everything else in this mocked app. No
/// passenger tracking here on purpose — drivers shouldn't be interacting
/// with the phone while driving.
class _ActiveTrip {
  final String route;
  final String plateNumber;
  final DateTime startTime;

  const _ActiveTrip({
    required this.route,
    required this.plateNumber,
    required this.startTime,
  });
}

class _DriverDashboardScreenState extends State<DriverDashboardScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Seeded from the local driver session, which signup/login write into.
  // Once a real backend/auth service exists, replace this with a proper
  // fetch of the authenticated driver's profile.
  String _driverName = DriverSession.instance.fullName ?? 'Driver';
  String _driverId = DriverSession.instance.driverId ?? '—';
  String? _photoUrl = DriverSession.instance.photoUrl;

  // Trip state — "online" now just means "currently on a trip" instead of a
  // manually-flipped switch, since Start/End Trip is what actually drives
  // it.
  _ActiveTrip? _activeTrip;

  // Backend-sourced today's-stats — authoritative across devices, and the
  // only source for Today's Trips (shows 0 until this resolves, rather
  // than a locally-cached guess). Earnings falls back to
  // DriverOperationsLog's local store if this hasn't loaded yet/fails.
  int? _tripsTodayRemote;
  double? _earningsTodayRemote;

  bool get _isOnline => _activeTrip != null;

  // Fallback used only if GPS is unavailable/denied — San Juan City, Metro
  // Manila. Mirrors the commuter dashboard's real-map setup exactly.
  static const LatLng _fallbackLocation = LatLng(14.6019, 121.0355);

  final MapController _mapController = MapController();
  LatLng? _currentLocation;
  bool _locatingInProgress = true;
  String? _locationError;

  // Separate, non-interactive controller for the small dashboard preview —
  // kept apart from _mapController (used by the expanded modal) so each
  // FlutterMap instance owns exactly one controller for its whole lifetime.
  final MapController _previewMapController = MapController();

  /// Re-fetches notifications on a timer so the bell badge picks up
  /// admin-initiated events (e.g. a short-trip review) that happen
  /// entirely outside this app while the driver is just sitting on the
  /// dashboard — without this, nothing here would learn about them until
  /// some other action happened to call fetchRemote() again. Same cadence
  /// the admin site's own notification bell polls at.
  Timer? _notificationPollTimer;

  @override
  void initState() {
    super.initState();
    _resolveCurrentLocation();
    // So the bell badge reflects real unread notifications right away,
    // not just after the bell is tapped.
    DriverNotificationsScreen.fetchRemote().then((_) {
      if (mounted) setState(() {});
    });
    _fetchTodayStats();
    _notificationPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      DriverNotificationsScreen.fetchRemote().then((_) {
        if (mounted) setState(() {});
      });
    });
  }

  /// Best-effort pull of today's trip count / earnings from the backend —
  /// authoritative across devices, unlike the local stores this falls
  /// back to. Never blocks the UI; a failure just leaves the fallback in
  /// place.
  Future<void> _fetchTodayStats() async {
    final token = DriverSession.instance.authToken;
    if (token == null) return;
    try {
      final response = await ApiClient.get('/api/driver/today-stats', token: token);
      if (!mounted) return;
      setState(() {
        _tripsTodayRemote = response['tripsToday'] as int?;
        final earnings = response['earningsToday'];
        _earningsTodayRemote = earnings == null ? null : (earnings as num).toDouble();
      });
    } catch (_) {
      // Keep whatever's currently shown (local fallback).
    }
  }

  @override
  void dispose() {
    _notificationPollTimer?.cancel();
    _mapController.dispose();
    _previewMapController.dispose();
    super.dispose();
  }

  Future<void> _resolveCurrentLocation({bool showErrors = false}) async {
    setState(() {
      _locatingInProgress = true;
      _locationError = null;
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const _LocationFailure(
          'Location services are turned off. Enable them in your device settings.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw const _LocationFailure('Location permission was denied.');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocationFailure(
          'Location permission is permanently denied. Enable it from app settings.',
        );
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );

      if (!mounted) return;
      final resolved = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentLocation = resolved;
        _locatingInProgress = false;
      });
      _mapController.move(resolved, 16);
    } on _LocationFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _currentLocation ??= _fallbackLocation;
        _locatingInProgress = false;
        _locationError = failure.message;
      });
      if (showErrors) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentLocation ??= _fallbackLocation;
        _locatingInProgress = false;
        _locationError = 'Could not get your current location.';
      });
      if (showErrors) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get your current location.')),
        );
      }
    }
  }

  void _recenterMap() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16);
    }
    _resolveCurrentLocation(showErrors: true);
  }

  Future<void> _handleLogout() async {
    final confirmed = await showLogoutConfirmationSheet(context);
    if (!confirmed || !mounted) return;

    // Navigate first, clear session second — even if signOut() somehow
    // throws (a corrupt SharedPreferences write, etc.), the driver still
    // ends up back at the login screen instead of silently staying on
    // the dashboard with no visible feedback.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const DriverLoginScreen()),
      (route) => false,
    );
    try {
      // Trip history and notifications persist across logout now, same as
      // the rest of the account data DriverSession.signOut() already keeps
      // on disk — they're account data, not session-scoped.
      await DriverSession.instance.signOut();
    } catch (_) {
      // Already navigated away — nothing left to do but not crash.
    }
  }

  Future<void> _openSettings() async {
    final result = await Navigator.push<DriverSettingsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => DriverSettingsScreen(
          initialFullName: _driverName,
          initialMobileNumber: DriverSession.instance.mobileNumber,
        ),
      ),
    );

    if (result == null) return;

    setState(() {
      if (result.fullName.isNotEmpty) _driverName = result.fullName;
      _photoUrl = result.photoUrl;
    });
  }

  void _openQrCode() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverQrCodeScreen()));
  }

  // Fetches first so mark-read covers anything that arrived since the
  // last fetch, then marks everything read (clearing the bell badge)
  // right away, rather than waiting for the feed screen to fully open.
  Future<void> _openNotifications() async {
    await DriverNotificationsScreen.fetchRemote();
    await DriverNotificationsScreen.markAllRead();
    if (!mounted) return;
    setState(() {});
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverNotificationsScreen()));
  }

  Future<void> _openTripHistory() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverHistoryScreen()));
    // Today's Trips comes from the backend (see _fetchTodayStats) — re-pull
    // it once the driver's back, in case anything changed while this
    // screen was open.
    _fetchTodayStats();
  }

  Future<void> _openDailyOperations() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverDailyOperationsScreen()));
    // The Earnings stat card reads DriverOperationsLog.todayEntry live, so
    // just refresh the build once the driver's back from logging today's
    // numbers — and re-pull the backend figure too, since that's what the
    // card prefers when available.
    if (mounted) setState(() {});
    _fetchTodayStats();
  }

  void _openWeeklyAnalytics() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverWeeklyAnalyticsScreen()));
  }

  void _openMonthlyAnalytics() {
    Navigator.push(context, MaterialPageRoute(builder: (_) => const DriverMonthlyAnalyticsScreen()));
  }

  // ===================================================================
  // START / END TRIP
  // ===================================================================

  Future<void> _handleStartTrip() async {
    final result = await Navigator.push<DriverStartTripResult>(
      context,
      MaterialPageRoute(
        builder: (_) => DriverStartTripScreen(
          currentLocation: _currentLocation ?? _fallbackLocation,
          hasRealFix: _currentLocation != null && _locationError == null,
        ),
      ),
    );

    if (result == null || !mounted) return;

    final trip = _ActiveTrip(
      route: result.route,
      plateNumber: result.plateNumber,
      startTime: DateTime.now(),
    );
    setState(() => _activeTrip = trip);

    // Start Trip immediately hands off to the dedicated live-tracking
    // screen — the vehicle marker actually moves there, and that's also
    // the only place "End Trip" lives once a trip is underway. That
    // screen is what actually calls the backend's /trips/start (see
    // DriverTripInProgressScreen._initializeTrip), which is what
    // triggers the real "Trip Started" notification — no local push
    // needed here anymore.
    await _openTripInProgress(trip);
  }

  Future<void> _openTripInProgress(_ActiveTrip trip) async {
    final ended = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => DriverTripInProgressScreen(
          route: trip.route,
          plateNumber: trip.plateNumber,
          startTime: trip.startTime,
          initialLocation: _currentLocation ?? _fallbackLocation,
        ),
      ),
    );

    if (!mounted) return;
    if (ended == true) {
      // The backend already has this trip (POST /trips/:id/end already
      // ran) — re-pull today's-stats so the Today's Trips card reflects
      // it, and clear the active-trip state.
      setState(() => _activeTrip = null);
      _fetchTodayStats();
      // Ending the trip also fired a "Trip Completed" notification
      // server-side (see driver.ts's /trips/:id/end) — without this, the
      // bell badge stays stale until the driver opens Notifications
      // manually (which does its own fresh fetch) or logs out and back in.
      DriverNotificationsScreen.fetchRemote().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  String _timeOfDay(DateTime dt) {
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour12:$minute $period';
  }

  void _openFullMapRoute() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildExpandedMapModal(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    // No PopScope wrapper here on purpose — driver login now reaches this
    // screen via pushAndRemoveUntil, so it's already the root route and
    // there's nothing left underneath for the back button to reveal.
    // Logout only ever happens through the explicit confirm sheet in the
    // drawer.
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF9FAFB),

      drawer: DriverMenuDrawer(
        driverName: _driverName,
        driverId: _driverId,
        photoUrl: _photoUrl,
        onSettingsTap: _openSettings,
        onQrCodeTap: _openQrCode,
        onTripHistoryTap: _openTripHistory,
        onLogoutTap: _handleLogout,
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      // A custom circular button instead of FloatingActionButton — FAB
      // ignores a wrapping Container's size (it stays at its own default
      // 56x56), so the icon+label content was overflowing the circle.
      // This SizedBox size is the button's actual, real size.
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: _activeTrip == null ? AppColors.primary : AppColors.logoBlue,
          shape: CircleBorder(
            side: BorderSide(
              color: _activeTrip == null ? const Color(0xFFE0A800) : const Color(0xFF0F3EA6),
              width: 1.5,
            ),
          ),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _activeTrip == null ? _handleStartTrip : () => _openTripInProgress(_activeTrip!),
            child: SizedBox(
              width: 82,
              height: 82,
              child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _activeTrip == null ? Icons.directions_bus : Icons.map_rounded,
                color: _activeTrip == null ? AppColors.onPrimary : Colors.white,
                size: 30,
              ),
              const SizedBox(height: 4),
              Text(
                _activeTrip == null ? 'Start Trip' : 'View Trip',
                style: TextStyle(
                  color: _activeTrip == null ? AppColors.onPrimary : Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
              ),
            ),
          ),
        ),
      ),

      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Header Bar — round white icon buttons, matching the
              // commuter dashboard's floating menu/notifications pair.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _RoundIconButton(
                    icon: Icons.menu,
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Sans-Serif'),
                      children: [
                        TextSpan(text: 'Manibel', style: TextStyle(color: AppColors.logoBlue)),
                        TextSpan(text: 'App', style: TextStyle(color: AppColors.logoRed)),
                      ],
                    ),
                  ),
                  _RoundIconButton(
                    icon: Icons.notifications_none_rounded,
                    badgeCount: DriverNotificationsScreen.unreadCount,
                    onTap: _openNotifications,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Driver Profile Header Card — same yellow gradient banner
              // convention used across the commuter side.
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, Color(0xFFFFDE7A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 2)),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                      child: CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xFFD9D9D9),
                        backgroundImage: avatarImageProvider(photoUrl: _photoUrl),
                        child: avatarImageProvider(photoUrl: _photoUrl) == null
                            ? const Icon(Icons.person, size: 32, color: AppColors.textSecondary)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _driverName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.onPrimary),
                          ),
                          Text(
                            'Driver ID: $_driverId',
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.onPrimary),
                          ),
                        ],
                      ),
                    ),
                    // Online/Offline status — reflects whether a trip is
                    // actually active, no longer a manual toggle.
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _isOnline ? Colors.green : AppColors.errorRed),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(radius: 4, backgroundColor: _isOnline ? Colors.green : AppColors.errorRed),
                          const SizedBox(width: 6),
                          Text(
                            _isOnline ? 'On Trip' : 'Offline',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: _isOnline ? Colors.green.shade800 : AppColors.errorRed,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              if (_activeTrip != null) ...[
                _buildActiveTripCard(),
                const SizedBox(height: 16),
              ],

              // Live Map Preview — a real, pannable OpenStreetMap view (via
              // flutter_map), not a painted placeholder.
              GestureDetector(
                onTap: _openFullMapRoute,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2)),
                    ],
                  ),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Where Passengers Are Waiting',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.textPrimary),
                            ),
                            Row(
                              children: [
                                CircleAvatar(radius: 4, backgroundColor: _locatingInProgress ? Colors.orange : Colors.green),
                                const SizedBox(width: 4),
                                Text(
                                  _locatingInProgress ? 'Locating…' : 'Live',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _locatingInProgress ? Colors.orange.shade800 : Colors.green,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                        child: SizedBox(
                          height: 180,
                          width: double.infinity,
                          child: Stack(
                            children: [
                              IgnorePointer(
                                child: _DriverLiveMap(
                                  mapController: _previewMapController,
                                  currentLocation: _currentLocation ?? _fallbackLocation,
                                  hasRealFix: _currentLocation != null && _locationError == null,
                                  interactive: false,
                                ),
                              ),
                              Positioned(
                                top: 10,
                                left: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    _activeTrip != null ? 'Route: ${_activeTrip!.route}' : 'Tap to view live map',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(color: AppColors.logoBlue, borderRadius: BorderRadius.circular(12)),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.zoom_out_map, size: 14, color: Colors.white),
                                      SizedBox(width: 4),
                                      Text('Tap to Expand', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                    ],
                                  ),
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
              const SizedBox(height: 16),

              // Dynamic 2-Card Stats Row (Today's Trips & Earnings) — now
              // driven by persisted trip history / operations log, not
              // fake constructor defaults or session-only counters.
              Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.directions_bus_filled,
                      iconBg: const Color(0xFFDBEAFE),
                      iconColor: AppColors.logoBlue,
                      title: "Today's Trips",
                      value: '${_tripsTodayRemote ?? 0}',
                      subtitle: 'Trips',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      icon: Icons.account_balance_wallet,
                      iconBg: AppColors.qrTileBg,
                      iconColor: AppColors.qrIconColor,
                      title: 'Earnings',
                      value: '₱${(_earningsTodayRemote ?? DriverOperationsLog.todayEntry?.totalEarnings ?? 0).toStringAsFixed(0)}',
                      subtitle: 'Today',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              _buildNavigationCard(
                icon: Icons.local_gas_station,
                iconBg: AppColors.settingsTileBg,
                iconColor: AppColors.settingsIconColor,
                title: 'Daily Operations Dashboard',
                subtitle: 'Check if your revenue is higher than your gas expense',
                onTap: _openDailyOperations,
              ),
              const SizedBox(height: 12),

              _buildNavigationCard(
                icon: Icons.bar_chart_rounded,
                iconBg: const Color(0xFFDBEAFE),
                iconColor: AppColors.logoBlue,
                title: 'Weekly Analytics Report',
                subtitle: 'See your earnings, expenses, and net income trend',
                onTap: _openWeeklyAnalytics,
              ),
              const SizedBox(height: 12),

              _buildNavigationCard(
                icon: Icons.insights_rounded,
                iconBg: AppColors.qrTileBg,
                iconColor: AppColors.qrIconColor,
                title: 'Monthly Analytics & Performance',
                subtitle: 'Review this month\'s totals and your best day',
                onTap: _openMonthlyAnalytics,
              ),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  // ===================================================================
  // ACTIVE TRIP CARD — route, plate/start time, live passenger stepper.
  // ===================================================================

  Widget _buildActiveTripCard() {
    final trip = _activeTrip!;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _openTripInProgress(trip),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.logoBlue.withOpacity(0.25)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(color: AppColors.logoBlue, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    trip.route,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(20)),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(radius: 3, backgroundColor: Colors.green),
                      SizedBox(width: 4),
                      Text('LIVE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.green)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${trip.plateNumber} · Started ${_timeOfDay(trip.startTime)}',
              style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            const Row(
              children: [
                Icon(Icons.map_rounded, size: 12, color: AppColors.logoBlue),
                SizedBox(width: 4),
                Text(
                  'Tap to view live map and end trip',
                  style: TextStyle(fontSize: 10, color: AppColors.logoBlue, fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Stat Card Widget Builder
  Widget _buildStatCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                Text(
                  value,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                Text(subtitle, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Navigation Option Builder
  Widget _buildNavigationCard({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.logoBlue),
          ],
        ),
      ),
    );
  }

  // Expanded, fully interactive live map modal.
  Widget _buildExpandedMapModal(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _activeTrip != null ? _activeTrip!.route : 'Where Passengers Are Waiting',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _locationError ?? 'Your position and nearby waiting passengers',
                      style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _DriverLiveMap(
              mapController: _mapController,
              currentLocation: _currentLocation ?? _fallbackLocation,
              hasRealFix: _currentLocation != null && _locationError == null,
              onRecenter: _recenterMap,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationFailure {
  final String message;
  const _LocationFailure(this.message);
}

// Round white icon button — same look as the commuter dashboard's floating
// menu/notifications buttons.
class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  const _RoundIconButton({required this.icon, required this.onTap, this.badgeCount = 0});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: Colors.black26,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Icon(icon, size: 24, color: Colors.black87),
            ),
          ),
        ),
        if (badgeCount > 0)
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              constraints: const BoxConstraints(minWidth: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFE23F3F),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                badgeCount > 9 ? '9+' : '$badgeCount',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
              ),
            ),
          ),
      ],
    );
  }
}

// ===========================================================================
// REAL LIVE MAP — OpenStreetMap tiles via flutter_map, same pattern as the
// commuter dashboard's map. `interactive: false` renders a static preview
// (used in the small dashboard card); the expanded modal gets full
// pan/zoom plus a recenter button.
// ===========================================================================

class _DriverLiveMap extends StatelessWidget {
  final MapController mapController;
  final LatLng currentLocation;
  final bool hasRealFix;
  final VoidCallback? onRecenter;
  final bool interactive;

  const _DriverLiveMap({
    required this.mapController,
    required this.currentLocation,
    required this.hasRealFix,
    this.onRecenter,
    this.interactive = true,
  });

  // A few nearby points, offset from the current location, standing in for
  // passengers waiting along the route until a real feed is wired up.
  List<_WaitingStop> get _waitingStops => [
        _WaitingStop(
          point: LatLng(currentLocation.latitude + 0.004, currentLocation.longitude + 0.003),
          count: 5,
        ),
        _WaitingStop(
          point: LatLng(currentLocation.latitude - 0.003, currentLocation.longitude - 0.004),
          count: 8,
        ),
        _WaitingStop(
          point: LatLng(currentLocation.latitude + 0.002, currentLocation.longitude - 0.005),
          count: 3,
        ),
      ];

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: mapController,
          options: MapOptions(
            initialCenter: currentLocation,
            initialZoom: 15,
            minZoom: 3,
            maxZoom: 19,
            interactionOptions: InteractionOptions(
              flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.manibel.app',
              maxZoom: 19,
            ),
            if (interactive)
              RichAttributionWidget(
                attributions: [TextSourceAttribution('© OpenStreetMap contributors', onTap: () {})],
              ),
            MarkerLayer(
              markers: [
                Marker(
                  point: currentLocation,
                  width: 24,
                  height: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      color: hasRealFix ? AppColors.logoBlue : Colors.black38,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: (hasRealFix ? AppColors.logoBlue : Colors.black38).withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                  ),
                ),
                if (interactive)
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
        if (interactive && onRecenter != null)
          Positioned(
            right: 12,
            bottom: 20,
            child: _RoundIconButton(icon: Icons.my_location_rounded, onTap: onRecenter!),
          ),
      ],
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
