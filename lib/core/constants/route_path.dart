import 'package:latlong2/latlong.dart';

/// A fixed, real road-following polyline tracing the actual Pasig–Quiapo
/// jeepney corridor — the real, officially-registered LTFRB route ("Pasig
/// (TP) - Quiapo (Echague) via Sta. Mesa, C. Palanca", confirmed against
/// the public GTFS feed at github.com/sakayph/gtfs), traced via Mapbox's
/// Directions API with Sta. Mesa and Carlos Palanca St as waypoints (that
/// feed has no shape data for this specific route to trace exactly, so
/// this follows the same real streets rather than the feed's own
/// unavailable polyline) and simplified (Douglas-Peucker, ~50 points)
/// rather than hand-guessed. A second, unverified corridor briefly lived
/// here alongside this one; removed once this one was confirmed as the
/// actual registered route and the other wasn't. Used only to draw a
/// visual "trail" on the booking map (see [trailBetween]); it plays no
/// part in the ETA numbers themselves, which stay the server's own
/// straight-line estimate (see GET /commuter/nearby-jeepneys' own doc
/// comment).
class RoutePath {
  RoutePath._();

  static const List<LatLng> pasigToQuiapo = [
    LatLng(14.576409, 121.085129),
    LatLng(14.575961, 121.084898),
    LatLng(14.578373, 121.081715),
    LatLng(14.575236, 121.079447),
    LatLng(14.573591, 121.078534),
    LatLng(14.574876, 121.076296),
    LatLng(14.577512, 121.073278),
    LatLng(14.576327, 121.072742),
    LatLng(14.569717, 121.070941),
    LatLng(14.571393, 121.068744),
    LatLng(14.572115, 121.067436),
    LatLng(14.572240, 121.066871),
    LatLng(14.571925, 121.064579),
    LatLng(14.584205, 121.050221),
    LatLng(14.587374, 121.046289),
    LatLng(14.588956, 121.042398),
    LatLng(14.589476, 121.040430),
    LatLng(14.589449, 121.035326),
    LatLng(14.590450, 121.033945),
    LatLng(14.592243, 121.029964),
    LatLng(14.593258, 121.028130),
    LatLng(14.596162, 121.020429),
    LatLng(14.596764, 121.021471),
    LatLng(14.597273, 121.021296),
    LatLng(14.596764, 121.021471),
    LatLng(14.595949, 121.020022),
    LatLng(14.595973, 121.019832),
    LatLng(14.597610, 121.017616),
    LatLng(14.603012, 121.015881),
    LatLng(14.602679, 121.014956),
    LatLng(14.601137, 120.998635),
    LatLng(14.600590, 120.996179),
    LatLng(14.601600, 120.992786),
    LatLng(14.601001, 120.991606),
    LatLng(14.600431, 120.990967),
    LatLng(14.603258, 120.984948),
    LatLng(14.603531, 120.983710),
    LatLng(14.603429, 120.983695),
    LatLng(14.603272, 120.984630),
    LatLng(14.603083, 120.984897),
    LatLng(14.598268, 120.984006),
    LatLng(14.596904, 120.983622),
    LatLng(14.596703, 120.983439),
    LatLng(14.596382, 120.983674),
    LatLng(14.597368, 120.984017),
    LatLng(14.607630, 120.985976),
    LatLng(14.607887, 120.986283),
    LatLng(14.608100, 120.985930),
    LatLng(14.599519, 120.984250),
    LatLng(14.599665, 120.983213),
    LatLng(14.599501, 120.983192),
  ];

  /// The real Quiapo→Pasig return trip — deliberately *not*
  /// `pasigToQuiapo.reversed`. Confirmed via Mapbox Directions that this
  /// direction genuinely takes different streets (crosses the
  /// Legarda-Magsaysay Flyover and Old Santa Mesa St rather than
  /// retracing the outbound Magsaysay Blvd leg) — downtown Manila's
  /// one-way streets mean the outbound and return legs of a lot of real
  /// routes differ, this corridor included.
  static const List<LatLng> quiapoToPasig = [
    LatLng(14.599501, 120.983192),
    LatLng(14.599665, 120.983213),
    LatLng(14.600090, 120.981504),
    LatLng(14.602353, 120.981905),
    LatLng(14.603675, 120.981965),
    LatLng(14.603272, 120.984630),
    LatLng(14.600601, 120.990570),
    LatLng(14.600315, 120.990962),
    LatLng(14.600948, 120.991647),
    LatLng(14.601528, 120.992782),
    LatLng(14.600496, 120.996186),
    LatLng(14.601069, 120.998653),
    LatLng(14.602077, 121.010046),
    LatLng(14.602087, 121.011896),
    LatLng(14.600689, 121.013364),
    LatLng(14.597469, 121.015705),
    LatLng(14.597408, 121.016321),
    LatLng(14.597660, 121.017601),
    LatLng(14.595928, 121.019935),
    LatLng(14.596764, 121.021471),
    LatLng(14.597273, 121.021296),
    LatLng(14.596764, 121.021471),
    LatLng(14.596162, 121.020429),
    LatLng(14.593258, 121.028130),
    LatLng(14.592243, 121.029964),
    LatLng(14.590450, 121.033945),
    LatLng(14.589449, 121.035326),
    LatLng(14.589550, 121.039927),
    LatLng(14.588594, 121.040118),
    LatLng(14.587666, 121.039698),
    LatLng(14.586388, 121.041493),
    LatLng(14.586645, 121.043198),
    LatLng(14.585913, 121.044491),
    LatLng(14.587264, 121.046408),
    LatLng(14.584876, 121.049362),
    LatLng(14.571825, 121.064544),
    LatLng(14.572166, 121.066043),
    LatLng(14.572240, 121.066871),
    LatLng(14.572115, 121.067436),
    LatLng(14.571393, 121.068744),
    LatLng(14.569717, 121.070941),
    LatLng(14.567598, 121.070377),
    LatLng(14.566009, 121.070250),
    LatLng(14.566278, 121.071291),
    LatLng(14.565984, 121.076121),
    LatLng(14.565253, 121.075990),
    LatLng(14.565260, 121.076102),
    LatLng(14.566122, 121.077661),
    LatLng(14.567271, 121.080225),
    LatLng(14.567972, 121.080844),
    LatLng(14.576409, 121.085129),
  ];

  /// Picks the direction matching one of the app's two exact route strings
  /// ('Pasig – Quiapo' / 'Quiapo – Pasig', see kDriverRoutes in
  /// driver_start_trip_screen.dart) — anything else (null, an
  /// unrecognized value) falls back to the Pasig→Quiapo ordering.
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
