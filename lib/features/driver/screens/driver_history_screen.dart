import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/driver_session.dart';
import '../../../core/utils/manila_date_range.dart';

const List<String> _kMonthAbbrev = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Matches the format the trip-in-progress screen builds locally, so a
/// backend-synced entry displays identically to one recorded on this
/// device the moment a trip ended.
String _formatHistoryDateTime(DateTime utcInstant) {
  final dt = toManilaWallClock(utcInstant);
  final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final period = dt.hour >= 12 ? 'PM' : 'AM';
  final minute = dt.minute.toString().padLeft(2, '0');
  return '${_kMonthAbbrev[dt.month - 1]} ${dt.day}, ${dt.year} · $hour12:$minute $period';
}

String _formatHistoryDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m';
}

/// The two fixed routes this fleet services — see kDriverRoutes in
/// driver_start_trip_screen.dart. Hardcoded here too (rather than derived
/// from whatever's been loaded so far) so the Route filter always offers
/// both options regardless of which page of trips happens to be loaded.
const List<String> kTripHistoryRoutes = ['Pasig – Quiapo', 'Quiapo – Pasig'];

// ===========================================================================
// TRIP HISTORY ITEM
// ===========================================================================

class DriverTripHistoryItem {
  final String tripId;
  final String route;
  final String plateNumber;
  final String dateTime;
  final String duration;

  /// Raw completion timestamp — [dateTime] is a pre-formatted display
  /// string that isn't safely re-parseable, so this is what "today's
  /// trips" counts actually filter against.
  final DateTime completedAt;

  /// Whether the *backend* flagged this trip as unusually short (see
  /// computeShortTripFlag in the backend's driver.ts) — never computed on
  /// this device. [flagReason] is the backend's own explanation of why.
  final bool isShortTrip;
  final String? flagReason;

  /// This driver's own explanation for [isShortTrip], submitted via
  /// PATCH /api/driver/trips/:id/explanation — null until they submit
  /// one.
  final String? driverExplanation;
  final DateTime? explanationSubmittedAt;

  /// Admin review trail — 'PENDING' | 'REVIEWED' | 'VALID' | 'INVALID',
  /// matching the backend's TripReviewStatus enum. Read-only here; only
  /// an admin can change it (see PATCH /api/admin/trips/:id/review).
  final String reviewStatus;
  final DateTime? reviewedAt;
  final String? adminReviewNote;

  const DriverTripHistoryItem({
    required this.tripId,
    required this.route,
    required this.plateNumber,
    required this.dateTime,
    required this.duration,
    required this.completedAt,
    this.isShortTrip = false,
    this.flagReason,
    this.driverExplanation,
    this.explanationSubmittedAt,
    this.reviewStatus = 'PENDING',
    this.reviewedAt,
    this.adminReviewNote,
  });

  /// Builds an item straight from one of GET /api/driver/trips's `trips`
  /// entries (or GET /api/driver/trips/:id's `trip`) — the backend is the
  /// only source of truth for a trip's flag/review state, so nothing here
  /// is ever cached to disk; every read is a fresh call.
  factory DriverTripHistoryItem.fromJson(Map<String, dynamic> map, {required String plateNumber}) {
    final startedAt = DateTime.parse(map['startedAt'] as String);
    final endedAtRaw = map['endedAt'] as String?;
    final completedAt = endedAtRaw != null ? DateTime.parse(endedAtRaw) : startedAt;
    final explanationSubmittedAtRaw = map['explanationSubmittedAt'] as String?;
    final reviewedAtRaw = map['reviewedAt'] as String?;
    return DriverTripHistoryItem(
      tripId: map['id'] as String,
      route: (map['route'] as String?) ?? '—',
      plateNumber: plateNumber,
      dateTime: _formatHistoryDateTime(startedAt),
      duration: _formatHistoryDuration(completedAt.difference(startedAt)),
      completedAt: completedAt,
      isShortTrip: map['isShortTrip'] as bool? ?? false,
      flagReason: map['flagReason'] as String?,
      driverExplanation: map['driverExplanation'] as String?,
      explanationSubmittedAt: explanationSubmittedAtRaw != null ? DateTime.parse(explanationSubmittedAtRaw) : null,
      reviewStatus: map['reviewStatus'] as String? ?? 'PENDING',
      reviewedAt: reviewedAtRaw != null ? DateTime.parse(reviewedAtRaw) : null,
      adminReviewNote: map['adminReviewNote'] as String?,
    );
  }
}

/// Fetches a single trip by id, scoped to the calling driver — used by
/// DriverTripDetailsScreen/DriverTripExplanationScreen's own live-refresh
/// polling and by the notifications screen's "open the trip this
/// notification points at" navigation. Returns null on any failure (trip
/// gone, offline, etc.) — callers already have a trip to fall back to.
Future<DriverTripHistoryItem?> fetchDriverTripById(String tripId) async {
  final token = DriverSession.instance.authToken;
  if (token == null) return null;
  try {
    final response = await ApiClient.get('/api/driver/trips/$tripId', token: token);
    final tripJson = response['trip'] as Map<String, dynamic>?;
    if (tripJson == null) return null;
    return DriverTripHistoryItem.fromJson(tripJson, plateNumber: DriverSession.instance.plateNumber ?? '—');
  } catch (_) {
    return null;
  }
}

// ===========================================================================
// DRIVER HISTORY SCREEN
// ===========================================================================

enum _DatePreset { all, today, week, month, custom }

const int _kPageSize = 20;

class DriverHistoryScreen extends StatefulWidget {
  const DriverHistoryScreen({super.key});

  @override
  State<DriverHistoryScreen> createState() => _DriverHistoryScreenState();
}

class _DriverHistoryScreenState extends State<DriverHistoryScreen> {
  final List<DriverTripHistoryItem> _trips = [];
  int _loadedPages = 0;
  bool _hasNextPage = true;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String? _error;

  _DatePreset _datePreset = _DatePreset.all;
  DateTimeRange? _customRange;
  String? _routeFilter;

  /// Keeps whatever's currently loaded (however many pages that is) live
  /// while this screen stays open — an admin reviewing a flagged trip
  /// should show up here without the driver having to leave and come
  /// back. Re-fetches pages 1.._loadedPages as one replace rather than
  /// resetting to just page 1, so a driver who's tapped "Load More" a few
  /// times doesn't lose that on every tick.
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _loadFirstPage();
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) => _refreshLoadedPages());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Map<String, String> get _filterParams {
    final params = <String, String>{};
    ManilaDateRange? range;
    switch (_datePreset) {
      case _DatePreset.all:
        range = null;
      case _DatePreset.today:
        range = ManilaDateRange.preset('today');
      case _DatePreset.week:
        range = ManilaDateRange.preset('week');
      case _DatePreset.month:
        range = ManilaDateRange.preset('month');
      case _DatePreset.custom:
        range = _customRange != null ? ManilaDateRange.custom(_customRange!.start, _customRange!.end) : null;
    }
    if (range != null) {
      params['dateFrom'] = range.from.toIso8601String();
      params['dateTo'] = range.to.toIso8601String();
    }
    if (_routeFilter != null) params['route'] = _routeFilter!;
    return params;
  }

  Future<Map<String, dynamic>?> _fetchPage(int page) async {
    final token = DriverSession.instance.authToken;
    if (token == null) return null;
    final params = {'page': '$page', 'limit': '$_kPageSize', ..._filterParams};
    final query = params.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&');
    return ApiClient.get('/api/driver/trips?$query', token: token);
  }

  Future<void> _loadFirstPage() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final response = await _fetchPage(1);
      if (!mounted) return;
      final plateNumber = DriverSession.instance.plateNumber ?? '—';
      final raw = response?['trips'] as List<dynamic>? ?? const [];
      setState(() {
        _trips
          ..clear()
          ..addAll(raw.map((j) => DriverTripHistoryItem.fromJson(j as Map<String, dynamic>, plateNumber: plateNumber)));
        _loadedPages = 1;
        _hasNextPage = response?['hasNextPage'] as bool? ?? false;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = "Couldn't load your trip history. Pull down or try again.";
      });
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasNextPage) return;
    setState(() => _isLoadingMore = true);
    try {
      final nextPage = _loadedPages + 1;
      final response = await _fetchPage(nextPage);
      if (!mounted) return;
      final plateNumber = DriverSession.instance.plateNumber ?? '—';
      final raw = response?['trips'] as List<dynamic>? ?? const [];
      setState(() {
        _trips.addAll(raw.map((j) => DriverTripHistoryItem.fromJson(j as Map<String, dynamic>, plateNumber: plateNumber)));
        _loadedPages = nextPage;
        _hasNextPage = response?['hasNextPage'] as bool? ?? false;
        _isLoadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't load more trips. Please try again.")),
      );
    }
  }

  /// Best-effort re-fetch of pages 1.._loadedPages, replacing [_trips] in
  /// one go — the "make it feel live" tick. Silently keeps whatever's
  /// currently shown on failure, same as every other poll in this app.
  Future<void> _refreshLoadedPages() async {
    if (_isLoading || _isLoadingMore || _loadedPages == 0) return;
    try {
      final plateNumber = DriverSession.instance.plateNumber ?? '—';
      final merged = <DriverTripHistoryItem>[];
      bool hasNext = _hasNextPage;
      for (var page = 1; page <= _loadedPages; page++) {
        final response = await _fetchPage(page);
        final raw = response?['trips'] as List<dynamic>? ?? const [];
        merged.addAll(raw.map((j) => DriverTripHistoryItem.fromJson(j as Map<String, dynamic>, plateNumber: plateNumber)));
        if (page == _loadedPages) hasNext = response?['hasNextPage'] as bool? ?? false;
      }
      if (!mounted) return;
      setState(() {
        _trips
          ..clear()
          ..addAll(merged);
        _hasNextPage = hasNext;
      });
    } catch (_) {
      // Keep whatever's currently shown.
    }
  }

  /// Any filter change clears the list and reloads page 1 from scratch —
  /// a stale "Load More" state from a previous filter wouldn't line up
  /// with the new one anyway.
  void _applyFilters() {
    _loadedPages = 0;
    _trips.clear();
    _loadFirstPage();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange,
    );
    if (picked == null) return;
    setState(() {
      _datePreset = _DatePreset.custom;
      _customRange = picked;
    });
    _applyFilters();
  }

  void _selectDatePreset(_DatePreset preset) {
    if (preset == _DatePreset.custom) {
      _pickCustomRange();
      return;
    }
    if (_datePreset == preset) return;
    setState(() => _datePreset = preset);
    _applyFilters();
  }

  void _selectRoute(String? route) {
    if (_routeFilter == route) return;
    setState(() => _routeFilter = route);
    _applyFilters();
  }

  void _openTripDetails(BuildContext context, DriverTripHistoryItem trip) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DriverTripDetailsScreen(trip: trip),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            _FilterBar(
              datePreset: _datePreset,
              customRange: _customRange,
              routeFilter: _routeFilter,
              onSelectDatePreset: _selectDatePreset,
              onSelectRoute: _selectRoute,
            ),
            Expanded(child: _buildBody(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _loadFirstPage);
    }
    if (_trips.isEmpty) {
      return const _EmptyHistoryState();
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        const Text(
          'Your Trips',
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 4),
        const Text(
          'Tap a trip to view its details.',
          style: TextStyle(
            fontSize: 10,
            color: Colors.black45,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        ..._trips.map(
          (trip) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _TripHistoryCard(
              trip: trip,
              onTap: () => _openTripDetails(context, trip),
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (_hasNextPage)
          Center(
            child: OutlinedButton(
              onPressed: _isLoadingMore ? null : _loadMore,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.logoBlue,
                side: const BorderSide(color: AppColors.logoBlue),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                _isLoadingMore ? 'Loading...' : 'Load More',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
          )
        else
          const Center(
            child: Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                "You've reached the end.",
                style: TextStyle(fontSize: 11, color: Colors.black38, fontWeight: FontWeight.w500),
              ),
            ),
          ),
      ],
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
                  'Trip History',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onPrimary,
                  ),
                ),
                const SizedBox(height: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// FILTER BAR
// ===========================================================================
// Two compact dropdowns side by side instead of two rows of scrolling
// chips — same filters (date preset + route), far less vertical space and
// nothing to horizontally scroll past to see if more options exist.

/// Shared pill-shaped shell every filter dropdown sits in — kept as one
/// function rather than duplicating this BoxDecoration/height at each
/// call site.
Widget _filterDropdownShell({required Widget child}) {
  return Container(
    height: 40,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE1E4E8)),
    ),
    alignment: Alignment.centerLeft,
    child: child,
  );
}

const TextStyle _kFilterDropdownTextStyle = TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w700,
  color: Colors.black87,
);

class _FilterBar extends StatelessWidget {
  final _DatePreset datePreset;
  final DateTimeRange? customRange;
  final String? routeFilter;
  final ValueChanged<_DatePreset> onSelectDatePreset;
  final ValueChanged<String?> onSelectRoute;

  const _FilterBar({
    required this.datePreset,
    required this.customRange,
    required this.routeFilter,
    required this.onSelectDatePreset,
    required this.onSelectRoute,
  });

  String get _customLabel {
    if (customRange == null) return 'Custom Range';
    final r = customRange!;
    return '${r.start.month}/${r.start.day} – ${r.end.month}/${r.end.day}';
  }

  String _dateLabel(_DatePreset preset) {
    switch (preset) {
      case _DatePreset.all:
        return 'All Dates';
      case _DatePreset.today:
        return 'Today';
      case _DatePreset.week:
        return 'This Week';
      case _DatePreset.month:
        return 'This Month';
      case _DatePreset.custom:
        return _customLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          Expanded(
            child: _filterDropdownShell(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<_DatePreset>(
                  value: datePreset,
                  isExpanded: true,
                  isDense: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.black45),
                  style: _kFilterDropdownTextStyle,
                  items: _DatePreset.values
                      .map((preset) => DropdownMenuItem(
                            value: preset,
                            child: Text(_dateLabel(preset), overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (preset) {
                    if (preset != null) onSelectDatePreset(preset);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _filterDropdownShell(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: routeFilter,
                  isExpanded: true,
                  isDense: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: Colors.black45),
                  style: _kFilterDropdownTextStyle,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All Routes', overflow: TextOverflow.ellipsis)),
                    for (final route in kTripHistoryRoutes)
                      DropdownMenuItem<String?>(value: route, child: Text(route, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: onSelectRoute,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistoryState extends StatelessWidget {
  const _EmptyHistoryState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.history_rounded, size: 56, color: Colors.black26),
          const SizedBox(height: 12),
          const Text(
            'No trips found',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.black45),
          ),
          const SizedBox(height: 4),
          const Text(
            'Trips you complete will show up here.',
            style: TextStyle(fontSize: 12, color: Colors.black38, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 48, color: Colors.black26),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black45, fontWeight: FontWeight.w500),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.logoBlue,
              side: const BorderSide(color: AppColors.logoBlue),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// HISTORY CARD
// ===========================================================================

class _TripHistoryCard extends StatelessWidget {
  final DriverTripHistoryItem trip;
  final VoidCallback onTap;

  const _TripHistoryCard({required this.trip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE1E4E8)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: const BoxDecoration(
                  color: AppColors.logoBlue,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: const Icon(Icons.directions_bus_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.route,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      trip.plateNumber,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      trip.dateTime,
                      style: const TextStyle(fontSize: 10, color: Colors.black38),
                    ),
                    if (trip.isShortTrip) ...[
                      const SizedBox(height: 4),
                      const _ShortTripFlaggedBadge(),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    trip.duration,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppColors.logoBlue,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Icon(Icons.chevron_right_rounded, color: Colors.black38, size: 22),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tag shown on trips the backend flagged as unusually short — see
/// [DriverTripHistoryItem.isShortTrip]. Never shown based on a
/// client-side guess.
class _ShortTripFlaggedBadge extends StatelessWidget {
  const _ShortTripFlaggedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFFFE08A)),
      ),
      child: const Text(
        'Short Trip – Flagged',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: Color(0xFF8A6D00),
        ),
      ),
    );
  }
}

/// Small status pill for a flagged trip's review outcome — shown once an
/// admin has acted (see [DriverTripHistoryItem.reviewStatus]).
class _ReviewStatusBadge extends StatelessWidget {
  final String reviewStatus;

  const _ReviewStatusBadge({required this.reviewStatus});

  @override
  Widget build(BuildContext context) {
    final (label, bg, border, fg) = switch (reviewStatus) {
      'VALID' => ('Reviewed – Valid', const Color(0xFFE3F6E8), const Color(0xFFA9E0B8), const Color(0xFF1E7A3B)),
      'INVALID' => ('Reviewed – Invalid', const Color(0xFFFCE4E4), const Color(0xFFF3AFAF), const Color(0xFFA61B1B)),
      'REVIEWED' => ('Reviewed', const Color(0xFFE6EEFB), const Color(0xFFB7CDF3), const Color(0xFF1F4E9C)),
      _ => ('Pending Review', const Color(0xFFF1F1F1), const Color(0xFFDADADA), const Color(0xFF666666)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}

// ===========================================================================
// TRIP DETAILS SCREEN
// ===========================================================================

class DriverTripDetailsScreen extends StatefulWidget {
  final DriverTripHistoryItem trip;

  const DriverTripDetailsScreen({super.key, required this.trip});

  @override
  State<DriverTripDetailsScreen> createState() => _DriverTripDetailsScreenState();
}

class _DriverTripDetailsScreenState extends State<DriverTripDetailsScreen> {
  late DriverTripHistoryItem _trip;

  /// Keeps this trip's flag/review state current while the driver is
  /// sitting on this screen — an admin can review it at any moment, and
  /// the driver shouldn't have to leave and come back to see that. Reads
  /// just this one trip (see fetchDriverTripById), not the whole history.
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final refreshed = await fetchDriverTripById(_trip.tripId);
      if (!mounted || refreshed == null) return;
      setState(() => _trip = refreshed);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _openExplanation() async {
    final updated = await Navigator.push<DriverTripHistoryItem>(
      context,
      MaterialPageRoute(builder: (_) => DriverTripExplanationScreen(trip: _trip)),
    );
    if (updated != null && mounted) {
      setState(() => _trip = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    final trip = _trip;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildHeader(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'TRIP SUMMARY',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 1.0,
                                  color: AppColors.logoBlue,
                                ),
                              ),
                              if (trip.isShortTrip) const _ShortTripFlaggedBadge(),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              trip.dateTime,
                              style: const TextStyle(
                                fontSize: 10,
                                color: Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          _ReceiptRow(label: 'Trip ID', value: trip.tripId),
                          const SizedBox(height: 10),
                          _ReceiptRow(label: 'Route', value: trip.route),
                          const SizedBox(height: 10),
                          _ReceiptRow(label: 'Vehicle', value: trip.plateNumber),
                        ],
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: const BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.only(
                          bottomLeft: Radius.circular(13),
                          bottomRight: Radius.circular(13),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Duration',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.onPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            trip.duration,
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (trip.isShortTrip)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: _ShortTripFlagCard(trip: trip, onExplain: _openExplanation),
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
                  'Trip Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _trip.tripId,
                  style: TextStyle(fontSize: 10, color: Colors.black.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The flagged-trip section on Trip Details — flag reason, this driver's
/// own explanation (if any) and its submitted date, the admin review
/// outcome (if any), and the Explain/Update Explanation action.
class _ShortTripFlagCard extends StatelessWidget {
  final DriverTripHistoryItem trip;
  final VoidCallback onExplain;

  const _ShortTripFlagCard({required this.trip, required this.onExplain});

  @override
  Widget build(BuildContext context) {
    final hasExplanation = trip.driverExplanation != null && trip.driverExplanation!.isNotEmpty;
    // Once an admin has made a call on this trip, the explanation that
    // call was based on shouldn't keep changing underneath it — locked
    // the moment reviewStatus leaves PENDING (VALID/INVALID, in practice,
    // since REVIEWED isn't exposed as an admin action anymore). The
    // driver can still see everything on this card, just can't reopen
    // the form.
    final isLocked = trip.reviewStatus != 'PENDING';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFFE08A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFF8A6D00)),
              const SizedBox(width: 6),
              const Text(
                'Short Trip – Flagged',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Color(0xFF8A6D00)),
              ),
            ],
          ),
          if (trip.flagReason != null) ...[
            const SizedBox(height: 6),
            Text(
              trip.flagReason!,
              style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500),
            ),
          ],
          const SizedBox(height: 12),
          if (hasExplanation) ...[
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 15, color: Color(0xFF1E7A3B)),
                const SizedBox(width: 5),
                const Text(
                  'Explanation Submitted',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1E7A3B)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFE1E4E8)),
              ),
              child: Text(
                trip.driverExplanation!,
                style: const TextStyle(fontSize: 12, color: Colors.black87, fontWeight: FontWeight.w500),
              ),
            ),
            if (trip.explanationSubmittedAt != null) ...[
              const SizedBox(height: 4),
              Text(
                'Submitted ${_formatHistoryDateTime(trip.explanationSubmittedAt!)}',
                style: const TextStyle(fontSize: 10, color: Colors.black38),
              ),
            ],
            const SizedBox(height: 10),
          ],
          if (isLocked) ...[
            Row(
              children: [
                const Text(
                  'Review status: ',
                  style: TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
                ),
                _ReviewStatusBadge(reviewStatus: trip.reviewStatus),
              ],
            ),
            if (trip.adminReviewNote != null && trip.adminReviewNote!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                'Admin note: ${trip.adminReviewNote!}',
                style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500),
              ),
            ],
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: isLocked ? null : onExplain,
              style: OutlinedButton.styleFrom(
                foregroundColor: isLocked ? Colors.black38 : const Color(0xFF8A6D00),
                side: BorderSide(color: isLocked ? const Color(0xFFE1E4E8) : const Color(0xFFE0A800)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                isLocked ? 'Reviewed' : (hasExplanation ? 'Update Explanation' : 'Explain'),
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReceiptRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w500),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// TRIP EXPLANATION SCREEN
// ===========================================================================

/// The form a driver uses to explain (or update their explanation for) a
/// flagged trip — PATCH /api/driver/trips/:id/explanation is the only
/// thing this screen ever calls; it can't touch isShortTrip, duration,
/// status, or review fields. Pops the updated trip if an explanation was
/// successfully submitted/updated, so the caller (DriverTripDetailsScreen)
/// can apply it directly without a second round trip.
/// Quick-tap reasons covering the causes of a short trip a jeepney driver
/// in the Philippines is actually likely to hit — faster than typing mid-
/// shift, and gives admins reviewing Trip History a consistent, scannable
/// set of explanations instead of freeform prose every time. "Others"
/// (handled separately, not in this list) reveals a free-text field for
/// anything that doesn't fit.
const List<String> _kShortTripPresetReasons = [
  'Accidentally tapped Start Trip',
  'No passengers boarded — returned to terminal',
  'Vehicle breakdown or mechanical problem',
  'Flat tire',
  'Flagged down by a traffic enforcer or checkpoint',
  'Road blocked or rerouted (traffic, flooding, construction)',
  'Ran out of fuel',
];

const String _kOthersReasonOption = 'Others';

/// One tappable row in the reason picker — a radio-style selectable
/// option, styled like this app's other selectable-pill affordances
/// (see _ShortTripFlagCard's Explain button) rather than a bare
/// Material Radio, to match the rest of this screen's look.
class _ReasonOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  const _ReasonOption({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.secondary.withValues(alpha: 0.08) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? AppColors.secondary : const Color(0xFFE1E4E8)),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                size: 18,
                color: selected ? AppColors.secondary : Colors.black26,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.secondary : Colors.black87,
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

class DriverTripExplanationScreen extends StatefulWidget {
  final DriverTripHistoryItem trip;

  const DriverTripExplanationScreen({super.key, required this.trip});

  @override
  State<DriverTripExplanationScreen> createState() => _DriverTripExplanationScreenState();
}

class _DriverTripExplanationScreenState extends State<DriverTripExplanationScreen> {
  late DriverTripHistoryItem _trip;
  late final TextEditingController _controller;

  /// One of [_kShortTripPresetReasons], [_kOthersReasonOption], or null
  /// (nothing chosen yet). Null blocks submit — see [_handleSubmit].
  String? _selectedReason;
  bool _isSubmitting = false;

  /// Whatever the trip looked like when this screen last actually changed
  /// it (a successful submit) — popped on back if non-null, so the caller
  /// only re-renders when something really changed.
  DriverTripHistoryItem? _updatedTrip;

  /// Re-checked every poll tick — an admin can review this exact trip
  /// while the driver still has this form open, and submitting after
  /// that point should stop being possible right away, not just the next
  /// time this screen happens to be opened (the backend already rejects
  /// it either way — see PATCH /trips/:id/explanation — this just keeps
  /// the UI honest about it in real time too).
  bool get _isLocked => _trip.reviewStatus != 'PENDING';

  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _trip = widget.trip;
    final existing = _trip.driverExplanation;
    if (existing != null && existing.isNotEmpty) {
      _selectedReason = _kShortTripPresetReasons.contains(existing) ? existing : _kOthersReasonOption;
    }
    _controller = TextEditingController(
      text: _selectedReason == _kOthersReasonOption ? existing ?? '' : '',
    );
    // Only refreshes reviewStatus/adminReviewNote/reviewedAt (via _trip)
    // — deliberately never touches _selectedReason/_controller, so it
    // can't clobber whatever the driver's mid-typing.
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) async {
      final refreshed = await fetchDriverTripById(_trip.tripId);
      if (!mounted || refreshed == null) return;
      setState(() => _trip = refreshed);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _selectReason(String reason) {
    setState(() => _selectedReason = reason);
  }

  Future<void> _handleSubmit() async {
    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a reason.')),
      );
      return;
    }

    final isOthers = _selectedReason == _kOthersReasonOption;
    final text = isOthers ? _controller.text.trim() : _selectedReason!;
    if (isOthers && text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter an explanation before submitting.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final response = await ApiClient.patch(
        '/api/driver/trips/${_trip.tripId}/explanation',
        {'explanation': text},
        token: DriverSession.instance.authToken,
      );
      final tripJson = response['trip'] as Map<String, dynamic>;
      final updated = DriverTripHistoryItem.fromJson(tripJson, plateNumber: _trip.plateNumber);
      if (!mounted) return;
      setState(() {
        _trip = updated;
        _updatedTrip = updated;
        _isSubmitting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Explanation Submitted')),
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't submit your explanation. Please try again.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasExplanation = _trip.driverExplanation != null && _trip.driverExplanation!.isNotEmpty;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    if (hasExplanation)
                      Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F6E8),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFA9E0B8)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF1E7A3B)),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Explanation Submitted',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF1E7A3B)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (_trip.flagReason != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Text(
                          _trip.flagReason!,
                          style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500),
                        ),
                      ),
                    const Text(
                      'Your Explanation',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Choose a reason for this trip.',
                      style: TextStyle(fontSize: 10, color: Colors.black45, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 10),
                    ..._kShortTripPresetReasons.map(
                      (reason) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ReasonOption(
                          label: reason,
                          selected: _selectedReason == reason,
                          onTap: _isSubmitting ? null : () => _selectReason(reason),
                        ),
                      ),
                    ),
                    _ReasonOption(
                      label: _kOthersReasonOption,
                      selected: _selectedReason == _kOthersReasonOption,
                      onTap: _isSubmitting ? null : () => _selectReason(_kOthersReasonOption),
                    ),
                    if (_selectedReason == _kOthersReasonOption) ...[
                      const SizedBox(height: 10),
                      TextField(
                        controller: _controller,
                        maxLines: 6,
                        maxLength: 1000,
                        enabled: !_isSubmitting,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Tell us what happened with this trip...',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE1E4E8)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFE1E4E8)),
                          ),
                        ),
                      ),
                    ],
                    if (_trip.explanationSubmittedAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Last submitted ${_formatHistoryDateTime(_trip.explanationSubmittedAt!)}',
                          style: const TextStyle(fontSize: 10, color: Colors.black38),
                        ),
                      ),
                    const SizedBox(height: 18),
                    if (_isLocked)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F1F1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'An admin has already reviewed this trip, so it can no longer be explained or updated.',
                          style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isSubmitting ? null : _handleSubmit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: AppColors.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            _isSubmitting
                                ? 'Submitting...'
                                : (hasExplanation ? 'Update Explanation' : 'Submit Explanation'),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    if (_trip.reviewStatus != 'PENDING') ...[
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          const Text(
                            'Review status: ',
                            style: TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w600),
                          ),
                          _ReviewStatusBadge(reviewStatus: _trip.reviewStatus),
                        ],
                      ),
                      if (_trip.adminReviewNote != null && _trip.adminReviewNote!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Admin note: ${_trip.adminReviewNote!}',
                          style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ],
                  ],
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
              onTap: () => Navigator.of(context).maybePop(_updatedTrip),
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
                  'Explain Trip',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _trip.tripId,
                  style: TextStyle(fontSize: 10, color: Colors.black.withValues(alpha: 0.55)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
