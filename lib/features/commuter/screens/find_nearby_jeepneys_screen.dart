import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../../core/constants/app_colors.dart';

/// -----------------------------------------------------------------------
/// MODELS
/// -----------------------------------------------------------------------

/// Represents a single jeepney unit that can be tracked on the map.
class JeepneyModel {
  final String id; // e.g. "MB-001"
  final String route; // e.g. "Bayan Terminal - Plaza"
  final String driverName;
  final int seatingCapacity;
  final double distanceKm;
  final int etaMinutes;
  final LatLng position;
  final bool onTrip;

  const JeepneyModel({
    required this.id,
    required this.route,
    required this.driverName,
    required this.seatingCapacity,
    required this.distanceKm,
    required this.etaMinutes,
    required this.position,
    this.onTrip = true,
  });

  /// Color-codes the ETA the same way the design does:
  /// green (<= 5 min), amber (<= 8 min), red (> 8 min).
  Color get etaColor {
    if (etaMinutes <= 5) return const Color(0xFF2E9E4F);
    if (etaMinutes <= 8) return const Color(0xFFE0A400);
    return const Color(0xFFD64545);
  }
}

/// Progress of the currently-tracked trip, used on the "Estimated Arrival"
/// panel.
class TripProgressModel {
  final String originLabel;
  final String destinationLabel;
  final double progress; // 0.0 - 1.0
  final double distanceTraveledKm;
  final int estimatedTotalMinutes;

  const TripProgressModel({
    required this.originLabel,
    required this.destinationLabel,
    required this.progress,
    required this.distanceTraveledKm,
    required this.estimatedTotalMinutes,
  });
}

/// Which panel is currently showing at the bottom of the screen.
enum _PanelState {
  nearbyList, // Screen 1
  tripDetail, // Screen 2
  sharePrompt, // Screen 3
  sharingActive, // Screen 4
}

/// -----------------------------------------------------------------------
/// SCREEN
/// -----------------------------------------------------------------------

class FindNearbyJeepneysScreen extends StatefulWidget {
  const FindNearbyJeepneysScreen({
    super.key,
    this.commuterName = 'Guest',
    this.initialCameraPosition = const LatLng(14.5764, 121.0851), // Pasig
  });

  final String commuterName;
  final LatLng initialCameraPosition;

  @override
  State<FindNearbyJeepneysScreen> createState() =>
      _FindNearbyJeepneysScreenState();
}

class _FindNearbyJeepneysScreenState extends State<FindNearbyJeepneysScreen> {
  GoogleMapController? _mapController;
  _PanelState _panelState = _PanelState.nearbyList;
  JeepneyModel? _selectedJeepney;
  int _passengerCount = 0;
  bool _isSharing = false;

  // Location permission state. The map widget must not set
  // myLocationEnabled: true until this resolves to true, or the
  // plugin can hang on Android waiting for a permission it was
  // never granted.
  bool _locationChecked = false;
  bool _locationGranted = false;

  @override
  void initState() {
    super.initState();
    _ensureLocationPermission();
  }

  Future<void> _ensureLocationPermission() async {
    bool granted = false;
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        granted = permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse;
      }
    } catch (_) {
      // Leave granted = false; the map still renders, just without
      // the blue "my location" dot.
    }
    if (mounted) {
      setState(() {
        _locationChecked = true;
        _locationGranted = granted;
      });
    }
  }

  // TODO: replace with a live feed (e.g. websocket / Firestore stream).
  final List<JeepneyModel> _nearbyJeepneys = const [
    JeepneyModel(
      id: 'MB-001',
      route: 'Bayan Terminal - Plaza',
      driverName: 'Juan Dela Cruz',
      seatingCapacity: 24,
      distanceKm: 0.2,
      etaMinutes: 5,
      position: LatLng(14.5790, 121.0870),
    ),
    JeepneyModel(
      id: 'MB-012',
      route: 'Bayan Terminal - Plaza',
      driverName: 'Ramon Santos',
      seatingCapacity: 16,
      distanceKm: 1.2,
      etaMinutes: 8,
      position: LatLng(14.5810, 121.0900),
    ),
    JeepneyModel(
      id: 'MB-025',
      route: 'Bayan Terminal - Plaza',
      driverName: 'Mario Reyes',
      seatingCapacity: 24,
      distanceKm: 1.8,
      etaMinutes: 10,
      position: LatLng(14.5745, 121.0830),
    ),
  ];

  static const TripProgressModel _mockTripProgress = TripProgressModel(
    originLabel: 'Bayan Terminal',
    destinationLabel: 'Plaza',
    progress: 0.45,
    distanceTraveledKm: 3.6,
    estimatedTotalMinutes: 18,
  );

  Set<Marker> get _markers {
    return _nearbyJeepneys.map((jeepney) {
      final bool selected = jeepney.id == _selectedJeepney?.id;
      return Marker(
        markerId: MarkerId(jeepney.id),
        position: jeepney.position,
        icon: BitmapDescriptor.defaultMarkerWithHue(
          selected ? BitmapDescriptor.hueYellow : BitmapDescriptor.hueAzure,
        ),
        onTap: () => _selectJeepney(jeepney),
      );
    }).toSet();
  }

  void _selectJeepney(JeepneyModel jeepney) {
    setState(() {
      _selectedJeepney = jeepney;
      _panelState = _PanelState.tripDetail;
    });
    _mapController?.animateCamera(CameraUpdate.newLatLng(jeepney.position));
  }

  void _backToList() {
    setState(() {
      _panelState = _PanelState.nearbyList;
      _selectedJeepney = null;
    });
  }

  void _openSharePrompt() {
    setState(() => _panelState = _PanelState.sharePrompt);
  }

  void _incrementPassengers() {
    setState(() => _passengerCount++);
  }

  void _decrementPassengers() {
    if (_passengerCount == 0) return;
    setState(() => _passengerCount--);
  }

  void _confirmShare() {
    setState(() {
      _isSharing = true;
      _panelState = _PanelState.sharingActive;
    });
    // TODO: hook up to a real location-broadcast service.
  }

  void _cancelShare() {
    setState(() {
      _isSharing = false;
      _panelState = _PanelState.tripDetail;
      _passengerCount = 0;
    });
    // TODO: stop broadcasting the commuter's live location.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          _buildMap(),
          _buildBackButton(),
          _buildFloatingJeepneyBadge(),
          _buildTopCard(),
          _buildBottomPanel(),
          if (_panelState != _PanelState.sharePrompt &&
              _panelState != _PanelState.sharingActive)
            _buildFloatingShareFab(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // MAP LAYER
  // ---------------------------------------------------------------------

  Widget _buildMap() {
    // Wait for the permission check to resolve before creating the
    // GoogleMap widget with myLocationEnabled: true — enabling it
    // before Android has actually granted permission is what causes
    // the map (and sometimes the whole screen) to hang.
    if (!_locationChecked) {
      return const ColoredBox(
        color: Color(0xFFE9ECEE),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return GoogleMap(
      initialCameraPosition: CameraPosition(
        target: widget.initialCameraPosition,
        zoom: 15,
      ),
      onMapCreated: (controller) => _mapController = controller,
      markers: _markers,
      myLocationEnabled: _locationGranted,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );
  }

  // ---------------------------------------------------------------------
  // TOP OVERLAYS
  // ---------------------------------------------------------------------

  Widget _buildBackButton() {
    return Positioned(
      top: 56,
      left: 16,
      child: _CircleIconButton(
        icon: Icons.arrow_back,
        onTap: () {
          if (_panelState == _PanelState.nearbyList) {
            Navigator.of(context).maybePop();
          } else if (_panelState == _PanelState.sharePrompt ||
              _panelState == _PanelState.sharingActive) {
            setState(() {
              _panelState = _selectedJeepney != null
                  ? _PanelState.tripDetail
                  : _PanelState.nearbyList;
            });
          } else {
            _backToList();
          }
        },
      ),
    );
  }

  Widget _buildFloatingJeepneyBadge() {
    return const Positioned(
      top: 130,
      left: 16,
      child: _CircleIconButton(icon: Icons.directions_bus, filled: true),
    );
  }

  Widget _buildTopCard() {
    final bool showingTrip = _selectedJeepney != null;
    return Positioned(
      top: 48,
      left: 76,
      right: 16,
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: showingTrip
              ? _TripHeader(jeepney: _selectedJeepney!)
              : _BrowseHeader(
                  commuterName: widget.commuterName,
                ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // FLOATING SHARE BUTTON (hand icon)
  // ---------------------------------------------------------------------

  Widget _buildFloatingShareFab() {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 16,
      left: 0,
      right: 0,
      child: Center(
        child: GestureDetector(
          onTap: _panelState == _PanelState.sharingActive
              ? null
              : _openSharePrompt,
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: _isSharing
                    ? AppColors.primary
                    : Colors.grey.shade300,
                width: 2,
              ),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 8),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                const Icon(Icons.pan_tool_alt_outlined, size: 26),
                if (_isSharing)
                  const Positioned(
                    right: 8,
                    bottom: 8,
                    child: CircleAvatar(
                      radius: 8,
                      backgroundColor: AppColors.primary,
                      child: Icon(Icons.check, size: 10, color: AppColors.onPrimary),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // BOTTOM PANEL
  // ---------------------------------------------------------------------

  Widget _buildBottomPanel() {
    return DraggableScrollableSheet(
      key: ValueKey(_panelState),
      initialChildSize: _initialSheetSizeFor(_panelState),
      minChildSize: 0.15,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 12)],
          ),
          child: Column(
            children: [
              const _SheetDragHandle(),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    4,
                    20,
                    MediaQuery.of(context).padding.bottom + 20,
                  ),
                  child: _buildPanelContent(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Starting height (as a fraction of screen height) for each panel
  /// state, before the user drags it up or down.
  double _initialSheetSizeFor(_PanelState state) {
    switch (state) {
      case _PanelState.nearbyList:
        return 0.42;
      case _PanelState.tripDetail:
        return 0.36;
      case _PanelState.sharePrompt:
        return 0.4;
      case _PanelState.sharingActive:
        return 0.3;
    }
  }

  Widget _buildPanelContent() {
    switch (_panelState) {
      case _PanelState.nearbyList:
        return _NearbyJeepneysPanel(
          jeepneys: _nearbyJeepneys,
          onSelect: _selectJeepney,
        );
      case _PanelState.tripDetail:
        return _TripDetailPanel(progress: _mockTripProgress);
      case _PanelState.sharePrompt:
        return _SharePromptPanel(
          passengerCount: _passengerCount,
          onIncrement: _incrementPassengers,
          onDecrement: _decrementPassengers,
          onShare: _confirmShare,
        );
      case _PanelState.sharingActive:
        return _SharingActivePanel(onCancel: _cancelShare);
    }
  }
}

/// -----------------------------------------------------------------------
/// SHARED WIDGETS
/// -----------------------------------------------------------------------

class _SheetDragHandle extends StatelessWidget {
  const _SheetDragHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({
    required this.icon,
    this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: filled ? AppColors.primary : Colors.white,
      shape: const CircleBorder(),
      elevation: 4,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Icon(
            icon,
            size: 22,
            color: filled ? AppColors.onPrimary : Colors.black87,
          ),
        ),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// TOP CARD CONTENT
/// -----------------------------------------------------------------------

class _BrowseHeader extends StatelessWidget {
  const _BrowseHeader({required this.commuterName});

  final String commuterName;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Find Nearby Jeepneys',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        Text(
          commuterName,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}

class _TripHeader extends StatelessWidget {
  const _TripHeader({required this.jeepney});

  final JeepneyModel jeepney;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Jeepney ${jeepney.id}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                jeepney.route,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              Text(
                'Driver: ${jeepney.driverName}',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              Text(
                'Seating Capacity: ${jeepney.seatingCapacity} Seats',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        if (jeepney.onTrip) const _StatusDot(label: 'On Trip'),
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF2E9E4F),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2E9E4F),
          ),
        ),
      ],
    );
  }
}

/// -----------------------------------------------------------------------
/// PANEL 1 — NEARBY JEEPNEYS LIST
/// -----------------------------------------------------------------------

class _NearbyJeepneysPanel extends StatelessWidget {
  const _NearbyJeepneysPanel({
    required this.jeepneys,
    required this.onSelect,
  });

  final List<JeepneyModel> jeepneys;
  final ValueChanged<JeepneyModel> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Nearby Jeepneys',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF2E9E4F),
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  'Updated just now',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...jeepneys.map(
          (jeepney) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _JeepneyListTile(
              jeepney: jeepney,
              onTap: () => onSelect(jeepney),
            ),
          ),
        ),
      ],
    );
  }
}

class _JeepneyListTile extends StatelessWidget {
  const _JeepneyListTile({required this.jeepney, required this.onTap});

  final JeepneyModel jeepney;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.logoBlue,
              child: const Icon(
                Icons.directions_bus,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Jeepney ${jeepney.id}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    jeepney.route,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    '${jeepney.distanceKm} km away',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  Text(
                    'Seating Capacity: ${jeepney.seatingCapacity}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${jeepney.etaMinutes} mins',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: jeepney.etaColor,
                  ),
                ),
                Text(
                  'Away',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// PANEL 2 — TRIP DETAIL / ESTIMATED ARRIVAL
/// -----------------------------------------------------------------------

class _TripDetailPanel extends StatelessWidget {
  const _TripDetailPanel({required this.progress});

  final TripProgressModel progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Estimated Arrival',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            const Text(
              '5',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                color: Color(0xFF2E9E4F),
              ),
            ),
            const SizedBox(width: 4),
            const Text(
              'mins',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2E9E4F),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '(0.2 km away)',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
            ),
          ],
        ),
        Text(
          'Updated just now',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const Divider(height: 28),
        const Text(
          'Trip Progress',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Text(
              progress.originLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: _ProgressTrack(progress: progress.progress),
              ),
            ),
            Text(
              progress.destinationLabel,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _LabelValue(
              label: 'Distance Traveled',
              value: '${progress.distanceTraveledKm} km away',
            ),
            _LabelValue(
              label: 'Estimated Total Time',
              value: '${progress.estimatedTotalMinutes} mins',
              alignEnd: true,
            ),
          ],
        ),
      ],
    );
  }
}

class _ProgressTrack extends StatelessWidget {
  const _ProgressTrack({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final double dotX = constraints.maxWidth * progress;
          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                width: dotX,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Positioned(
                left: (dotX - 10).clamp(0, constraints.maxWidth - 20),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_bus,
                    color: AppColors.onPrimary,
                    size: 12,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  const _LabelValue({
    required this.label,
    required this.value,
    this.alignEnd = false,
  });

  final String label;
  final String value;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// -----------------------------------------------------------------------
/// PANEL 3 — SHARE LOCATION PROMPT
/// -----------------------------------------------------------------------

class _SharePromptPanel extends StatelessWidget {
  const _SharePromptPanel({
    required this.passengerCount,
    required this.onIncrement,
    required this.onDecrement,
    required this.onShare,
  });

  final int passengerCount;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Share your Location?',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 20),
        const Text(
          'Select Number of Passengers',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        Text(
          'Do you have any companions?',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepperButton(icon: Icons.remove, onTap: onDecrement),
            SizedBox(
              width: 60,
              child: Text(
                '$passengerCount',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            _StepperButton(icon: Icons.add, onTap: onIncrement),
          ],
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onShare,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Share',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.onPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      shape: CircleBorder(side: BorderSide(color: Colors.grey.shade300)),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Icon(icon, size: 18, color: Colors.black87),
        ),
      ),
    );
  }
}

/// -----------------------------------------------------------------------
/// PANEL 4 — SHARING ACTIVE
/// -----------------------------------------------------------------------

class _SharingActivePanel extends StatelessWidget {
  const _SharingActivePanel({required this.onCancel});

  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'The jeepney drivers will see your current location.\nPlease wait.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: OutlinedButton(
            onPressed: onCancel,
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF7A1F2B),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Cancel Share',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }
}