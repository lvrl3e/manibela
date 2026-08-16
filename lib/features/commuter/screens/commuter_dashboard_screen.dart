import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_assets.dart';
import 'jeepney_booking_flow_screen.dart';
import 'commuter_menu_drawer.dart';
import 'settings_screen.dart';
import 'notifications_screen.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import '../../../core/widgets/logout_confirmation_sheet.dart';
import '../../auth/screens/commuter_login_screen.dart';

const Color _kBlueDark = Color(0xFF0F3EA6);

class CommuterDashboardScreen extends StatefulWidget {
  const CommuterDashboardScreen({super.key});

  @override
  State<CommuterDashboardScreen> createState() =>
      _CommuterDashboardScreenState();
}

class _CommuterDashboardScreenState extends State<CommuterDashboardScreen> {
  // Seeded from the local session, which signup/settings write into. Once a
  // real backend/auth service exists, replace this with a proper fetch of
  // the authenticated user's profile.
  String _commuterName = UserSession.instance.fullName ?? 'Juan Dela Cruz';
  String _commuterId = UserSession.instance.commuterId ?? '—';
  String _mobileNumber = UserSession.instance.mobileNumber ?? '';
  DateTime? _dateOfBirth = UserSession.instance.dateOfBirth;
  String? _photoUrl = UserSession.instance.photoUrl;

  // Fallback used only if GPS is unavailable/denied — San Juan City, Metro
  // Manila. The real value is populated by _resolveCurrentLocation() below.
  static const LatLng _fallbackLocation = LatLng(14.6019, 121.0355);

  final MapController _mapController = MapController();

  LatLng? _currentLocation;
  bool _locatingInProgress = true;
  String? _locationError;

  /// Re-fetches notifications on a timer so the bell badge picks up
  /// server-triggered events (e.g. a complaint resolution) that happen
  /// while the commuter is just sitting on the dashboard — mirrors
  /// DriverDashboardScreen's own polling timer, same reasoning: without
  /// this, nothing here would learn about them until some other action
  /// happened to call fetchRemote() again.
  Timer? _notificationPollTimer;

  /// Set when this commuter has an open boarding somewhere (see GET
  /// /api/commuter/active-trip) — surfaced as a banner offering to jump
  /// straight into the live boarding-status view, for a trip that was
  /// boarded in another session rather than this one.
  ResumedTrip? _activeTrip;

  @override
  void initState() {
    super.initState();
    _resolveCurrentLocation();
    _fetchActiveTrip();
    // So the bell badge reflects real unread notifications right away,
    // not just after the bell is tapped.
    NotificationsScreen.fetchRemote().then((_) {
      if (mounted) setState(() {});
    });
    _notificationPollTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      NotificationsScreen.fetchRemote().then((_) {
        if (mounted) setState(() {});
      });
    });
  }

  Future<void> _fetchActiveTrip() async {
    try {
      final response = await ApiClient.get(
        '/api/commuter/active-trip',
        token: UserSession.instance.authToken,
      );
      if (!mounted) return;
      final raw = response['activeTrip'] as Map<String, dynamic>?;
      setState(() {
        _activeTrip = raw == null
            ? null
            : ResumedTrip(
                tripId: raw['tripId'] as String,
                route: raw['route'] as String? ?? '—',
                driverName: raw['driverName'] as String,
                plateNumber: raw['plateNumber'] as String,
                photoUrl: raw['photoUrl'] as String?,
                driverRating: (raw['averageRating'] as num?)?.toDouble() ?? 0,
                ratingCount: raw['ratingCount'] as int? ?? 0,
                regularRiders: raw['regularRiders'] as int? ?? 1,
                studentRiders: raw['studentRiders'] as int? ?? 0,
                seniorRiders: raw['seniorRiders'] as int? ?? 0,
              );
      });
    } catch (_) {
      // Best-effort — no banner if this fails, same as everything else here.
    }
  }

  void _resumeActiveTrip() {
    final resumed = _activeTrip;
    if (resumed == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JeepneyBookingFlowScreen(commuterName: _commuterName, resumedTrip: resumed),
      ),
    ).then((_) => _fetchActiveTrip());
  }

  Future<void> _resolveCurrentLocation({bool showErrors = false}) async {
    setState(() {
      _locatingInProgress = true;
      _locationError = null;
    });

    try {
      // 1. Make sure location services are actually on for the device.
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw const _LocationFailure(
          'Location services are turned off. Enable them in your device settings.',
        );
      }

      // 2. Check/request permission.
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw const _LocationFailure(
            'Location permission was denied.',
          );
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw const _LocationFailure(
          'Location permission is permanently denied. Enable it from app settings.',
        );
      }

      // 3. Get the actual GPS fix.
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(failure.message)),
        );
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

  Future<void> _handleLogout(BuildContext context) async {
    final confirmed = await showLogoutConfirmationSheet(context);
    if (!confirmed || !context.mounted) return;

    // Trip history and notifications persist across logout now, same as
    // the rest of the account data UserSession.signOut() already keeps on
    // disk — they're account data, not session-scoped.
    await UserSession.instance.signOut();

    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const CommuterLoginScreen()),
      (route) => false,
    );
  }

  Future<void> _openSettings(BuildContext context) async {
    final result = await Navigator.push<SettingsResult>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          initialFullName: _commuterName,
          initialMobileNumber: _mobileNumber,
          initialDateOfBirth: _dateOfBirth,
        ),
      ),
    );

    // Only commit changes if Save Changes was actually tapped. Settings no
    // longer persists the photo on pick — it's staged locally there and
    // only written to UserSession (and returned here) on Save — so backing
    // out of the form leaves everything, including the photo, untouched.
    if (result == null) return;

    setState(() {
      if (result.fullName.isNotEmpty) _commuterName = result.fullName;
      _mobileNumber = result.mobileNumber;
      _dateOfBirth = result.dateOfBirth;
      _photoUrl = result.photoUrl;
    });
  }


  void _handleBook(BuildContext context) {
    // No demand signal fired here anymore — the route isn't known yet at
    // this point, and GET /driver/demand-signals needs one to filter by
    // (see its own doc comment in driver.ts). The signal now fires once a
    // route is actually picked, inside JeepneyBookingFlowScreen itself
    // (see _startDemandSignalKeepAlive in jeepney_booking_flow_screen.dart).
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JeepneyBookingFlowScreen(commuterName: _commuterName),
      ),
      // Re-check active-trip on return, same as _resumeActiveTrip below —
      // without this, closing the booking flow mid-ride (X button, system
      // back) leaves this screen showing whatever it looked like *before*
      // "Sakay na" was tapped (no active trip), even though the trip is
      // still genuinely open server-side. Looks exactly like the trip
      // ended when it didn't.
    ).then((_) => _fetchActiveTrip());
  }

  // Marks everything read (clearing the bell badge) right when it's
  // tapped, rather than waiting for the feed screen to fully open.
  Future<void> _openNotifications(BuildContext context) async {
    // Fetch first so the "mark read" call below covers anything that
    // arrived since the last fetch, not just what was already cached.
    await NotificationsScreen.fetchRemote();
    await NotificationsScreen.markAllRead();
    if (!mounted) return;
    setState(() {});
    if (!context.mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
  }

  void _recenterMap() {
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16);
    }
    // Also refresh the GPS fix in case the device has moved.
    _resolveCurrentLocation(showErrors: true);
  }

  @override
  Widget build(BuildContext context) {
    final mapCenter = _currentLocation ?? _fallbackLocation;

    return Scaffold(
      backgroundColor: const Color(0xFFE9ECEE),
      drawer: CommuterMenuDrawer(
        commuterName: _commuterName,
        commuterId: _commuterId,
        photoUrl: _photoUrl,
        onSettingsTap: () => _openSettings(context),
        onLogoutTap: () => _handleLogout(context),
      ),
      body: Stack(
        children: [
          // Full-screen live OpenStreetMap.
          Positioned.fill(
            child: _LiveMap(
              mapController: _mapController,
              currentLocation: mapCenter,
              hasRealFix: _currentLocation != null && _locationError == null,
              onRecenter: _recenterMap,
            ),
          ),

          if (_locatingInProgress)
            const Positioned(
              top: 70,
              left: 0,
              right: 0,
              child: Center(
                child: _StatusPill(
                  icon: null,
                  label: 'Getting your location…',
                  showSpinner: true,
                ),
              ),
            )
          else if (_locationError != null)
            Positioned(
              top: 70,
              left: 16,
              right: 16,
              child: Center(
                child: _StatusPill(
                  icon: Icons.location_off_rounded,
                  label: _locationError!,
                  onTap: () => _resolveCurrentLocation(showErrors: true),
                ),
              ),
            ),

          // Floating top bar: menu (left) + notifications (right).
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Builder(
                    builder: (context) => _RoundIconButton(
                      icon: Icons.menu,
                      onTap: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  _RoundIconButton(
                    icon: Icons.notifications_none_rounded,
                    badgeCount: NotificationsScreen.unreadCount,
                    onTap: () => _openNotifications(context),
                  ),
                ],
              ),
            ),
          ),

          // Bottom sheet: "Choose Service" + Book button.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
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
                child: _activeTrip != null
                    ? _ActiveTripBanner(trip: _activeTrip!, onTap: _resumeActiveTrip)
                    : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.map_outlined,
                            color: Colors.black87, size: 20),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Find Nearby Jeepneys',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => _handleBook(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(26),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
  'Sakay na',
  style: TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w800,
    color: _kBlueDark,
  ),
),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _notificationPollTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }
}

class _LocationFailure {
  final String message;
  const _LocationFailure(this.message);
}

/// Replaces the "Find Nearby Jeepneys" / "Sakay na" card when this
/// commuter already has an open boarding elsewhere (see
/// [_CommuterDashboardScreenState._fetchActiveTrip]) — starting a new
/// booking wouldn't make sense while already mid-trip, so this offers to
/// resume the live boarding-status view for the real one instead.
class _ActiveTripBanner extends StatelessWidget {
  final ResumedTrip trip;
  final VoidCallback onTap;

  const _ActiveTripBanner({required this.trip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.directions_bus_filled_rounded, color: AppColors.logoBlue, size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                "You're currently on a trip",
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.black87),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '${trip.plateNumber} · ${trip.driverName} · ${trip.route}',
          style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              elevation: 0,
            ),
            child: const Text(
              'View Trip',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: _kBlueDark),
            ),
          ),
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final bool showSpinner;
  final VoidCallback? onTap;

  const _StatusPill({
    required this.icon,
    required this.label,
    this.showSpinner = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      elevation: 3,
      shadowColor: Colors.black26,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSpinner)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else if (icon != null)
                Icon(icon, size: 16, color: const Color(0xFFE23F3F)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black87,
                  ),
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                const Icon(Icons.refresh_rounded,
                    size: 14, color: AppColors.logoBlue),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
              padding: const EdgeInsets.all(10),
              child: Icon(icon, size: 22, color: Colors.black87),
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

/// Real, pannable/zoomable OpenStreetMap tile view (via flutter_map) —
/// just the commuter's own position. Nearby jeepneys deliberately don't
/// show here anymore: they only appear once the commuter has actually
/// committed to looking for a ride (tapped "Sakay na" and picked a route),
/// inside JeepneyBookingFlowScreen's own map/list — see that screen's
/// _startFindingJeepneys.
class _LiveMap extends StatelessWidget {
  final MapController mapController;
  final LatLng currentLocation;
  final bool hasRealFix;
  final VoidCallback onRecenter;

  const _LiveMap({
    required this.mapController,
    required this.currentLocation,
    required this.hasRealFix,
    required this.onRecenter,
  });

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
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.manibel.app',
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
                // Current location — greyed out until we have a real GPS fix.
                Marker(
                  point: currentLocation,
                  width: 30,
                  height: 30,
                  child: Container(
                    decoration: BoxDecoration(
                      color: hasRealFix
                          ? AppColors.logoBlue
                          : Colors.black38,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(
                          color: (hasRealFix
                                  ? AppColors.logoBlue
                                  : Colors.black38)
                              .withOpacity(0.4),
                          blurRadius: 8,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.person_rounded, size: 16, color: Colors.white),
                  ),
                ),
              ],
            ),
          ],
        ),

        // Map controls, bottom-right — mirrors the reference's floating
        // location/layers buttons.
        Positioned(
          right: 12,
          bottom: 160,
          child: Column(
            children: [
              _RoundIconButton(
                icon: Icons.my_location_rounded,
                onTap: onRecenter,
              ),
              const SizedBox(height: 10),
              _RoundIconButton(icon: Icons.layers_outlined, onTap: () {}),
            ],
          ),
        ),
      ],
    );
  }
}

