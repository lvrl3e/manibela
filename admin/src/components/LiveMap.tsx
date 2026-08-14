import { useEffect } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { formatManilaDateTime } from '../lib/formatDate';

export interface JeepneyMarker {
  id: string;
  lat: number;
  lng: number;
  driverName: string;
  plateNumber: string;
  route: string | null;
  /** Names of commuters currently marked on board this trip (see
   * TripBoarding's doc comment in schema.prisma) — shown as a list, not
   * a count, since a count would misleadingly imply it's the trip's full
   * ridership (riders without the app never show up here). Omitted
   * entirely on maps that aren't passenger-focused. */
  passengers?: string[];
  /** The following are only populated by Jeepney Monitoring's "View
   * Location" flow (see JeepneyLiveMapPage) — omitted on maps that source
   * markers from GET /trips/active, which doesn't carry this detail. */
  currentTripStartIso?: string | null;
  lastLocationUpdatedAtIso?: string | null;
  isOnline?: boolean;
}

export interface DemandMarker {
  id: string;
  lat: number;
  lng: number;
  /** How many signals this marker represents — callers pre-cluster
   * nearby points (see clusterDemandSignals) since raw signals can
   * overlap almost exactly at typical waiting spots. */
  count: number;
}

/** Groups demand signals into grid cells (~100m) and returns one marker
 * per cell with a count — a lightweight stand-in for real clustering,
 * proportionate to this being a simple live-demand view rather than a
 * dense analytics map. */
export function clusterDemandSignals(signals: { id: string; lat: number; lng: number }[]): DemandMarker[] {
  const cellSize = 0.001; // ~100m at this latitude
  const buckets = new Map<string, { latSum: number; lngSum: number; count: number; firstId: string }>();

  for (const s of signals) {
    const key = `${Math.round(s.lat / cellSize)}:${Math.round(s.lng / cellSize)}`;
    const bucket = buckets.get(key);
    if (bucket) {
      bucket.latSum += s.lat;
      bucket.lngSum += s.lng;
      bucket.count += 1;
    } else {
      buckets.set(key, { latSum: s.lat, lngSum: s.lng, count: 1, firstId: s.id });
    }
  }

  return [...buckets.entries()].map(([key, b]) => ({
    id: key || b.firstId,
    lat: b.latSum / b.count,
    lng: b.lngSum / b.count,
    count: b.count,
  }));
}

// Custom divIcons instead of Leaflet's default marker (whose image
// assets need bundler-specific path config to resolve correctly) — also
// lets these match the brand palette and the Figma's blue-jeepney /
// green-demand-cluster style directly.
const jeepneyIcon = L.divIcon({
  className: '',
  html: `<div style="width:30px;height:30px;border-radius:9999px;background:#0b57d0;border:2px solid white;box-shadow:0 1px 4px rgba(0,0,0,0.35);display:flex;align-items:center;justify-content:center;">
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2"><path d="M3 12l1.5-5A2 2 0 0 1 6.4 5.5h11.2a2 2 0 0 1 1.9 1.5L21 12"/><rect x="2" y="12" width="20" height="6" rx="1.5"/><circle cx="7" cy="18.5" r="1.5"/><circle cx="17" cy="18.5" r="1.5"/></svg>
  </div>`,
  iconSize: [30, 30],
  iconAnchor: [15, 15],
});

function demandIcon(count: number) {
  return L.divIcon({
    className: '',
    html: `<div style="width:28px;height:28px;border-radius:9999px;background:#0ca30c;border:2px solid white;box-shadow:0 1px 4px rgba(0,0,0,0.35);display:flex;align-items:center;justify-content:center;color:white;font-size:12px;font-weight:700;font-family:system-ui,sans-serif;">${count}</div>`,
    iconSize: [28, 28],
    iconAnchor: [14, 14],
  });
}

const PASIG_CITY_CENTER: [number, number] = [14.5764, 121.0851];

/** Imperatively pans/zooms the map when `target` changes — lets a sidebar
 * list (see the full-screen map pages) drive the map without lifting the
 * MapContainer instance itself out of react-leaflet's control. */
function FlyToTarget({ target }: { target: [number, number] | null }) {
  const map = useMap();
  useEffect(() => {
    if (target) map.flyTo(target, 17, { duration: 0.8 });
  }, [target, map]);
  return null;
}

export function LiveMap({
  jeepneys = [],
  demandSignals = [],
  center = PASIG_CITY_CENTER,
  zoom = 15,
  focusPosition = null,
}: {
  jeepneys?: JeepneyMarker[];
  demandSignals?: DemandMarker[];
  center?: [number, number];
  zoom?: number;
  /** When set, smoothly pans/zooms the map to this position (e.g. a
   * sidebar list item was clicked) — see FlyToTarget above. */
  focusPosition?: [number, number] | null;
}) {
  return (
    <MapContainer center={center} zoom={zoom} style={{ height: '100%', width: '100%' }} scrollWheelZoom>
      <TileLayer
        url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
      />
      {jeepneys.map((j) => (
        <Marker key={j.id} position={[j.lat, j.lng]} icon={jeepneyIcon}>
          <Popup>
            <div style={{ fontSize: 13 }}>
              <strong>{j.plateNumber}</strong>
              <br />
              Driver: {j.driverName}
              <br />
              Route: {j.route ?? '—'}
              {j.passengers && (
                <>
                  <br />
                  Onboard: {j.passengers.length > 0 ? j.passengers.join(', ') : 'none'}
                </>
              )}
              {j.isOnline !== undefined && (
                <>
                  <br />
                  Status: {j.isOnline ? 'Online' : 'Offline'}
                </>
              )}
              {j.currentTripStartIso !== undefined && (
                <>
                  <br />
                  Current Trip Start: {j.currentTripStartIso ? formatManilaDateTime(j.currentTripStartIso) : '—'}
                </>
              )}
              {j.lastLocationUpdatedAtIso !== undefined && (
                <>
                  <br />
                  Last Updated: {j.lastLocationUpdatedAtIso ? formatManilaDateTime(j.lastLocationUpdatedAtIso) : '—'}
                </>
              )}
            </div>
          </Popup>
        </Marker>
      ))}
      {demandSignals.map((d) => (
        <Marker key={d.id} position={[d.lat, d.lng]} icon={demandIcon(d.count)}>
          <Popup>{d.count} ride request{d.count === 1 ? '' : 's'} near here</Popup>
        </Marker>
      ))}
      <FlyToTarget target={focusPosition} />
    </MapContainer>
  );
}
