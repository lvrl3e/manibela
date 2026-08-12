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
import 'commuter_history_screen.dart';
import '../../../core/services/user_session.dart';
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

  @override
  void initState() {
    super.initState();
    _resolveCurrentLocation();
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
    await UserSession.instance.signOut();
    await CommuterHistoryScreen.clearOnLogout();
    await NotificationsScreen.clearOnLogout();

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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JeepneyBookingFlowScreen(commuterName: _commuterName),
      ),
    );
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
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const NotificationsScreen(),
                      ),
                    ),
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
                child: Column(
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
    _mapController.dispose();
    super.dispose();
  }
}

class _LocationFailure {
  final String message;
  const _LocationFailure(this.message);
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

/// Real, pannable/zoomable OpenStreetMap tile view (via flutter_map), with
/// jeepney and POI markers layered on top.
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

  // A few nearby points, offset from the current location, standing in for
  // live jeepney/driver positions until a real feed is wired up.
  List<LatLng> get _jeepneyPositions => [
        LatLng(currentLocation.latitude + 0.004, currentLocation.longitude + 0.003),
        LatLng(currentLocation.latitude - 0.003, currentLocation.longitude - 0.004),
        LatLng(currentLocation.latitude + 0.002, currentLocation.longitude - 0.005),
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
                  width: 24,
                  height: 24,
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
                  ),
                ),

                // Nearby jeepneys.
                for (int i = 0; i < _jeepneyPositions.length; i++)
                  Marker(
                    point: _jeepneyPositions[i],
                    width: 18,
                    height: 18,
                    child: _JeepneyPin(
                      color: [
                        AppColors.logoBlue,
                        AppColors.splashBackground,
                        AppColors.settingsIconColor,
                      ][i % 3],
                    ),
                  ),

                // A couple of points of interest.
                Marker(
                  point: LatLng(
                    currentLocation.latitude + 0.006,
                    currentLocation.longitude - 0.001,
                  ),
                  width: 30,
                  height: 30,
                  child: const _PoiPin(
                    icon: Icons.restaurant,
                    background: AppColors.splashBackground,
                  ),
                ),
                Marker(
                  point: LatLng(
                    currentLocation.latitude - 0.001,
                    currentLocation.longitude + 0.006,
                  ),
                  width: 30,
                  height: 30,
                  child: const _PoiPin(
                    icon: Icons.lock,
                    background: AppColors.logoBlue,
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

class _JeepneyPin extends StatelessWidget {
  final Color color;
  const _JeepneyPin({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class _PoiPin extends StatelessWidget {
  final IconData icon;
  final Color background;

  const _PoiPin({required this.icon, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: background,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(icon, size: 15, color: Colors.white),
    );
  }
}