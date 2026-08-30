import { useEffect, useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { StatCard } from '../components/StatCard';
import { SectionHeader } from '../components/Card';
import { StatCardSkeleton, TableSkeleton } from '../components/Skeleton';
import { RoutePill } from '../components/RoutePill';
import { JeepneyTripsPanel } from '../components/JeepneyTripsPanel';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { formatManilaTime, formatManilaDateTime } from '../lib/formatDate';

interface JeepneyStats {
  registeredJeepneys: number;
  online: number;
  offline: number;
  onlineChangePercent: number | null;
}

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

function MapPinFilledIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 21s7-6.4 7-12a7 7 0 0 0-14 0c0 5.6 7 12 7 12Z" />
      <circle cx="12" cy="9" r="2.4" />
    </svg>
  );
}

function OnlineIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <path d="m8.5 12.5 2.3 2.3 4.7-4.8" />
    </svg>
  );
}

function OfflineIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <path d="m9.5 9.5 5 5m0-5-5 5" />
    </svg>
  );
}

function ExpandIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M9 3H3v6M15 3h6v6M3 15v6h6M21 15v6h-6" />
    </svg>
  );
}

function PinIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 21s7-6.4 7-12a7 7 0 0 0-14 0c0 5.6 7 12 7 12Z" />
      <circle cx="12" cy="9" r="2.4" />
    </svg>
  );
}

function ClockIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7v5l3.5 2" />
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

function FleetIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <rect x="3" y="7" width="18" height="9" rx="2" />
      <path d="M3 11h18" />
      <circle cx="7.5" cy="18" r="1.6" />
      <circle cx="16.5" cy="18" r="1.6" />
    </svg>
  );
}

function formatLocation(lat: number | null, lng: number | null): string {
  if (lat === null || lng === null) return '—';
  return `${lat.toFixed(4)}, ${lng.toFixed(4)}`;
}

const STATUS_FILTERS: { label: string; value: '' | 'online' | 'offline' }[] = [
  { label: 'All', value: '' },
  { label: 'Online', value: 'online' },
  { label: 'Offline', value: 'offline' },
];

// The only two routes this fleet actually services — mirrors
// kDriverRoutes in the driver app's driver_start_trip_screen.dart, the
// exact strings a driver's route selection sends to the backend. Fixed
// here rather than derived from the current jeepney list so the filter
// still offers both routes even when nobody's currently running one of
// them.
const ROUTES = ['Pasig – Quiapo', 'Quiapo – Pasig'];

export default function JeepneyMonitoringPage() {
  const [stats, setStats] = useState<JeepneyStats | null>(null);
  // null = not yet loaded, distinct from "loaded, zero jeepneys" — needed so
  // the empty state and the skeleton don't collapse into the same check.
  const [jeepneys, setJeepneys] = useState<JeepneyRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [viewingTripsFor, setViewingTripsFor] = useState<JeepneyRow | null>(null);
  const [search, setSearch] = useState('');
  const [statusFilter, setStatusFilter] = useState<(typeof STATUS_FILTERS)[number]['value']>('');
  const [routeFilter, setRouteFilter] = useState('');

  function fetchStats() {
    apiClient.get<JeepneyStats>('/api/admin/jeepney-stats').then(setStats).catch(() => {});
  }

  function fetchJeepneys() {
    apiClient
      .get<{ jeepneys: JeepneyRow[] }>('/api/admin/jeepneys')
      .then((res) => setJeepneys(res.jeepneys))
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load jeepneys.'));
  }

  useEffect(() => {
    fetchStats();
    fetchJeepneys();
  }, []);
  usePolling(fetchStats, 8000);
  usePolling(fetchJeepneys, 8000);

  const filteredJeepneys = useMemo(() => {
    if (!jeepneys) return [];
    const q = search.trim().toLowerCase();
    return jeepneys.filter((j) => {
      if (statusFilter === 'online' && !j.isOnline) return false;
      if (statusFilter === 'offline' && j.isOnline) return false;
      if (routeFilter && j.route !== routeFilter) return false;
      if (!q) return true;
      return j.plateNumber.toLowerCase().includes(q) || j.driverName.toLowerCase().includes(q);
    });
  }, [jeepneys, search, statusFilter, routeFilter]);

  return (
    <DashboardLayout title="Jeepney Monitoring">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-col gap-1">
          <p className="text-sm text-gray-500">Live on the road, right now.</p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Link
            to="/jeepney-monitoring/history"
            className="flex items-center gap-2 rounded-lg border border-border-subtle bg-surface-card px-4 py-2.5 text-sm font-semibold text-gray-700 hover:bg-gray-50"
          >
            <ClockIcon />
            Trip History
          </Link>
          <Link
            to="/jeepney-monitoring/map"
            className="flex items-center gap-2 rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white hover:brightness-110"
          >
            <ExpandIcon />
            Open Full-Screen Map
          </Link>
        </div>
      </div>

      {stats ? (
        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <StatCard label="Registered Jeepneys" value={stats.registeredJeepneys} icon={<MapPinFilledIcon />} />
          <StatCard
            label="Online"
            value={stats.online}
            icon={<OnlineIcon />}
            changePercent={stats.onlineChangePercent}
            changeLabel="trips vs yesterday"
          />
          <StatCard label="Offline" value={stats.offline} icon={<OfflineIcon />} />
        </div>
      ) : (
        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <StatCardSkeleton key={i} />
          ))}
        </div>
      )}

      <div className="mt-6">
        <SectionHeader
          icon={<FleetIcon />}
          title="Fleet"
          action={
            <p className="text-sm text-gray-500">
              {jeepneys ? `${filteredJeepneys.length} of ${jeepneys.length} jeepney(s)` : ''}
            </p>
          }
        />
      </div>

      <div className="mt-3 flex flex-wrap items-center gap-3">
        <div className="flex min-w-[220px] flex-1 items-center gap-2 rounded-lg border border-border-subtle bg-surface-card px-3 py-2">
          <SearchIcon />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search plate or driver"
            className="w-full bg-transparent text-sm text-gray-700 focus:outline-none"
          />
        </div>
        <select
          value={routeFilter}
          onChange={(e) => setRouteFilter(e.target.value)}
          className="rounded-lg border border-border-subtle bg-white px-3 py-2 text-sm font-semibold text-gray-600 focus:border-brand-blue focus:outline-none"
        >
          <option value="">All Routes</option>
          {ROUTES.map((r) => (
            <option key={r} value={r}>
              {r}
            </option>
          ))}
        </select>
        <div className="flex flex-wrap gap-2">
          {STATUS_FILTERS.map((f) => (
            <button
              key={f.value}
              onClick={() => setStatusFilter(f.value)}
              className={`rounded-lg px-3.5 py-2 text-sm font-semibold transition ${
                statusFilter === f.value ? 'bg-brand-blue text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
      </div>

      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}
      {!error && jeepneys === null && <TableSkeleton columns={7} />}
      {!error && jeepneys !== null && jeepneys.length === 0 && (
        <p className="mt-4 text-sm text-gray-500">No jeepneys registered yet.</p>
      )}
      {!error && jeepneys !== null && jeepneys.length > 0 && filteredJeepneys.length === 0 && (
        <p className="mt-4 text-sm text-gray-500">No jeepneys match your search or filter.</p>
      )}

      {filteredJeepneys.length > 0 && (
        <div className="mt-4 overflow-x-auto rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
          <table className="w-full min-w-[920px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-5 py-3">Plate Number</th>
                <th className="px-5 py-3">Driver</th>
                <th className="px-5 py-3">Route</th>
                <th className="px-5 py-3">Current Trip Start</th>
                <th className="px-5 py-3">Last Location</th>
                <th className="px-5 py-3">Last Updated</th>
                <th className="px-5 py-3">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filteredJeepneys.map((j) => (
                <tr key={j.driverId} className="transition hover:bg-gray-50">
                  <td className="px-5 py-3">
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-gray-900">{j.plateNumber}</span>
                      <span
                        className={`inline-flex items-center rounded-full px-2 py-0.5 text-[10px] font-semibold ${
                          j.isOnline ? 'bg-status-good-bg text-status-good' : 'bg-gray-100 text-gray-500'
                        }`}
                      >
                        {j.isOnline ? 'Online' : 'Offline'}
                      </span>
                    </div>
                  </td>
                  <td className="px-5 py-3 text-gray-600">{j.driverName}</td>
                  <td className="px-5 py-3">
                    <RoutePill route={j.route} />
                  </td>
                  <td className="px-5 py-3 text-gray-600">
                    {j.currentTripStart ? formatManilaTime(j.currentTripStart) : '—'}
                  </td>
                  <td className="px-5 py-3 text-gray-600">{formatLocation(j.lastLat, j.lastLng)}</td>
                  <td className="px-5 py-3 text-gray-600">
                    {j.lastLocationUpdatedAt ? formatManilaDateTime(j.lastLocationUpdatedAt) : '—'}
                  </td>
                  <td className="px-5 py-3">
                    <div className="flex flex-wrap gap-2">
                      <Link
                        to={
                          j.lastLat !== null && j.lastLng !== null
                            ? `/jeepney-monitoring/map?driverId=${j.driverId}`
                            : '#'
                        }
                        aria-disabled={j.lastLat === null}
                        className={`flex items-center gap-1.5 rounded-lg border border-border-subtle px-2.5 py-1.5 text-xs font-semibold ${
                          j.lastLat === null
                            ? 'cursor-not-allowed text-gray-300'
                            : 'text-gray-600 hover:bg-gray-50 hover:text-brand-blue'
                        }`}
                        onClick={(e) => {
                          if (j.lastLat === null) e.preventDefault();
                        }}
                      >
                        <PinIcon />
                        View Location
                      </Link>
                      <button
                        onClick={() => setViewingTripsFor(j)}
                        className="flex items-center gap-1.5 rounded-lg border border-border-subtle px-2.5 py-1.5 text-xs font-semibold text-gray-600 hover:bg-gray-50 hover:text-brand-blue"
                      >
                        <ClockIcon />
                        View Trips
                      </button>
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {viewingTripsFor && (
        <JeepneyTripsPanel
          driverId={viewingTripsFor.driverId}
          driverName={viewingTripsFor.driverName}
          plateNumber={viewingTripsFor.plateNumber}
          onClose={() => setViewingTripsFor(null)}
        />
      )}
    </DashboardLayout>
  );
}
