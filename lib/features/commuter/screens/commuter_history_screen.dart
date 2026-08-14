import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/user_session.dart';
import '../../../core/utils/fare_calculator.dart';
import 'notifications_screen.dart';

// ===========================================================================
// HISTORY ITEM
// ===========================================================================

class TripHistoryItem {
  final String tripId;
  final String driverName;
  final String plateNumber;
  final String route;
  final String boardingPoint;
  final int regularRiders;
  final int studentRiders;
  final int seniorRiders;
  final String dateTime;
  final String fare;

  /// Raw boarding timestamp — [dateTime] is a pre-formatted display string
  /// that isn't safely re-parseable, so this is what merge/sort against
  /// [syncFromBackend] actually uses.
  final DateTime boardedAt;

  /// The driver's average rating and how many ratings it's based on — from
  /// the backend's real Rating table (see [CommuterHistoryScreen.syncFromBackend]),
  /// null/0 until a sync has actually happened. Fare/rider counts stay
  /// purely local (self-reported, no payment system to verify against),
  /// but a rating is real, durable data once submitted, so this isn't.
  final double? driverAverageRating;
  final int driverRatingCount;

  const TripHistoryItem({
    required this.tripId,
    required this.driverName,
    required this.plateNumber,
    required this.route,
    required this.boardingPoint,
    required this.regularRiders,
    required this.studentRiders,
    required this.seniorRiders,
    required this.dateTime,
    required this.fare,
    required this.boardedAt,
    this.driverAverageRating,
    this.driverRatingCount = 0,
  });

  FareBreakdown get fareBreakdown => FareBreakdown(
        regularRiders: regularRiders,
        studentRiders: studentRiders,
        seniorRiders: seniorRiders,
      );

  String get ridersLabel => fareBreakdown.ridersLabel;

  Map<String, dynamic> _toJson() => {
        'tripId': tripId,
        'driverName': driverName,
        'plateNumber': plateNumber,
        'route': route,
        'boardingPoint': boardingPoint,
        'regularRiders': regularRiders,
        'studentRiders': studentRiders,
        'seniorRiders': seniorRiders,
        'dateTime': dateTime,
        'fare': fare,
        'boardedAt': boardedAt.toIso8601String(),
        'driverAverageRating': driverAverageRating,
        'driverRatingCount': driverRatingCount,
      };

  static TripHistoryItem _fromJson(Map<String, dynamic> json) => TripHistoryItem(
        tripId: json['tripId'] as String,
        driverName: json['driverName'] as String,
        plateNumber: json['plateNumber'] as String,
        route: json['route'] as String,
        boardingPoint: json['boardingPoint'] as String,
        regularRiders: json['regularRiders'] as int,
        studentRiders: json['studentRiders'] as int,
        seniorRiders: json['seniorRiders'] as int,
        dateTime: json['dateTime'] as String,
        fare: json['fare'] as String,
        // Older persisted entries (from before this field existed) won't
        // have it — fall back to "now" rather than crash on load.
        boardedAt: json['boardedAt'] != null ? DateTime.parse(json['boardedAt'] as String) : DateTime.now(),
        driverAverageRating: (json['driverAverageRating'] as num?)?.toDouble(),
        driverRatingCount: json['driverRatingCount'] as int? ?? 0,
      );
}

// ===========================================================================
// COMMUTER HISTORY SCREEN
// ===========================================================================

class CommuterHistoryScreen extends StatefulWidget {
  const CommuterHistoryScreen({
    super.key,
  });

  static const _kHistoryPrefsKey = 'commuter_trip_history_v1';
  static const _kRatedPrefsKey = 'commuter_rated_trip_ids_v1';
  static const _kReportedPrefsKey = 'commuter_reported_trip_ids_v1';

  // Keyed by tripId so a locally-recorded booking (added the instant a
  // ride ends) and the same trip coming back from [syncFromBackend] merge
  // into one row instead of duplicating — the local flow uses the real
  // backend Trip id now (see JeepneyBookingFlowScreen's _boardedTripId),
  // so the two always agree on a key once connectivity allows /board to
  // succeed at all. Persisted to disk — logging out must never erase a
  // commuter's trip history.
  static final Map<String, TripHistoryItem> _byTripId = {};
  static bool _loaded = false;

  /// All trips, most recently boarded first — what the UI reads.
  static List<TripHistoryItem> get _history {
    final list = _byTripId.values.toList();
    list.sort((a, b) => b.boardedAt.compareTo(a.boardedAt));
    return list;
  }

  /// Loads whatever was previously persisted, once. Safe to call
  /// repeatedly — a no-op after the first successful load.
  static Future<void> loadFromPrefs() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    try {
      final rawHistory = prefs.getStringList(_kHistoryPrefsKey);
      if (rawHistory != null) {
        _byTripId.clear();
        for (final s in rawHistory) {
          final item = TripHistoryItem._fromJson(jsonDecode(s) as Map<String, dynamic>);
          _byTripId[item.tripId] = item;
        }
      }
      _ratedTripIds
        ..clear()
        ..addAll(prefs.getStringList(_kRatedPrefsKey) ?? const []);
      _reportedTripIds
        ..clear()
        ..addAll(prefs.getStringList(_kReportedPrefsKey) ?? const []);
    } catch (_) {
      // Corrupt/old-format data on disk — start clean rather than crash.
    }
    _loaded = true;
  }

  static Future<void> _persistHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kHistoryPrefsKey, _history.map((t) => jsonEncode(t._toJson())).toList());
  }

  static Future<void> _persistRatedAndReported() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kRatedPrefsKey, _ratedTripIds.toList());
    await prefs.setStringList(_kReportedPrefsKey, _reportedTripIds.toList());
  }

  /// Records a just-completed booking (or overwrites the same tripId, e.g.
  /// once [syncFromBackend] confirms it).
  static Future<void> addTrip(TripHistoryItem trip) async {
    _byTripId[trip.tripId] = trip;
    await _persistHistory();
  }

  /// Pulls the commuter's real boardings from the backend and merges them
  /// in — trip identity (driver, plate, route, timestamps, driver rating)
  /// is authoritative from there; fare/rider counts on a matching local
  /// entry are left untouched (self-reported, no backend equivalent — see
  /// TripHistoryItem's doc comment). Also unions in which trips the
  /// backend already knows this commuter rated/reported, so those stay
  /// blocked across devices/reinstalls. Best-effort; a failed sync just
  /// leaves the local cache as it was. Call after login/app-start, not on
  /// every read.
  static Future<void> syncFromBackend() async {
    final token = UserSession.instance.authToken;
    if (token == null) return;
    const days = 366;
    const pageSize = 100;
    try {
      final seenIds = <String>{};

      // Walks every page within the window, not just the first — GET
      // /api/commuter/trips is paginated now (see tripHistoryQuerySchema
      // in commuter.ts), and stopping after one page used to silently cap
      // this at 100 rides. That was worse than just "incomplete history":
      // the reconcile-deletion pass below would then wrongly evict any
      // older-than-100th ride still inside the window, since it looked
      // exactly like a ride that no longer exists on the backend.
      var page = 1;
      while (true) {
        final response = await ApiClient.get('/api/commuter/trips?days=$days&page=$page&pageSize=$pageSize', token: token);
        final raw = response['trips'] as List<dynamic>? ?? const [];
        for (final j in raw) {
          final map = j as Map<String, dynamic>;
          final tripId = map['tripId'] as String;
          final boardedAt = DateTime.parse(map['boardedAt'] as String);
          final existing = _byTripId[tripId];
          seenIds.add(tripId);

          _byTripId[tripId] = TripHistoryItem(
            tripId: tripId,
            driverName: map['driverName'] as String,
            plateNumber: map['plateNumber'] as String,
            route: (map['route'] as String?) ?? existing?.route ?? '—',
            boardingPoint: existing?.boardingPoint ?? '—',
            regularRiders: existing?.regularRiders ?? 1,
            studentRiders: existing?.studentRiders ?? 0,
            seniorRiders: existing?.seniorRiders ?? 0,
            dateTime: existing?.dateTime ?? _formatBoardedAt(boardedAt),
            fare: existing?.fare ?? '—',
            boardedAt: boardedAt,
            driverAverageRating: (map['driverAverageRating'] as num?)?.toDouble(),
            driverRatingCount: map['driverRatingCount'] as int? ?? 0,
          );

          if (map['alreadyRated'] == true) _ratedTripIds.add(tripId);
          if (map['alreadyReported'] == true) _reportedTripIds.add(tripId);
        }

        final hasNextPage = response['hasNextPage'] as bool? ?? false;
        if (!hasNextPage) break;
        page += 1;
      }

      // Reconcile deletions the same way DriverHistoryScreen does — a
      // locally-cached trip inside the window just queried but missing
      // from the response no longer exists on the backend. Entries older
      // than the window are left alone; their current state is unknown.
      final windowStart = DateTime.now().subtract(const Duration(days: days));
      _byTripId.removeWhere(
        (id, item) => !seenIds.contains(id) && item.boardedAt.isAfter(windowStart),
      );

      await _persistHistory();
      await _persistRatedAndReported();
    } catch (_) {
      // Keep whatever's cached locally.
    }
  }

  static String _formatBoardedAt(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year} · $hour12:$minute $period';
  }

  // Tracks trips a commuter has already rated / reported, keyed by tripId,
  // so the Trip Details screen can block a second submission for the same
  // trip even across screen re-entries within the session — now also kept
  // in sync with the backend's real Rating/Complaint records (see
  // [syncFromBackend]).
  static final Set<String> _ratedTripIds = <String>{};
  static final Set<String> _reportedTripIds = <String>{};

  @override
  State<CommuterHistoryScreen> createState() => _CommuterHistoryScreenState();
}

class _CommuterHistoryScreenState extends State<CommuterHistoryScreen> {
  @override
  void initState() {
    super.initState();
    // Re-syncs every time this screen is opened, not just once at
    // login/app-start — otherwise a trip deleted server-side after login
    // would never disappear from this screen until the commuter logged
    // out and back in (see CommuterHistoryScreen.syncFromBackend's doc
    // comment).
    CommuterHistoryScreen.syncFromBackend().then((_) {
      if (mounted) setState(() {});
    });
  }

  void _openTripDetails(
    BuildContext context,
    TripHistoryItem trip,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommuterTripDetailsScreen(
          trip: trip,
        ),
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
            Expanded(
              child: CommuterHistoryScreen._history.isEmpty
                  ? const _EmptyHistoryState()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        14,
                        16,
                        24,
                      ),
                      children: [
                        const Text(
                          'Your Trips',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
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

                        ...CommuterHistoryScreen._history.map(
                          (trip) => Padding(
                            padding: const EdgeInsets.only(
                              bottom: 12,
                            ),
                            child: _TripHistoryCard(
                              trip: trip,
                              onTap: () {
                                _openTripDetails(
                                  context,
                                  trip,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // HEADER
  // ===============================================================
  // Same yellow banner + back button + title/subtitle convention used
  // across the other commuter screens (Settings, Change Password,
  // Emergency Hotlines). Fixed (not scrolling) since the body below it
  // swaps between a list and a centered empty state.

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
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_back, size: 18, color: Colors.black87),
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
                  'History',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onPrimary,
                  ),
                ),
              ],
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
          const Icon(
            Icons.history_rounded,
            size: 56,
            color: Colors.black26,
          ),
          const SizedBox(height: 12),
          const Text(
            'No trips yet',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.black45,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Trips you book will show up here.',
            style: TextStyle(
              fontSize: 12,
              color: Colors.black38,
              fontWeight: FontWeight.w500,
            ),
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
  final TripHistoryItem trip;
  final VoidCallback onTap;

  const _TripHistoryCard({
    required this.trip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final initial = trip.driverName.trim().isEmpty
        ? 'D'
        : trip.driverName.trim()[0].toUpperCase();

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
            border: Border.all(
              color: const Color(0xFFE1E4E8),
            ),
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

                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.route,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      '${trip.driverName} · ${trip.plateNumber}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 3),

                    Text(
                      trip.dateTime,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Column(
                crossAxisAlignment:
                    CrossAxisAlignment.end,
                children: [
                  Text(
                    trip.fare,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: AppColors.logoBlue,
                    ),
                  ),

                  const SizedBox(height: 5),

                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.black38,
                    size: 22,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// TRIP DETAILS SCREEN
// ===========================================================================

class CommuterTripDetailsScreen extends StatefulWidget {
  final TripHistoryItem trip;

  const CommuterTripDetailsScreen({
    super.key,
    required this.trip,
  });

  @override
  State<CommuterTripDetailsScreen> createState() =>
      _CommuterTripDetailsScreenState();
}

class _CommuterTripDetailsScreenState
    extends State<CommuterTripDetailsScreen> {
  int _rating = 0;

  final TextEditingController _commentController =
      TextEditingController();

  bool get _alreadyRated =>
      CommuterHistoryScreen._ratedTripIds.contains(widget.trip.tripId);

  bool get _alreadyReported =>
      CommuterHistoryScreen._reportedTripIds.contains(widget.trip.tripId);

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  bool _isSubmittingRating = false;

  Future<void> _submitRating() async {
    if (_alreadyRated || _isSubmittingRating) return;

    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a rating first.',
          ),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmittingRating = true);

    try {
      await ApiClient.post(
        '/api/commuter/trips/${widget.trip.tripId}/rating',
        {
          'stars': _rating,
          if (_commentController.text.trim().isNotEmpty) 'comment': _commentController.text.trim(),
        },
        token: UserSession.instance.authToken,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmittingRating = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSubmittingRating = false;
      CommuterHistoryScreen._ratedTripIds.add(widget.trip.tripId);
    });
    CommuterHistoryScreen._persistRatedAndReported();

    NotificationsScreen.push(
      AppNotification(
        icon: Icons.star_rounded,
        iconBackground: AppColors.splashBackground,
        title: 'Thank You For Rating!',
        message: 'Thank you! Your rating helps improve our service.',
        time: DateTime.now(),
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: AppColors.logoBlue,
        content: Text(
          'Rating submitted successfully!',
          style: TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Future<void> _reportDriver() async {
    if (_alreadyReported) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ReportDriverScreen(
          trip: widget.trip,
        ),
      ),
    );

    // The report screen marks the trip reported on successful submit —
    // refresh so the button/label reflect that when we come back.
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;

    final initial = trip.driverName.trim().isEmpty
        ? 'D'
        : trip.driverName.trim()[0].toUpperCase();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),

      appBar: AppBar(
        backgroundColor: AppColors.primary,
        elevation: 0,
        foregroundColor: AppColors.onPrimary,

        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            size: 18,
          ),
          onPressed: () {
            Navigator.pop(context);
          },
        ),

        title: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'Trip Details',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.onPrimary,
              ),
            ),

            const SizedBox(height: 1),
          ],
        ),
      ),

      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            7,
            12,
            7,
            24,
          ),
          children: [
            // =========================================================
            // DRIVER CARD
            // =========================================================

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),

              decoration: BoxDecoration(
                color: const Color(0xFFF1F3F6),
                borderRadius:
                    BorderRadius.circular(14),
              ),

              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,

                    decoration:
                        const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),

                    alignment: Alignment.center,

                    child: Text(
                      initial,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.driverName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 2),

                        Text(
                          trip.plateNumber,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.black54,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),

                    decoration: BoxDecoration(
                      color: AppColors.qrTileBg,
                      borderRadius:
                          BorderRadius.circular(20),
                    ),

                    child: Row(
                      children: [
                        const Icon(
                          Icons.star_rounded,
                          color: AppColors.qrIconColor,
                          size: 14,
                        ),

                        const SizedBox(width: 2),

                        Text(
                          trip.driverAverageRating != null
                              ? trip.driverAverageRating!.toStringAsFixed(1)
                              : 'New',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: AppColors.logoBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // =========================================================
            // RECEIPT
            // =========================================================

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFFE0E0E0),
                ),
              ),

              child: Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(
                      12,
                      12,
                      12,
                      10,
                    ),

                    child: Column(
                      children: [
                        const Align(
                          alignment:
                              Alignment.centerLeft,
                          child: Text(
                            'TRIP RECEIPT',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight:
                                  FontWeight.w900,
                              letterSpacing: 1.0,
                              color:
                                  AppColors.logoBlue,
                            ),
                          ),
                        ),

                        const SizedBox(height: 3),

                        Align(
                          alignment:
                              Alignment.centerLeft,
                          child: Text(
                            trip.dateTime,
                            style:
                                const TextStyle(
                              fontSize: 9,
                              color:
                                  Colors.black54,
                              fontWeight:
                                  FontWeight.w500,
                            ),
                          ),
                        ),

                        const SizedBox(height: 15),

                        _ReceiptRow(
                          label: 'Trip ID',
                          value: trip.tripId,
                        ),

                        const SizedBox(height: 9),

                        _ReceiptRow(
                          label: 'Route',
                          value: trip.route,
                        ),

                        const SizedBox(height: 9),

                        _ReceiptRow(
                          label: 'Boarding point',
                          value:
                              trip.boardingPoint,
                        ),

                        const SizedBox(height: 9),

                        _ReceiptRow(
                          label: 'Passengers',
                          value: trip.ridersLabel,
                        ),

                        const SizedBox(height: 9),

                        _ReceiptRow(
                          label: 'Jeepney',
                          value:
                              '${trip.plateNumber} · ${trip.driverName}',
                        ),

                        if (trip.regularRiders > 0) ...[
                          const SizedBox(height: 9),
                          _ReceiptRow(
                            label: '${trip.regularRiders} × Regular (₱${FareBreakdown.regularFare.toStringAsFixed(2)})',
                            value: '₱${trip.fareBreakdown.regularSubtotal.toStringAsFixed(2)}',
                          ),
                        ],

                        if (trip.studentRiders > 0) ...[
                          const SizedBox(height: 9),
                          _ReceiptRow(
                            label: '${trip.studentRiders} × Student (₱${FareBreakdown.discountedFare.toStringAsFixed(2)})',
                            value: '₱${trip.fareBreakdown.studentSubtotal.toStringAsFixed(2)}',
                          ),
                        ],

                        if (trip.seniorRiders > 0) ...[
                          const SizedBox(height: 9),
                          _ReceiptRow(
                            label: '${trip.seniorRiders} × Senior/PWD (₱${FareBreakdown.discountedFare.toStringAsFixed(2)})',
                            value: '₱${trip.fareBreakdown.seniorSubtotal.toStringAsFixed(2)}',
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ===================================================
                  // DOTTED SEPARATOR
                  // ===================================================

                  SizedBox(
                    height: 8,
                    child: Row(
                      children: List.generate(
                        30,
                        (index) => Expanded(
                          child: Container(
                            height: 3,
                            margin:
                                const EdgeInsets
                                    .symmetric(
                              horizontal: 2,
                            ),
                            decoration:
                                BoxDecoration(
                              color:
                                  const Color(
                                0xFFDDE2EA,
                              ),
                              borderRadius:
                                  BorderRadius
                                      .circular(4),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // ===================================================
                  // FARE
                  // ===================================================

                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),

                    decoration:
                        const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius:
                          BorderRadius.only(
                        bottomLeft:
                            Radius.circular(13),
                        bottomRight:
                            Radius.circular(13),
                      ),
                    ),

                    child: Row(
                      mainAxisAlignment:
                          MainAxisAlignment
                              .spaceBetween,
                      children: [
                        const Text(
                          'Total Fare',
                          style: TextStyle(
                            fontSize: 9,
                            color: AppColors.onPrimary,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),

                        Text(
                          trip.fare,
                          style: const TextStyle(
                            fontSize: 15,
                            color:
                                AppColors.textPrimary,
                            fontWeight:
                                FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // =========================================================
            // RATING
            // =========================================================

            const Text(
              'How was your driver?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.black,
              ),
            ),

            const SizedBox(height: 4),

            Row(
              children: List.generate(
                5,
                (index) {
                  final number = index + 1;

                  return GestureDetector(
                    onTap: _alreadyRated
                        ? null
                        : () {
                            setState(() {
                              _rating = number;
                            });
                          },

                    child: Padding(
                      padding:
                          const EdgeInsets.only(
                        right: 1,
                      ),

                      child: Icon(
                        Icons.star_rounded,
                        size: 27,
                        color: number <= _rating
                            ? (_alreadyRated
                                ? const Color(0xFFB9B9B9)
                                : AppColors.splashBackground)
                            : const Color(0xFFDDE1E7),
                      ),
                    ),
                  );
                },
              ),
            ),

            if (_alreadyRated)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  "You've already rated this trip.",
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.black45,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),

            const SizedBox(height: 7),

            // =========================================================
            // COMMENT
            // =========================================================

            Container(
              width: double.infinity,

              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFFE0E0E0),
                ),
              ),

              child: TextField(
                controller: _commentController,
                minLines: 3,
                maxLines: 4,

                decoration:
                    const InputDecoration(
                  hintText:
                      "Anything you'd like to add? (optional)",

                  hintStyle: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9EA4AE),
                  ),

                  border: InputBorder.none,

                  contentPadding:
                      EdgeInsets.all(12),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // =========================================================
            // SUBMIT RATING
            // =========================================================

            SizedBox(
              width: double.infinity,
              height: 36,

              child: ElevatedButton(
                onPressed: (_alreadyRated || _isSubmittingRating) ? null : _submitRating,

                style:
                    ElevatedButton.styleFrom(
                  backgroundColor: _alreadyRated
                      ? const Color(0xFFE1E4E8)
                      : const Color(0xFFFFD76A),
                  elevation: 0,

                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(20),
                  ),
                ),

                child: Text(
                  _alreadyRated
                      ? 'Rating Submitted'
                      : (_isSubmittingRating ? 'Submitting...' : 'Submit Rating'),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: _alreadyRated ? Colors.black45 : Colors.black87,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // =========================================================
            // REPORT DRIVER
            // =========================================================

            SizedBox(
              width: double.infinity,
              height: 34,

              child: OutlinedButton(
                onPressed: _alreadyReported ? null : _reportDriver,

                style:
                    OutlinedButton.styleFrom(
                  foregroundColor:
                      AppColors.logoBlue,

                  side: const BorderSide(
                    color: AppColors.logoBlue,
                    width: 1.1,
                  ),

                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(20),
                  ),
                ),

                child: Text(
                  _alreadyReported ? 'Report Submitted' : 'Report Driver',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// RECEIPT ROW
// ===========================================================================

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReceiptRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.black54,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          flex: 6,
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 9,
              color: Colors.black,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

// ===========================================================================
// REPORT DRIVER SCREEN
// ===========================================================================

class ReportDriverScreen extends StatefulWidget {
  final TripHistoryItem trip;

  const ReportDriverScreen({
    super.key,
    required this.trip,
  });

  @override
  State<ReportDriverScreen> createState() =>
      _ReportDriverScreenState();
}

class _ReportDriverScreenState
    extends State<ReportDriverScreen> {
  String? _selectedReason;

  final TextEditingController _detailsController =
      TextEditingController();

  final ImagePicker _picker = ImagePicker();
  File? _proofImage;

  // Matches the backend's COMPLAINT_TYPES enum exactly (see
  // POST /api/commuter/complaints in commuter.ts) — sent as-is as
  // complaintType, so this list can't drift from what the backend accepts.
  static const List<String> _reasons = [
    'Reckless Driving',
    'Overcharging',
    'Rude Behavior',
    'Route Deviation',
    'Other',
  ];

  bool _isSubmitting = false;

  bool get _alreadyReported =>
      CommuterHistoryScreen._reportedTripIds.contains(widget.trip.tripId);

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

      if (picked != null) {
        setState(() => _proofImage = File(picked.path));
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
            if (_proofImage != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text(
                  'Remove Photo',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _proofImage = null);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport() async {
    if (_alreadyReported || _isSubmitting) return;

    if (_selectedReason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please select a reason for your report.',
          ),
        ),
      );
      return;
    }

    if (_detailsController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please provide some details about the issue.',
          ),
        ),
      );
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _isSubmitting = true);

    try {
      await ApiClient.uploadFiles(
        '/api/commuter/complaints',
        files: _proofImage != null ? {'attachment': _proofImage!.path} : {},
        fields: {
          'plateNumber': widget.trip.plateNumber,
          'tripId': widget.trip.tripId,
          'complaintType': _selectedReason!,
          'description': _detailsController.text.trim(),
        },
        token: UserSession.instance.authToken,
      );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      CommuterHistoryScreen._reportedTripIds.add(widget.trip.tripId);
    });
    CommuterHistoryScreen._persistRatedAndReported();

    NotificationsScreen.push(
      AppNotification(
        icon: Icons.shield_rounded,
        iconBackground: AppColors.qrIconColor,
        title: 'Report Received',
        message: 'Your report has been received. Thank you for helping us improve.',
        time: DateTime.now(),
      ),
    );

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const _ReportSubmittedDialog(),
    ).then((_) {
      if (!mounted) return;
      Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;

    final initial = trip.driverName.trim().isEmpty
        ? 'D'
        : trip.driverName.trim()[0].toUpperCase();

    return Scaffold(
      backgroundColor:
          const Color(0xFFF5F6F8),

      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            _buildReportHeader(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                16,
                14,
                16,
                28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // =========================================================
            // DRIVER
            // =========================================================

            Container(
              padding:
                  const EdgeInsets.all(14),

              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(16),
                border: Border.all(
                  color:
                      const Color(0xFFE1E4E8),
                ),
              ),

              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,

                    decoration:
                        const BoxDecoration(
                      color: AppColors.logoBlue,
                      shape: BoxShape.circle,
                    ),

                    alignment:
                        Alignment.center,

                    child: Text(
                      initial,
                      style:
                          const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight:
                            FontWeight.w800,
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          trip.driverName,
                          style:
                              const TextStyle(
                            fontSize: 15,
                            fontWeight:
                                FontWeight.w800,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          '${trip.plateNumber} · ${trip.route}',
                          style:
                              const TextStyle(
                            fontSize: 11,
                            color:
                                Colors.black54,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // =========================================================
            // WARNING
            // =========================================================

            Container(
              padding:
                  const EdgeInsets.all(14),

              decoration: BoxDecoration(
                color:
                    const Color(0xFFFFF1F1),
                borderRadius:
                    BorderRadius.circular(14),
                border: Border.all(
                  color:
                      const Color(0xFFFFCACA),
                ),
              ),

              child: const Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color:
                        Color(0xFFE23F3F),
                    size: 22,
                  ),

                  SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      'Please only report genuine issues. '
                      'Your report will help us maintain a '
                      'safe and reliable commuting experience.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color:
                            Color(0xFF7A1F1F),
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // =========================================================
            // REASON
            // =========================================================

            const Text(
              'What happened?',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Select the reason that best describes the issue.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black45,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 12),

            ..._reasons.map(
              (reason) {
                final selected =
                    _selectedReason == reason;

                return Padding(
                  padding:
                      const EdgeInsets.only(
                    bottom: 9,
                  ),

                  child: Material(
                    color: Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(13),

                    child: InkWell(
                      borderRadius:
                          BorderRadius.circular(13),

                      onTap: () {
                        setState(() {
                          _selectedReason =
                              reason;
                        });
                      },

                      child: Container(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 14,
                          vertical: 13,
                        ),

                        decoration:
                            BoxDecoration(
                          borderRadius:
                              BorderRadius
                                  .circular(13),

                          border: Border.all(
                            color: selected
                                ? AppColors
                                    .primary
                                : const Color(
                                    0xFFE1E4E8,
                                  ),
                            width: selected
                                ? 1.5
                                : 1,
                          ),

                          color: selected
                              ? AppColors
                                  .qrTileBorder
                              : AppColors.qrTileBg,
                        ),

                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons
                                      .radio_button_checked_rounded
                                  : Icons
                                      .radio_button_off_rounded,

                              color: selected
                                  ? AppColors
                                      .onPrimary
                                  : Colors.black38,

                              size: 20,
                            ),

                            const SizedBox(
                              width: 10,
                            ),

                            Expanded(
                              child: Text(
                                reason,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                      FontWeight.w700,
                                  color: selected
                                      ? AppColors
                                          .onPrimary
                                      : Colors
                                          .black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 22),

            // =========================================================
            // DETAILS
            // =========================================================

            const Text(
              'Details',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Tell us what happened.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black45,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 10),

            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.circular(14),
                border: Border.all(
                  color:
                      const Color(0xFFE1E4E8),
                ),
              ),

              child: TextField(
                controller:
                    _detailsController,

                minLines: 5,
                maxLines: 7,

                textInputAction:
                    TextInputAction.newline,

                decoration:
                    const InputDecoration(
                  hintText:
                      'Describe what happened...',

                  hintStyle: TextStyle(
                    fontSize: 12,
                    color:
                        Color(0xFF9EA4AE),
                  ),

                  border:
                      InputBorder.none,

                  contentPadding:
                      EdgeInsets.all(14),
                ),

                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
            ),

            const SizedBox(height: 22),

            // =========================================================
            // PHOTO PROOF
            // =========================================================

            const Text(
              'Add Photo (Proof)',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),

            const SizedBox(height: 6),

            const Text(
              'Optional, but helps us investigate faster.',
              style: TextStyle(
                fontSize: 11,
                color: Colors.black45,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 10),

            GestureDetector(
              onTap: _alreadyReported ? null : _showImageSourceSheet,
              child: Container(
                width: double.infinity,
                height: _proofImage == null ? 120 : 200,
                decoration: BoxDecoration(
                  color: _proofImage == null ? AppColors.qrTileBg : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE1E4E8)),
                ),
                clipBehavior: Clip.antiAlias,
                child: _proofImage == null
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.add_a_photo_outlined,
                            size: 26,
                            color: AppColors.logoBlue,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tap to attach a photo',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      )
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(_proofImage!, fit: BoxFit.cover),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: GestureDetector(
                              onTap: () => setState(() => _proofImage = null),
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 22),

            // =========================================================
            // SUBMIT REPORT
            // =========================================================

            SizedBox(
              width: double.infinity,
              height: 48,

              child: ElevatedButton(
                onPressed: (_alreadyReported || _isSubmitting) ? null : _submitReport,

                style:
                    ElevatedButton.styleFrom(
                  backgroundColor: _alreadyReported
                      ? const Color(0xFFE1E4E8)
                      : AppColors.primary,
                  foregroundColor: _alreadyReported
                      ? Colors.black45
                      : AppColors.onPrimary,
                  elevation: 0,

                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(24),
                  ),
                ),

                child: Text(
                  _alreadyReported
                      ? 'Report Submitted'
                      : (_isSubmitting ? 'Submitting...' : 'Submit Report'),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // =========================================================
            // CANCEL
            // =========================================================

            SizedBox(
              width: double.infinity,
              height: 46,

              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                },

                style:
                    OutlinedButton.styleFrom(
                  foregroundColor:
                      AppColors.logoBlue,

                  side: const BorderSide(
                    color:
                        AppColors.logoBlue,
                    width: 1.2,
                  ),

                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(24),
                  ),
                ),

                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
              ),
            ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===============================================================
  // HEADER
  // ===============================================================
  // Same yellow banner + back button + title/subtitle convention used
  // across the other commuter screens.

  Widget _buildReportHeader(BuildContext context) {
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
                padding: EdgeInsets.all(10),
                child: Icon(Icons.arrow_back, size: 18, color: Colors.black87),
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
                  'Report Driver',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: AppColors.onPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tell us what happened during your trip',
                  style: TextStyle(fontSize: 11, color: Colors.black.withOpacity(0.55)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// REPORT SUBMITTED — compact confirmation. Tapping the dimmed background
// dismisses it (default showDialog barrier behavior); dismissing it (any
// way) pops the report screen back to Trip Details (handled by the
// caller's `.then()`).
// ===========================================================================

class _ReportSubmittedDialog extends StatelessWidget {
  const _ReportSubmittedDialog();

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
              'Report Submitted',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 4),
            const Text(
              "Thanks — we'll review this report.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: Colors.black45,
                fontWeight: FontWeight.w500,
              ),
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