import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { LiveMap, clusterDemandSignals, type JeepneyMarker } from '../components/LiveMap';
import { LogoMark } from '../components/Logo';
import { RoutePill } from '../components/RoutePill';
import { apiClient } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';

interface DemandSignalRow {
  id: string;
  lat: number;
  lng: number;
  createdAt: string;
}

interface ActiveTripRow {
  id: string;
  driverName: string;
  plateNumber: string;
  route: string | null;
  currentLat: number | null;
  currentLng: number | null;
}

interface OnboardPassenger {
  tripId: string;
  commuterName: string;
}

function BackIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M15 19l-7-7 7-7" />
    </svg>
  );
}

export default function PassengerLiveMapPage() {
  // null = not yet loaded for each — distinct from "loaded, genuinely
  // empty," so the sidebar doesn't flash "No one is on board" / "No ride
  // requests" before the first fetch even resolves.
  const [trips, setTrips] = useState<ActiveTripRow[] | null>(null);
  const [onboard, setOnboard] = useState<OnboardPassenger[] | null>(null);
  const [demandSignals, setDemandSignals] = useState<DemandSignalRow[] | null>(null);
  const [selectedId, setSelectedId] = useState<string | null>(null);

  function fetchTrips() {
    apiClient
      .get<{ trips: ActiveTripRow[] }>('/api/admin/trips/active')
      .then((res) => setTrips(res.trips))
      .catch(() => {});
  }

  function fetchOnboard() {
    apiClient
      .get<{ passengers: OnboardPassenger[] }>('/api/admin/onboard-passengers')
      .then((res) => setOnboard(res.passengers))
      .catch(() => {});
  }

  // Raw pings from the last 15 minutes (see DEMAND_SIGNAL_WINDOW_MS in
  // admin.ts, and DemandSignal's doc comment in schema.prisma) — clustered
  // client-side below, same as the driver app's own copy of this logic.
  function fetchDemandSignals() {
    apiClient
      .get<{ signals: DemandSignalRow[] }>('/api/admin/demand-signals')
      .then((res) => setDemandSignals(res.signals))
      .catch(() => {});
  }

  useEffect(() => {
    fetchTrips();
    fetchOnboard();
    fetchDemandSignals();
  }, []);
  usePolling(fetchTrips, 5000);
  usePolling(fetchOnboard, 5000);
  // Matches the other feeds on this page — demand signals are exactly as
  // "live" a concern as jeepney positions, so there's no reason for this
  // one to lag behind on its own slower clock.
  usePolling(fetchDemandSignals, 5000);

  const passengersByTrip = useMemo(() => {
    const map = new Map<string, string[]>();
    for (const p of onboard ?? []) {
      const list = map.get(p.tripId) ?? [];
      list.push(p.commuterName);
      map.set(p.tripId, list);
    }
    return map;
  }, [onboard]);

  // Only jeepneys that currently have at least one passenger on board —
  // this map exists to show where riders actually are, not every jeepney
  // on the road (that's Jeepney Monitoring's job).
  const markers: JeepneyMarker[] = useMemo(
    () =>
      (trips ?? [])
        .filter((t) => t.currentLat != null && t.currentLng != null && (passengersByTrip.get(t.id)?.length ?? 0) > 0)
        .map((t) => ({
          id: t.id,
          lat: t.currentLat!,
          lng: t.currentLng!,
          driverName: t.driverName,
          plateNumber: t.plateNumber,
          route: t.route,
          passengers: passengersByTrip.get(t.id) ?? [],
        })),
    [trips, passengersByTrip],
  );

  const demandMarkers = useMemo(() => clusterDemandSignals(demandSignals ?? []), [demandSignals]);

  // Shared selection for both lists below — a jeepney and a demand
  // cluster live in different id spaces (a Trip id vs. a cell-bucket key),
  // so there's no real risk of one selection accidentally matching both.
  const focusPosition = useMemo<[number, number] | null>(() => {
    const selectedJeepney = markers.find((m) => m.id === selectedId);
    if (selectedJeepney) return [selectedJeepney.lat, selectedJeepney.lng];
    const selectedDemand = demandMarkers.find((d) => d.id === selectedId);
    return selectedDemand ? [selectedDemand.lat, selectedDemand.lng] : null;
  }, [markers, demandMarkers, selectedId]);

  // Loaded once every feed has resolved at least once — used only to
  // decide skeleton vs. real content in the sidebar below.
  const hasLoaded = trips !== null && onboard !== null && demandSignals !== null;

  return (
    <div className="flex h-screen w-full flex-col bg-surface-page">
      <header className="flex items-center gap-3 bg-gradient-to-r from-[#111c4d] via-ink to-black px-4 py-3 shadow-[0_1px_3px_rgba(16,24,40,0.12)]">
        <Link
          to="/passenger-monitoring"
          className="flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-sm font-semibold text-white/70 transition hover:bg-white/10 hover:text-white"
        >
          <BackIcon />
          Back
        </Link>
        <div className="h-5 w-px bg-white/15" />
        <LogoMark size={26} />
        <div>
          <p className="font-display text-sm font-bold text-white">Live Passenger Map</p>
          <p className="text-xs text-white/60">
            {hasLoaded
              ? `${markers.length} jeepney(s) currently carrying passengers · ${(demandSignals ?? []).length} ride request(s) in the last 15 minutes`
              : 'Loading…'}
          </p>
        </div>
      </header>

      <div className="flex min-h-0 flex-1">
        <aside className="flex w-80 shrink-0 flex-col border-r border-gray-200 bg-white">
          <div className="border-b border-gray-100 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Jeepneys with passengers</p>
          </div>
          <div className="flex-1 overflow-y-auto">
            {!hasLoaded &&
              Array.from({ length: 3 }).map((_, i) => (
                <div key={i} className="flex flex-col items-start gap-1.5 border-b border-gray-100 px-4 py-3">
                  <div className="h-4 w-20 animate-pulse rounded bg-gray-100" />
                  <div className="h-3 w-32 animate-pulse rounded bg-gray-100" />
                  <div className="h-3 w-24 animate-pulse rounded bg-gray-100" />
                </div>
              ))}
            {hasLoaded && markers.length === 0 && (
              <p className="p-4 text-sm text-gray-400">No one is currently on board.</p>
            )}
            {markers.map((m) => (
              <button
                key={m.id}
                onClick={() => setSelectedId(m.id)}
                className={`flex w-full flex-col items-start gap-1 border-b border-gray-100 px-4 py-3 text-left transition hover:bg-gray-50 ${
                  selectedId === m.id ? 'bg-blue-50' : ''
                }`}
              >
                <span className="flex w-full items-center justify-between">
                  <span className="font-display text-sm font-semibold text-gray-900">{m.plateNumber}</span>
                  <RoutePill route={m.route} />
                </span>
                <span className="text-xs text-gray-500">{m.driverName}</span>
                <span className="text-xs text-gray-400">Onboard: {m.passengers?.join(', ')}</span>
              </button>
            ))}
          </div>

          <div className="border-y border-gray-100 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Ride Requests (last 15 min)</p>
          </div>
          <div className="max-h-48 overflow-y-auto">
            {!hasLoaded &&
              Array.from({ length: 2 }).map((_, i) => (
                <div key={i} className="flex items-center justify-between border-b border-gray-100 px-4 py-2.5">
                  <div className="h-3 w-24 animate-pulse rounded bg-gray-100" />
                  <div className="h-5 w-16 animate-pulse rounded-full bg-gray-100" />
                </div>
              ))}
            {hasLoaded && demandMarkers.length === 0 && (
              <p className="p-4 text-sm text-gray-400">No ride requests right now.</p>
            )}
            {demandMarkers.map((d) => (
              <button
                key={d.id}
                onClick={() => setSelectedId(d.id)}
                className={`flex w-full items-center justify-between border-b border-gray-100 px-4 py-2.5 text-left transition hover:bg-gray-50 ${
                  selectedId === d.id ? 'bg-blue-50' : ''
                }`}
              >
                <span className="text-xs text-gray-600">
                  {d.lat.toFixed(4)}, {d.lng.toFixed(4)}
                </span>
                <span className="rounded-full bg-status-good-bg px-2 py-0.5 text-xs font-semibold text-status-good">
                  {d.count} request{d.count === 1 ? '' : 's'}
                </span>
              </button>
            ))}
          </div>
        </aside>

        <div className="flex-1">
          <LiveMap
            jeepneys={markers}
            demandSignals={demandMarkers}
            zoom={14}
            focusPosition={focusPosition}
            onDeselect={() => setSelectedId(null)}
          />
        </div>
      </div>
    </div>
  );
}
