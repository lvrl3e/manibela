/// Mapbox raster tiles — replaces the plain OpenStreetMap tiles previously
/// used across every map in the app. Centralized here so the 5 screens
/// that each draw a map (see grep for `MapConfig.tileUrlTemplate`) share
/// one tile URL instead of duplicating it, and so swapping the visual
/// style later (e.g. a redesign in Mapbox Studio) is a one-line change
/// here instead of five.
class MapConfig {
  const MapConfig._();

  /// Set via `--dart-define=MAPBOX_ACCESS_TOKEN=...` at build time (see
  /// .github/workflows/build-apk.yml) — a Mapbox *public* token, safe to
  /// ship inside the compiled app the same way it's safe to ship inside
  /// any web page's source; Mapbox scopes/restricts it on their side, not
  /// by keeping it secret.
  static const String _accessToken = String.fromEnvironment('MAPBOX_ACCESS_TOKEN');

  /// ManibelaApp's own custom style — a warm neutral ground and one
  /// consistent dark label color instead of Mapbox Streets' defaults,
  /// but plain white/grey roads deliberately, not brand-colored: the
  /// route line drawn on top of the map (see RoutePath) is meant to be
  /// the only thing that reads as "highlighted", and colored roads
  /// underneath it competed with that. Built from the Mapbox Streets
  /// base via the Styles API. Overridable via
  /// `--dart-define=MAPBOX_STYLE_ID=...` for testing a different style
  /// without a code change. Republished under a fresh style ID rather
  /// than edited in place once before — Mapbox's CDN caches rendered
  /// tiles per exact style-id+coordinate for up to 2 hours regardless of
  /// later edits to that same style, so a new ID was the only way to
  /// make an already-viewed area reflect a style change immediately.
  static const String _styleId = String.fromEnvironment(
    'MAPBOX_STYLE_ID',
    defaultValue: 'lvrl3e/cmtfxoegm004q01sq2vxag5t5',
  );

  /// Mapbox's Raster Tiles API — a drop-in {z}/{x}/{y} URL template, same
  /// shape flutter_map's TileLayer already expected for the plain OSM
  /// tiles this replaces. @2x for crisp tiles on modern phone screens.
  static String get tileUrlTemplate =>
      'https://api.mapbox.com/styles/v1/$_styleId/tiles/256/{z}/{x}/{y}@2x?access_token=$_accessToken';

  /// Required by Mapbox's ToS whenever their tiles are displayed.
  static const String attribution = '© Mapbox © OpenStreetMap';
}
