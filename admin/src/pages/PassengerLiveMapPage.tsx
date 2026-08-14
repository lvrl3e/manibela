import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { LiveMap, type JeepneyMarker } from '../components/LiveMap';
import { LogoMark } from '../components/Logo';
import { apiClient } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';

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
  const [trips, setTrips] = useState<ActiveTripRow[]>([]);
  const [onboard, setOnboard] = useState<OnboardPassenger[]>([]);
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

  useEffect(() => {
    fetchTrips();
    fetchOnboard();
  }, []);
  usePolling(fetchTrips, 5000);
  usePolling(fetchOnboard, 5000);

  const passengersByTrip = useMemo(() => {
    const map = new Map<string, string[]>();
    for (const p of onboard) {
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
      trips
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

  const focusPosition = useMemo<[number, number] | null>(() => {
    const selected = markers.find((m) => m.id === selectedId);
    return selected ? [selected.lat, selected.lng] : null;
  }, [markers, selectedId]);

  return (
    <div className="flex h-screen w-full flex-col bg-surface-page">
      <header className="flex items-center gap-3 border-b border-gray-200 bg-white px-4 py-3 shadow-sm">
        <Link
          to="/passenger-monitoring"
          className="flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-sm font-semibold text-gray-600 hover:bg-gray-100"
        >
          <BackIcon />
          Back
        </Link>
        <div className="h-5 w-px bg-gray-200" />
        <LogoMark size={26} />
        <div>
          <p className="text-sm font-bold text-gray-900">Live Passenger Map</p>
          <p className="text-xs text-gray-500">{markers.length} jeepney(s) currently carrying passengers</p>
        </div>
      </header>

      <div className="flex min-h-0 flex-1">
        <aside className="flex w-80 shrink-0 flex-col border-r border-gray-200 bg-white">
          <div className="border-b border-gray-100 px-4 py-3">
            <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Jeepneys with riders</p>
          </div>
          <div className="flex-1 overflow-y-auto">
            {markers.length === 0 && <p className="p-4 text-sm text-gray-400">No one is currently on board.</p>}
            {markers.map((m) => (
              <button
                key={m.id}
                onClick={() => setSelectedId(m.id)}
                className={`flex w-full flex-col items-start gap-0.5 border-b border-gray-100 px-4 py-3 text-left transition hover:bg-gray-50 ${
                  selectedId === m.id ? 'bg-blue-50' : ''
                }`}
              >
                <span className="text-sm font-semibold text-gray-900">{m.plateNumber}</span>
                <span className="text-xs text-gray-500">
                  {m.driverName} · {m.route ?? 'No route set'}
                </span>
                <span className="text-xs text-gray-400">Onboard: {m.passengers?.join(', ')}</span>
              </button>
            ))}
          </div>
        </aside>

        <div className="flex-1">
          <LiveMap jeepneys={markers} zoom={14} focusPosition={focusPosition} />
        </div>
      </div>
    </div>
  );
}
