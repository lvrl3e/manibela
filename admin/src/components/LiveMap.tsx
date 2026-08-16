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

export interface DemandMarker {
  id: string;
  lat: number;
  lng: number;
  count: number;
}

interface RawDemandSignal {
  id: string;
  lat: number;
  lng: number;
}

/** Buckets raw demand-signal pings into ~0.001°-square cells (~100m at this
 * latitude) and collapses each cell into one marker centered on its pings'
 * average position — same reasoning as any map heatmap: individual pings
 * are noisy and (deliberately, see DemandSignal's doc comment in
 * schema.prisma) not tied to a commuter identity on their own; a cluster is
 * a stable, honest "demand is around here." Mirrored exactly by the driver
 * app's own _clusterDemandSignals (driver_dashboard_screen.dart) so both
 * surfaces agree on where passengers are from the same raw rows. */
export function clusterDemandSignals(signals: RawDemandSignal[]): DemandMarker[] {
  const CELL_SIZE = 0.001;
  const buckets = new Map<string, { latSum: number; lngSum: number; count: number }>();

  for (const signal of signals) {
    const cellLat = Math.floor(signal.lat / CELL_SIZE);
    const cellLng = Math.floor(signal.lng / CELL_SIZE);
    const key = `${cellLat}:${cellLng}`;
    const bucket = buckets.get(key) ?? { latSum: 0, lngSum: 0, count: 0 };
    bucket.latSum += signal.lat;
    bucket.lngSum += signal.lng;
    bucket.count += 1;
    buckets.set(key, bucket);
  }

  return [...buckets.entries()].map(([key, b]) => ({
    id: key,
    lat: b.latSum / b.count,
    lng: b.lngSum / b.count,
    count: b.count,
  }));
}

// A person icon (not the jeepney glyph — this marks where passengers are,
// not a vehicle) so it reads distinctly from the blue jeepney markers at a
// glance; red once several pings stack in one cell (worth prioritizing),
// green for a lone ping — mirrors the driver app's own _WaitingStopPin
// (driver_dashboard_screen.dart) so both surfaces read the same. The count
// badge always shows how many, same as the driver app's version.
function demandIcon(count: number) {
  const color = count > 1 ? '#e23f3f' : '#1a9d5c';
  return L.divIcon({
    className: '',
    html: `<div style="position:relative;width:26px;height:26px;">
      <div style="width:26px;height:26px;border-radius:9999px;background:${color};border:2px solid white;box-shadow:0 1px 4px rgba(0,0,0,0.35);display:flex;align-items:center;justify-content:center;">
        <svg width="14" height="14" viewBox="0 0 24 24" fill="white"><circle cx="12" cy="8" r="4"/><path d="M4 20c0-4.4 3.6-8 8-8s8 3.6 8 8"/></svg>
      </div>
      <div style="position:absolute;top:-5px;right:-5px;min-width:15px;padding:1px 4px;border-radius:9999px;background:white;border:1.2px solid ${color};color:${color};font-size:9.5px;font-weight:800;text-align:center;line-height:1.3;">${count}</div>
    </div>`,
    iconSize: [26, 26],
    iconAnchor: [13, 13],
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
          <Popup>
            {d.count} ride request{d.count === 1 ? '' : 's'} near here
          </Popup>
        </Marker>
      ))}
      <FlyToTarget target={focusPosition} />
    </MapContainer>
  );
}
