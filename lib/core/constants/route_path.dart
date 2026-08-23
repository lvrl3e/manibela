import 'package:latlong2/latlong.dart';

/// A fixed, real road-following polyline tracing the actual Pasig–Quiapo
/// jeepney corridor — simplified (Douglas-Peucker, ~85 points) from a real
/// driving route rather than hand-guessed waypoints, so it actually follows
/// the streets instead of cutting through buildings. Used only to draw a
/// visual "trail" on the booking map (see [trailBetween]); it plays no part
/// in the ETA numbers themselves, which stay the server's own straight-line
/// estimate (see GET /commuter/nearby-jeepneys' own doc comment).
class RoutePath {
  RoutePath._();

  static const List<LatLng> pasigToQuiapo = [
    LatLng(14.576390, 121.085118),
    LatLng(14.568189, 121.080947),
    LatLng(14.567158, 121.080039),
    LatLng(14.566122, 121.077661),
    LatLng(14.566379, 121.071275),
    LatLng(14.566108, 121.070269),
    LatLng(14.564475, 121.069680),
    LatLng(14.563259, 121.068828),
    LatLng(14.562917, 121.067894),
    LatLng(14.562978, 121.066536),
    LatLng(14.563254, 121.065682),
    LatLng(14.563649, 121.065446),
    LatLng(14.569953, 121.066539),
    LatLng(14.570341, 121.066472),
    LatLng(14.580629, 121.054540),
    LatLng(14.581289, 121.053561),
    LatLng(14.578580, 121.051537),
    LatLng(14.578889, 121.051101),
    LatLng(14.579575, 121.045686),
    LatLng(14.581159, 121.044968),
    LatLng(14.581759, 121.044499),
    LatLng(14.581454, 121.043740),
    LatLng(14.582355, 121.042936),
    LatLng(14.582417, 121.042326),
    LatLng(14.581899, 121.041826),
    LatLng(14.580673, 121.042159),
    LatLng(14.581272, 121.043403),
    LatLng(14.581033, 121.043578),
    LatLng(14.581138, 121.043871),
    LatLng(14.581425, 121.043753),
    LatLng(14.581657, 121.044345),
    LatLng(14.578955, 121.044262),
    LatLng(14.578180, 121.042828),
    LatLng(14.575843, 121.041107),
    LatLng(14.576596, 121.039941),
    LatLng(14.576633, 121.039500),
    LatLng(14.575831, 121.035794),
    LatLng(14.576283, 121.035134),
    LatLng(14.576803, 121.034766),
    LatLng(14.577491, 121.034902),
    LatLng(14.578169, 121.034466),
    LatLng(14.578431, 121.033659),
    LatLng(14.578148, 121.033089),
    LatLng(14.581205, 121.029545),
    LatLng(14.584880, 121.027279),
    LatLng(14.585979, 121.025907),
    LatLng(14.589691, 121.023223),
    LatLng(14.584326, 121.017236),
    LatLng(14.582185, 121.013415),
    LatLng(14.581946, 121.013279),
    LatLng(14.580141, 121.007427),
    LatLng(14.585617, 121.006076),
    LatLng(14.586668, 121.005338),
    LatLng(14.587975, 121.006531),
    LatLng(14.588698, 121.006572),
    LatLng(14.589619, 121.006165),
    LatLng(14.589061, 121.005228),
    LatLng(14.589758, 121.004398),
    LatLng(14.590320, 121.004849),
    LatLng(14.590656, 121.005688),
    LatLng(14.592018, 121.005162),
    LatLng(14.592595, 121.004608),
    LatLng(14.592974, 121.003374),
    LatLng(14.592862, 121.001673),
    LatLng(14.597450, 121.001284),
    LatLng(14.600972, 120.999547),
    LatLng(14.600627, 120.999366),
    LatLng(14.597919, 120.996357),
    LatLng(14.597421, 120.995260),
    LatLng(14.596648, 120.994721),
    LatLng(14.596570, 120.992275),
    LatLng(14.597216, 120.991973),
    LatLng(14.597016, 120.991464),
    LatLng(14.597438, 120.991291),
    LatLng(14.597016, 120.991464),
    LatLng(14.596844, 120.991011),
    LatLng(14.596527, 120.990992),
    LatLng(14.596522, 120.989567),
    LatLng(14.597729, 120.989640),
    LatLng(14.600378, 120.991030),
    LatLng(14.603258, 120.984948),
    LatLng(14.603531, 120.983710),
    LatLng(14.603181, 120.984871),
    LatLng(14.603029, 120.984893),
    LatLng(14.599519, 120.984250),
    LatLng(14.599665, 120.983213),
    LatLng(14.599501, 120.983192),
  ];

  static final List<LatLng> quiapoToPasig = pasigToQuiapo.reversed.toList();

  /// Picks the direction matching one of the app's two exact route strings
  /// ('Pasig – Quiapo' / 'Quiapo – Pasig', see _routes in
  /// jeepney_booking_flow_screen.dart) — anything else (null, a future
  /// route) falls back to the Pasig→Quiapo ordering, since the corridor's
  /// shape is identical either way for drawing purposes.
  static List<LatLng> forRoute(String? route) {
    if (route == 'Quiapo – Pasig') return quiapoToPasig;
    return pasigToQuiapo;
  }

  /// How far along [path] (as a fractional segment index — e.g. 4.3 means
  /// 30% of the way from point 4 to point 5) [point]'s closest spot on the
  /// route is. Treats the corridor as locally flat (plain lat/lng
  /// distance, no spherical correction) — at this route's ~13km span that's
  /// within a few percent, plenty accurate for a visual trail.
  static double _projectFraction(LatLng point, List<LatLng> path) {
    var bestDistSq = double.infinity;
    var bestFraction = 0.0;
    for (var i = 0; i < path.length - 1; i++) {
      final a = path[i];
      final b = path[i + 1];
      final dx = b.longitude - a.longitude;
      final dy = b.latitude - a.latitude;
      final lenSq = dx * dx + dy * dy;
      var t = 0.0;
      if (lenSq > 0) {
        t = (((point.longitude - a.longitude) * dx) +
                ((point.latitude - a.latitude) * dy)) /
            lenSq;
        t = t.clamp(0.0, 1.0);
      }
      final px = a.longitude + t * dx;
      final py = a.latitude + t * dy;
      final distSq = (point.longitude - px) * (point.longitude - px) +
          (point.latitude - py) * (point.latitude - py);
      if (distSq < bestDistSq) {
        bestDistSq = distSq;
        bestFraction = i + t;
      }
    }
    return bestFraction;
  }

  static LatLng _pointAtFraction(double fraction, List<LatLng> path) {
    final i = fraction.floor().clamp(0, path.length - 2);
    final t = fraction - i;
    final a = path[i];
    final b = path[i + 1];
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  /// The stretch of the Pasig–Quiapo corridor between wherever [from] and
  /// [to] each sit closest to it — e.g. a jeepney's live position and the
  /// waiting commuter's own position — as its own polyline, snapped exactly
  /// onto the route rather than jumping to the nearest vertex. Used to draw
  /// each nearby jeepney's approach as a real road-shaped trail instead of
  /// a straight line, alongside the ETA already shown for that option.
  static List<LatLng> trailBetween(LatLng from, LatLng to, {String? route}) {
    final path = forRoute(route);
    final fFrom = _projectFraction(from, path);
    final fTo = _projectFraction(to, path);
    final lo = fFrom < fTo ? fFrom : fTo;
    final hi = fFrom < fTo ? fTo : fFrom;

    final points = <LatLng>[_pointAtFraction(lo, path)];
    for (var i = lo.ceil(); i <= hi.floor(); i++) {
      if (i > lo && i < hi) points.add(path[i]);
    }
    points.add(_pointAtFraction(hi, path));
    return points;
  }
}
