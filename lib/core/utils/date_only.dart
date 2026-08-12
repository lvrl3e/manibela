/// Formats/parses a date-of-birth as a plain "YYYY-MM-DD" string with no
/// time-of-day or timezone component, matching the backend's `@db.Date`
/// column.
///
/// Never use [DateTime.toIso8601String] / [DateTime.parse] for this: a
/// local [DateTime]'s ISO string has no offset suffix, so whatever parses
/// it next (including the backend, on a machine that may be in a
/// different timezone) can reinterpret it as its own local time —
/// silently shifting the calendar date near a timezone boundary. Named
/// `DateOnly` (not `DateUtils`) to avoid colliding with Flutter's own
/// `material` class of that name.
class DateOnly {
  const DateOnly._();

  /// `DateTime(2000, 5, 15)` -> `"2000-05-15"`.
  static String format(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// `"2000-05-15"` -> `DateTime(2000, 5, 15)` (local, no time-of-day).
  /// Returns null for null/empty/unparseable input.
  static DateTime? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(value);
    if (match == null) return null;
    return DateTime(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  /// `DateTime(2000, 5, 15)` -> `"15/05/2000"` — for display only, never
  /// for anything sent back over the wire (use [format] for that).
  static String displayDDMMYYYY(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString().padLeft(4, '0');
    return '$d/$m/$y';
  }
}
