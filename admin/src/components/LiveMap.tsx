import { useEffect, useRef, useState } from 'react';
import { MapContainer, TileLayer, Marker, Popup, useMap, useMapEvent } from 'react-leaflet';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';
import { formatManilaDateTime } from '../lib/formatDate';
import { mapTileUrl, mapAttribution } from '../lib/mapConfig';

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
// lets these match the brand palette and the yellow-jeepney /
// green-demand-cluster style directly.
const jeepneyIcon = L.divIcon({
  className: '',
  html: `<div style="width:30px;height:30px;border-radius:9999px;background:#eab308;border:2px solid white;box-shadow:0 1px 4px rgba(0,0,0,0.35);display:flex;align-items:center;justify-content:center;">
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
  /** How many people this commuter is requesting a ride for — see
   * DemandSignal.partySize's doc comment in schema.prisma. Null on
   * signals sent before this existed; treated as 1. */
  partySize?: number | null;
}

/** Buckets raw demand-signal pings into ~0.001°-square cells (~100m at this
 * latitude) and collapses each cell into one marker centered on its pings'
 * average position — same reasoning as any map heatmap: individual pings
 * are noisy and (deliberately, see DemandSignal's doc comment in
 * schema.prisma) not tied to a commuter identity on their own; a cluster is
 * a stable, honest "demand is around here." A marker's displayed count
 * sums party sizes, not ping count — a group of 4 booked from one account
 * reads as 4 waiting, not 1; position averaging still uses ping count, not
 * party size, since that's geometric centering, not headcount. Mirrored
 * exactly by the driver app's own _clusterDemandSignals
 * (driver_dashboard_screen.dart) so both surfaces agree on where
 * passengers are from the same raw rows. */
export function clusterDemandSignals(signals: RawDemandSignal[]): DemandMarker[] {
  const CELL_SIZE = 0.001;
  const buckets = new Map<string, { latSum: number; lngSum: number; pingCount: number; partySizeSum: number }>();

  for (const signal of signals) {
    const cellLat = Math.floor(signal.lat / CELL_SIZE);
    const cellLng = Math.floor(signal.lng / CELL_SIZE);
    const key = `${cellLat}:${cellLng}`;
    const bucket = buckets.get(key) ?? { latSum: 0, lngSum: 0, pingCount: 0, partySizeSum: 0 };
    bucket.latSum += signal.lat;
    bucket.lngSum += signal.lng;
    bucket.pingCount += 1;
    bucket.partySizeSum += signal.partySize ?? 1;
    buckets.set(key, bucket);
  }

  return [...buckets.entries()].map(([key, b]) => ({
    id: key,
    lat: b.latSum / b.pingCount,
    lng: b.lngSum / b.pingCount,
    count: b.partySizeSum,
  }));
}

// A person icon (not the jeepney glyph — this marks where passengers are,
// not a vehicle) so it reads distinctly from the yellow jeepney markers at
// a glance; red once several pings stack in one cell (worth prioritizing),
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

// Jeepney Monitoring polls GET /trips/active every 5s (see usePolling in
// JeepneyLiveMapPage) — a marker snapping straight to each new fix reads
// as teleporting rather than "the jeepney is actually moving." This glides
// it there instead, over slightly less than the poll interval so it
// settles before the next fix arrives. Mirrors the same glide added to the
// mobile app's own booking-flow map (jeepney_booking_flow_screen.dart).
const GLIDE_MS = 4800;

function useGlidingPosition(lat: number, lng: number): [number, number] {
  const [pos, setPos] = useState<[number, number]>([lat, lng]);
  const posRef = useRef<[number, number]>([lat, lng]);
  const fromRef = useRef<[number, number]>([lat, lng]);
  const toRef = useRef<[number, number]>([lat, lng]);
  const rafRef = useRef<number | null>(null);

  useEffect(() => {
    const target: [number, number] = [lat, lng];
    if (target[0] === toRef.current[0] && target[1] === toRef.current[1]) return;

    fromRef.current = posRef.current;
    toRef.current = target;
    const startedAt = performance.now();

    if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);

    const tick = (now: number) => {
      const t = Math.min(1, (now - startedAt) / GLIDE_MS);
      const from = fromRef.current;
      const to = toRef.current;
      const next: [number, number] = [from[0] + (to[0] - from[0]) * t, from[1] + (to[1] - from[1]) * t];
      posRef.current = next;
      setPos(next);
      rafRef.current = t < 1 ? requestAnimationFrame(tick) : null;
    };
    rafRef.current = requestAnimationFrame(tick);

    return () => {
      if (rafRef.current !== null) cancelAnimationFrame(rafRef.current);
    };
  }, [lat, lng]);

  return pos;
}

function GlidingJeepneyMarker({ jeepney }: { jeepney: JeepneyMarker }) {
  const position = useGlidingPosition(jeepney.lat, jeepney.lng);
  return (
    <Marker position={position} icon={jeepneyIcon}>
      <Popup>
        <div style={{ fontSize: 13 }}>
          <strong>{jeepney.plateNumber}</strong>
          <br />
          Driver: {jeepney.driverName}
          <br />
          Route: {jeepney.route ?? '—'}
          {jeepney.passengers && (
            <>
              <br />
              Onboard: {jeepney.passengers.length > 0 ? jeepney.passengers.join(', ') : 'none'}
            </>
          )}
          {jeepney.isOnline !== undefined && (
            <>
              <br />
              Status: {jeepney.isOnline ? 'Online' : 'Offline'}
            </>
          )}
          {jeepney.currentTripStartIso !== undefined && (
            <>
              <br />
              Current Trip Start: {jeepney.currentTripStartIso ? formatManilaDateTime(jeepney.currentTripStartIso) : '—'}
            </>
          )}
          {jeepney.lastLocationUpdatedAtIso !== undefined && (
            <>
              <br />
              Last Updated: {jeepney.lastLocationUpdatedAtIso ? formatManilaDateTime(jeepney.lastLocationUpdatedAtIso) : '—'}
            </>
          )}
        </div>
      </Popup>
    </Marker>
  );
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

/** Frames the map to whatever markers actually exist, once, the first time
 * they arrive — the fixed PASIG_CITY_CENTER default is a fallback for
 * before any data has loaded, not a promise that live jeepneys/demand will
 * fall inside that view. A real route can run for several km, easily
 * outside the default viewport, which otherwise reads as "the map is
 * empty" even though every marker is rendering correctly just off-screen.
 * Runs once per mount (not on every poll refresh) so the view doesn't keep
 * re-centering under an admin who's already looking at something. Skipped
 * entirely when a specific `focusPosition` was requested (e.g. "View
 * Location" from the Fleet table) — that's a more specific intent than
 * "show me everything," and the two shouldn't fight over the viewport at
 * the same time. */
function FitBoundsOnLoad({ positions, skip }: { positions: [number, number][]; skip: boolean }) {
  const map = useMap();
  const hasFitRef = useRef(false);
  useEffect(() => {
    if (skip || hasFitRef.current || positions.length === 0) return;
    hasFitRef.current = true;
    if (positions.length === 1) {
      map.setView(positions[0], 16);
    } else {
      map.fitBounds(L.latLngBounds(positions), { padding: [48, 48], maxZoom: 16 });
    }
  }, [skip, positions, map]);
  return null;
}

/** Clicking empty map area (not a marker — Leaflet doesn't bubble marker
 * clicks up to the map) clears whatever sidebar selection is driving
 * `focusPosition` and zooms back out to frame the fleet again. Without
 * this, tapping a sidebar item to zoom in was a one-way trip — there was
 * no way back except picking another item, since a click on open water or
 * open road did nothing. */
function ClickToDeselect({ positions, onDeselect }: { positions: [number, number][]; onDeselect: () => void }) {
  const map = useMap();
  useMapEvent('click', () => {
    onDeselect();
    if (positions.length === 1) {
      map.flyTo(positions[0], 16, { duration: 0.8 });
    } else if (positions.length > 1) {
      map.flyToBounds(L.latLngBounds(positions), { padding: [48, 48], maxZoom: 16, duration: 0.8 });
    }
  });
  return null;
}

export function LiveMap({
  jeepneys = [],
  demandSignals = [],
  center = PASIG_CITY_CENTER,
  zoom = 15,
  focusPosition = null,
  onDeselect,
}: {
  jeepneys?: JeepneyMarker[];
  demandSignals?: DemandMarker[];
  center?: [number, number];
  zoom?: number;
  /** When set, smoothly pans/zooms the map to this position (e.g. a
   * sidebar list item was clicked) — see FlyToTarget above. */
  focusPosition?: [number, number] | null;
  /** Called when the admin clicks empty map area — the caller should clear
   * whatever selection is driving `focusPosition` (see ClickToDeselect
   * above). Omit on a map with no selectable sidebar list. */
  onDeselect?: () => void;
}) {
  const markerPositions: [number, number][] = [
    ...jeepneys.map((j): [number, number] => [j.lat, j.lng]),
    ...demandSignals.map((d): [number, number] => [d.lat, d.lng]),
  ];

  return (
    <MapContainer center={center} zoom={zoom} style={{ height: '100%', width: '100%' }} scrollWheelZoom>
      <TileLayer url={mapTileUrl} attribution={mapAttribution} />
      <FitBoundsOnLoad positions={markerPositions} skip={focusPosition !== null} />
      {/* Only listens while a selection is actually active — otherwise an
          admin who's freely panned/zoomed the map themselves would get
          yanked back to the fleet overview on every idle click. */}
      {onDeselect && focusPosition && <ClickToDeselect positions={markerPositions} onDeselect={onDeselect} />}
      {jeepneys.map((j) => (
        <GlidingJeepneyMarker key={j.id} jeepney={j} />
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
