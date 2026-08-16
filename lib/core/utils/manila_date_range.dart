/// Converts a real instant (e.g. `DateTime.parse` of a backend 'Z'-suffixed
/// ISO timestamp, which keeps its fields in UTC) into a DateTime whose
/// y/m/d/h/m/s fields read as Asia/Manila's wall clock would at that
/// moment. Reading `.hour`/`.day`/etc. directly off a UTC-typed DateTime
/// shows UTC time, not Manila time, regardless of the device's own
/// timezone — a real bug this app hit (Trip History showing a time 8
/// hours behind the admin site's, which correctly pins to Asia/Manila).
/// Use this before reading any display field off a backend-sourced
/// timestamp. Safe as plain +8h arithmetic because Manila has a fixed
/// +08:00 offset with no DST (see [ManilaDateRange]'s own doc comment).
DateTime toManilaWallClock(DateTime instant) {
  return instant.toUtc().add(const Duration(hours: 8));
}

/// Builds `dateFrom`/`dateTo` boundaries for Trip History's Date filter,
/// pinned to Asia/Manila regardless of the device's own timezone — mirrors
/// the admin site's `manilaDateRangeForPreset`/`manilaDateRangeForCustom`
/// in lib/formatDate.ts, so "Today"/"This Week"/"This Month" mean the same
/// instant range on both platforms. Asia/Manila has a fixed +08:00 offset
/// (no DST), which is what makes this plain arithmetic safe.
class ManilaDateRange {
  const ManilaDateRange({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  static const _manilaOffset = Duration(hours: 8);

  /// Manila midnight for the given Manila calendar (year, month, day) as a
  /// real UTC instant. `DateTime.utc(y, m, d)` is UTC midnight for that
  /// date; Manila is 8 hours ahead, so Manila midnight is 8 hours *before*
  /// that same UTC instant.
  static DateTime _manilaMidnightUtc(int year, int month, int day) {
    return DateTime.utc(year, month, day).subtract(_manilaOffset);
  }

  /// Today's Manila calendar date, as a UTC-typed DateTime whose y/m/d
  /// fields read as Manila's wall clock would right now — found by
  /// shifting the current UTC instant forward 8 hours. Only ever used to
  /// read `.year`/`.month`/`.day`/`.weekday` off, never as a real instant.
  static DateTime _todayManilaCalendarDate() {
    return DateTime.now().toUtc().add(_manilaOffset);
  }

  /// [from, to) — `to` is always "start of tomorrow" (Manila), so every
  /// preset includes the whole of today, not just up to the current
  /// moment. "week" starts Monday (DateTime.weekday is already
  /// ISO/Monday-first, 1..7).
  factory ManilaDateRange.preset(String preset) {
    final today = _todayManilaCalendarDate();
    final todayMidnight = _manilaMidnightUtc(today.year, today.month, today.day);
    final to = todayMidnight.add(const Duration(days: 1));

    if (preset == 'today') {
      return ManilaDateRange(from: todayMidnight, to: to);
    }
    if (preset == 'month') {
      final firstOfMonth = _manilaMidnightUtc(today.year, today.month, 1);
      return ManilaDateRange(from: firstOfMonth, to: to);
    }
    // 'week': DateTime.utc(y, m, d).weekday on the plain calendar date
    // (not the real Manila-midnight instant, which is 8h offset and would
    // read the wrong day) gives the correct ISO weekday, 1=Monday..7=Sunday.
    final weekday = DateTime.utc(today.year, today.month, today.day).weekday;
    final monday = todayMidnight.subtract(Duration(days: weekday - 1));
    return ManilaDateRange(from: monday, to: to);
  }

  /// [from, to) for a Custom Date Range picker's two calendar dates — `to`
  /// is the day *after* [toDate] at Manila midnight, so the end date picked
  /// is fully included. Only [fromDate]/[toDate]'s own year/month/day are
  /// read — treated as Manila calendar dates directly, same as the admin
  /// site's `<input type="date">` values.
  factory ManilaDateRange.custom(DateTime fromDate, DateTime toDate) {
    final from = _manilaMidnightUtc(fromDate.year, fromDate.month, fromDate.day);
    final to = _manilaMidnightUtc(toDate.year, toDate.month, toDate.day).add(const Duration(days: 1));
    return ManilaDateRange(from: from, to: to);
  }
}
