import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A single day's odometer/earnings/expense entry, plus the derived
/// metrics computed from it. Persisted to disk (see [DriverOperationsLog])
/// so the Daily Operations, Weekly Analytics, and Monthly Analytics
/// screens keep their history across app restarts and logout/login —
/// there's no backend yet, but this data still needs to actually survive.
class DriverOperationsEntry {
  final DateTime date;
  final double startOdo;
  final double endOdo;
  final double totalEarnings;
  final double fuelExpense;
  final double otherExpenses;

  const DriverOperationsEntry({
    required this.date,
    required this.startOdo,
    required this.endOdo,
    required this.totalEarnings,
    required this.fuelExpense,
    required this.otherExpenses,
  });

  double get distanceKm {
    final d = endOdo - startOdo;
    return d > 0 ? d : 0;
  }

  double get totalExpenses => fuelExpense + otherExpenses;

  double get netIncome => totalEarnings - totalExpenses;

  /// Revenue earned per kilometer driven.
  double get incomePerKm => distanceKm > 0 ? totalEarnings / distanceKm : 0;

  /// Fuel cost per kilometer driven.
  double get fuelCostPerKm => distanceKm > 0 ? fuelExpense / distanceKm : 0;

  Map<String, dynamic> _toJson() => {
        'date': date.toIso8601String(),
        'startOdo': startOdo,
        'endOdo': endOdo,
        'totalEarnings': totalEarnings,
        'fuelExpense': fuelExpense,
        'otherExpenses': otherExpenses,
      };

  static DriverOperationsEntry _fromJson(Map<String, dynamic> json) {
    return DriverOperationsEntry(
      date: DateTime.parse(json['date'] as String),
      startOdo: (json['startOdo'] as num).toDouble(),
      endOdo: (json['endOdo'] as num).toDouble(),
      totalEarnings: (json['totalEarnings'] as num).toDouble(),
      fuelExpense: (json['fuelExpense'] as num).toDouble(),
      otherExpenses: (json['otherExpenses'] as num).toDouble(),
    );
  }
}

/// Static, in-memory (mirrored to disk) log of daily operations entries,
/// keyed by calendar day. A driver can only have one entry per day —
/// saving again for the same day overwrites it, same as editing a form.
///
/// Logging out must NEVER erase this — it's the driver's actual earnings
/// record, not session state. [save] persists immediately; call
/// [loadFromPrefs] once (from the login flow) before reading anything, so
/// a cold app start has real data instead of an empty log.
class DriverOperationsLog {
  DriverOperationsLog._();

  static const _kPrefsKey = 'driver_operations_log_v1';

  static final Map<String, DriverOperationsEntry> _byDateKey = {};
  static bool _loaded = false;

  static String _keyFor(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// Loads whatever was previously persisted, once. Safe to call
  /// repeatedly — after the first successful load it's a no-op, so
  /// callers don't need to track whether they've already loaded it.
  static Future<void> loadFromPrefs() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kPrefsKey);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        _byDateKey
          ..clear()
          ..addEntries(decoded.entries.map(
            (e) => MapEntry(e.key, DriverOperationsEntry._fromJson(e.value as Map<String, dynamic>)),
          ));
      } catch (_) {
        // Corrupt/old-format data on disk — start clean rather than crash.
      }
    }
    _loaded = true;
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode(_byDateKey.map((key, entry) => MapEntry(key, entry._toJson())));
    await prefs.setString(_kPrefsKey, encoded);
  }

  static Future<void> save(DriverOperationsEntry entry) async {
    _byDateKey[_keyFor(entry.date)] = entry;
    await _persist();
  }

  static DriverOperationsEntry? get todayEntry => _byDateKey[_keyFor(DateTime.now())];

  static DriverOperationsEntry? forDate(DateTime date) => _byDateKey[_keyFor(date)];

  /// All logged entries, most recent first.
  static List<DriverOperationsEntry> get allEntries {
    final entries = _byDateKey.values.toList();
    entries.sort((a, b) => b.date.compareTo(a.date));
    return entries;
  }

  /// Entries logged on or after [since] (inclusive), most recent first.
  static List<DriverOperationsEntry> entriesSince(DateTime since) {
    final cutoff = DateTime(since.year, since.month, since.day);
    return allEntries.where((e) {
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      return !day.isBefore(cutoff);
    }).toList();
  }

  /// Entries logged between [start] and [end], inclusive on both ends,
  /// most recent first. Used to page back through previous weeks/months.
  static List<DriverOperationsEntry> entriesBetween(DateTime start, DateTime end) {
    final startDay = DateTime(start.year, start.month, start.day);
    final endDay = DateTime(end.year, end.month, end.day);
    return allEntries.where((e) {
      final day = DateTime(e.date.year, e.date.month, e.date.day);
      return !day.isBefore(startDay) && !day.isAfter(endDay);
    }).toList();
  }
}
