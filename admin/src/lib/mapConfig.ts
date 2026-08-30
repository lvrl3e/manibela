// Mapbox raster tiles — replaces the plain OpenStreetMap tiles previously
// used on the Live Map. Set VITE_MAPBOX_TOKEN in the Vercel project (see
// backend's MAPBOX_ACCESS_TOKEN — same underlying Mapbox public token,
// just under Vite's own env-var naming convention).
const MAPBOX_TOKEN = import.meta.env.VITE_MAPBOX_TOKEN ?? '';

// ManibelaApp's own custom style — see lib/core/constants/map_config.dart
// in the Flutter app for the full explanation; both platforms point at
// the same Mapbox style so the map looks identical everywhere.
const MAPBOX_STYLE_ID = import.meta.env.VITE_MAPBOX_STYLE_ID ?? 'lvrl3e/cmtfxoegm004q01sq2vxag5t5';

export const mapTileUrl = `https://api.mapbox.com/styles/v1/${MAPBOX_STYLE_ID}/tiles/256/{z}/{x}/{y}@2x?access_token=${MAPBOX_TOKEN}`;

export const mapAttribution =
  '&copy; <a href="https://www.mapbox.com/about/maps/">Mapbox</a> &copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>';
