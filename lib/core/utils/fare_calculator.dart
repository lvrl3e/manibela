/// Jeepney fares differ by passenger type: regular riders pay the full
/// fare, while students and seniors (PWD-equivalent discount under RA 9994
/// / RA 10963) pay a discounted fare. This is the single source of truth
/// for that math, shared by the booking flow (live summaries) and trip
/// history (receipts), so the numbers never drift between the two.
class FareBreakdown {
  final int regularRiders;
  final int studentRiders;
  final int seniorRiders;

  const FareBreakdown({
    this.regularRiders = 1,
    this.studentRiders = 0,
    this.seniorRiders = 0,
  });

  static const double regularFare = 15.00;
  static const double discountedFare = 12.00; // Student / Senior discount

  int get totalRiders => regularRiders + studentRiders + seniorRiders;

  double get regularSubtotal => regularRiders * regularFare;
  double get studentSubtotal => studentRiders * discountedFare;
  double get seniorSubtotal => seniorRiders * discountedFare;

  double get total => regularSubtotal + studentSubtotal + seniorSubtotal;

  String get totalLabel => '₱${total.toStringAsFixed(2)}';

  /// Short summary for a single-line summary row, e.g. "2 Regular, 1 Student".
  String get ridersLabel {
    final parts = <String>[];
    if (regularRiders > 0) parts.add('$regularRiders Regular');
    if (studentRiders > 0) parts.add('$studentRiders Student');
    if (seniorRiders > 0) parts.add('$seniorRiders Senior');
    if (parts.isEmpty) return 'None';
    return parts.join(', ');
  }
}
