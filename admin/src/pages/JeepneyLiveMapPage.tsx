import { useEffect, useMemo, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { LiveMap, type JeepneyMarker } from '../components/LiveMap';
import { LogoMark } from '../components/Logo';
import { apiClient } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { isManilaToday } from '../lib/formatDate';

interface JeepneyRow {
  driverId: string;
  driverName: string;
  plateNumber: string;
  isOnline: boolean;
  route: string | null;
  currentTripStart: string | null;
  lastLat: number | null;
  lastLng: number | null;
  lastLocationUpdatedAt: string | null;
}

function BackIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M15 19l-7-7 7-7" />
    </svg>
  );
}

function SearchIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="11" cy="11" r="7" />
      <path d="m21 21-4-4" />
    </svg>
  );
}

/** Every jeepney with a known last position from *today* — online
 * (currently on a trip, live-ish position) and offline (showing wherever
 * it last reported from) alike, since "View Location" from Jeepney
 * Monitoring needs to work for both. A jeepney whose last ping was on an
 * earlier date is excluded rather than shown sitting at a stale spot,
 * which would misleadingly read as "still there." Sourced from GET
 * /api/admin/jeepneys, the same one-row-per-driver endpoint that page's
 * table uses, not the active-trips-only /trips/active this page used to
 * read from. */
export default function JeepneyLiveMapPage() {
  const [searchParams] = useSearchParams();
  const [jeepneys, setJeepneys] = useState<JeepneyRow[]>([]);
  const [search, setSearch] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(searchParams.get('driverId'));

  function fetchJeepneys() {
    apiClient
      .get<{ jeepneys: JeepneyRow[] }>('/api/admin/jeepneys')
      .then((res) => setJeepneys(res.jeepneys))
      .catch(() => {});
  }

  useEffect(fetchJeepneys, []);
  usePolling(fetchJeepneys, 5000);

  const markers: JeepneyMarker[] = useMemo(
    () =>
      jeepneys
        .filter((j) => j.lastLat != null && j.lastLng != null && j.lastLocationUpdatedAt != null && isManilaToday(j.lastLocationUpdatedAt))
        .map((j) => ({
          id: j.driverId,
          lat: j.lastLat!,
          lng: j.lastLng!,
          driverName: j.driverName,
          plateNumber: j.plateNumber,
          route: j.route,
          isOnline: j.isOnline,
          currentTripStartIso: j.currentTripStart,
          lastLocationUpdatedAtIso: j.lastLocationUpdatedAt,
        })),
    [jeepneys],
  );

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase();
    if (!q) return markers;
    return markers.filter(
      (m) => m.plateNumber.toLowerCase().includes(q) || m.driverName.toLowerCase().includes(q),
    );
  }, [markers, search]);

  const focusPosition = useMemo<[number, number] | null>(() => {
    const selected = markers.find((m) => m.id === selectedId);
    return selected ? [selected.lat, selected.lng] : null;
  }, [markers, selectedId]);

  return (
    <div className="flex h-screen w-full flex-col bg-surface-page">
      <header className="flex items-center gap-3 border-b border-gray-200 bg-white px-4 py-3 shadow-sm">
        <Link
          to="/jeepney-monitoring"
          className="flex items-center gap-1.5 rounded-lg px-2.5 py-1.5 text-sm font-semibold text-gray-600 hover:bg-gray-100"
        >
          <BackIcon />
          Back
        </Link>
        <div className="h-5 w-px bg-gray-200" />
        <LogoMark size={26} />
        <div>
          <p className="text-sm font-bold text-gray-900">Live Jeepney Map</p>
          <p className="text-xs text-gray-500">{markers.length} jeepney(s) with a location updated today</p>
        </div>
      </header>

      <div className="flex min-h-0 flex-1">
        <aside className="flex w-80 shrink-0 flex-col border-r border-gray-200 bg-white">
          <div className="border-b border-gray-100 p-3">
            <div className="flex items-center gap-2 rounded-lg border border-border-subtle bg-gray-50 px-3 py-2">
              <SearchIcon />
              <input
                value={search}
                onChange={(e) => setSearch(e.target.value)}
                placeholder="Search plate or driver"
                className="w-full bg-transparent text-sm text-gray-700 focus:outline-none"
              />
            </div>
          </div>
          <div className="flex-1 overflow-y-auto">
            {filtered.length === 0 && (
              <p className="p-4 text-sm text-gray-400">No jeepneys with a location updated today.</p>
            )}
            {filtered.map((m) => (
              <button
                key={m.id}
                onClick={() => setSelectedId(m.id)}
                className={`flex w-full flex-col items-start gap-0.5 border-b border-gray-100 px-4 py-3 text-left transition hover:bg-gray-50 ${
                  selectedId === m.id ? 'bg-blue-50' : ''
                }`}
              >
                <span className="flex w-full items-center justify-between">
                  <span className="text-sm font-semibold text-gray-900">{m.plateNumber}</span>
                  <span
                    className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold ${
                      m.isOnline ? 'bg-status-good-bg text-status-good' : 'bg-gray-100 text-gray-500'
                    }`}
                  >
                    {m.isOnline ? 'Online' : 'Offline'}
                  </span>
                </span>
                <span className="text-xs text-gray-500">{m.driverName}</span>
                <span className="text-xs text-gray-400">{m.route ?? 'No route set'}</span>
              </button>
            ))}
          </div>
        </aside>

        <div className="flex-1">
          <LiveMap jeepneys={filtered} zoom={14} focusPosition={focusPosition} />
        </div>
      </div>
    </div>
  );
}
