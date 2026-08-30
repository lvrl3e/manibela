/// "120m" under 1km, "1.2km" beyond it — precise enough to be useful
/// without implying GPS/routing accuracy the underlying estimate doesn't
/// have. Shared between the commuter's nearby-jeepney distances and the
/// driver's distance-to-passenger readout so both present the same figure
/// the same way.
String formatDistanceCompact(int meters) {
  if (meters < 1000) return '${meters}m';
  return '${(meters / 1000).toStringAsFixed(1)}km';
}

/// [formatDistanceCompact] with the commuter-facing "away" suffix, e.g.
/// "120m away" / "1.2km away".
String formatDistanceAway(int meters) => '${formatDistanceCompact(meters)} away';
