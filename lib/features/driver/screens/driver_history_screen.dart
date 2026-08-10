import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/constants/app_colors.dart';

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

  const DriverTripHistoryItem({
    required this.tripId,
    required this.route,
    required this.plateNumber,
    required this.dateTime,
    required this.duration,
    required this.completedAt,
  });

  Map<String, dynamic> _toJson() => {
        'tripId': tripId,
        'route': route,
        'plateNumber': plateNumber,
        'dateTime': dateTime,
        'duration': duration,
        'completedAt': completedAt.toIso8601String(),
      };

  static DriverTripHistoryItem _fromJson(Map<String, dynamic> json) => DriverTripHistoryItem(
        tripId: json['tripId'] as String,
        route: json['route'] as String,
        plateNumber: json['plateNumber'] as String,
        dateTime: json['dateTime'] as String,
        duration: json['duration'] as String,
        // Older persisted entries (from before this field existed) won't
        // have it — fall back to "now" rather than crash on load.
        completedAt: json['completedAt'] != null
            ? DateTime.parse(json['completedAt'] as String)
            : DateTime.now(),
      );
}

// ===========================================================================
// DRIVER HISTORY SCREEN
// ===========================================================================

class DriverHistoryScreen extends StatelessWidget {
  const DriverHistoryScreen({super.key});

  static const _kPrefsKey = 'driver_trip_history_v1';

  // Mutable so completed trips (once the "Start Trip" flow actually
  // records them) can be appended here — this is the single source of
  // truth for driver trip history. Starts empty; a trip only shows up
  // once the driver actually completes one. Persisted to disk — logging
  // out must never erase a driver's trip record.
  static final List<DriverTripHistoryItem> _history = [];
  static bool _loaded = false;

  /// Loads whatever was previously persisted, once. Safe to call
  /// repeatedly — a no-op after the first successful load.
  static Future<void> loadFromPrefs() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kPrefsKey);
    if (raw != null) {
      try {
        _history
          ..clear()
          ..addAll(raw.map((s) => DriverTripHistoryItem._fromJson(jsonDecode(s) as Map<String, dynamic>)));
      } catch (_) {
        // Corrupt/old-format data on disk — start clean rather than crash.
      }
    }
    _loaded = true;
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kPrefsKey, _history.map((t) => jsonEncode(t._toJson())).toList());
  }

  /// Records a just-completed trip at the top of the history list.
  static Future<void> addTrip(DriverTripHistoryItem trip) async {
    _history.insert(0, trip);
    await _persist();
  }

  /// Wipes trip history on logout, per request — earnings/operations log
  /// (used for weekly/monthly reports) are untouched, only this list.
  static Future<void> clearOnLogout() async {
    _history.clear();
    await _persist();
  }

  /// How many trips were completed today — the real source for the
  /// dashboard's "Today's Trips" stat, so it reflects actual persisted
  /// history instead of a counter that resets on every login.
  static int get todayTripsCount {
    final now = DateTime.now();
    return _history.where((t) {
      final d = t.completedAt;
      return d.year == now.year && d.month == now.month && d.day == now.day;
    }).length;
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
            Expanded(
              child: _history.isEmpty
                  ? const _EmptyHistoryState()
                  : ListView(
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
                        ..._history.map(
                          (trip) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _TripHistoryCard(
                              trip: trip,
                              onTap: () => _openTripDetails(context, trip),
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
            'No trips yet',
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

// ===========================================================================
// TRIP DETAILS SCREEN
// ===========================================================================

class DriverTripDetailsScreen extends StatelessWidget {
  final DriverTripHistoryItem trip;

  const DriverTripDetailsScreen({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
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
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'TRIP SUMMARY',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.0,
                                color: AppColors.logoBlue,
                              ),
                            ),
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
                  trip.tripId,
                  style: TextStyle(fontSize: 10, color: Colors.black.withOpacity(0.55)),
                ),
              ],
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
