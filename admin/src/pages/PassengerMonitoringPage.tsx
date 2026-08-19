import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { StatCard } from '../components/StatCard';
import { SectionHeader } from '../components/Card';
import { StatCardSkeleton, TableSkeleton } from '../components/Skeleton';
import { RoutePill } from '../components/RoutePill';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { formatManilaTime } from '../lib/formatDate';

interface PassengerStats {
  totalCommuters: number;
  activeCommuters: number;
  inactiveCommuters: number;
  currentlyOnBoard: number;
  demandSignalsToday: number;
  totalCommutersChangePercent: number | null;
}

interface OnboardPassenger {
  id: string;
  commuterName: string;
  mobileNumber: string | null;
  driverName: string;
  plateNumber: string;
  route: string | null;
  boardedAt: string;
}

function BusPersonIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="3" y="5" width="18" height="11" rx="2.5" />
      <path d="M3 11h18" />
      <circle cx="7.5" cy="19" r="1.4" />
      <circle cx="16.5" cy="19" r="1.4" />
    </svg>
  );
}

function PeopleIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="9" cy="8" r="3.2" />
      <path d="M2.5 20c0-3.6 2.9-6.2 6.5-6.2s6.5 2.6 6.5 6.2" />
      <circle cx="17.5" cy="9" r="2.6" />
      <path d="M15.8 13.9c2.9.4 4.7 2.6 4.7 6.1" />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <path d="m8.5 12.5 2.3 2.3 4.7-4.8" />
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
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 21s7-6.5 7-12a7 7 0 0 0-14 0c0 5.5 7 12 7 12Z" />
      <circle cx="12" cy="9" r="2.5" />
    </svg>
  );
}

function OnboardIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <rect x="3" y="5" width="18" height="11" rx="2.5" />
      <path d="M3 11h18" />
      <circle cx="7.5" cy="19" r="1.4" />
      <circle cx="16.5" cy="19" r="1.4" />
    </svg>
  );
}

export default function PassengerMonitoringPage() {
  const [stats, setStats] = useState<PassengerStats | null>(null);
  // null = not yet loaded, distinct from "loaded, nobody's on board" — see
  // the same fix on Jeepney Monitoring's fleet list.
  const [onboard, setOnboard] = useState<OnboardPassenger[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  function fetchStats() {
    apiClient.get<PassengerStats>('/api/admin/commuter-stats').then(setStats).catch(() => {});
  }

  function fetchOnboard() {
    apiClient
      .get<{ passengers: OnboardPassenger[] }>('/api/admin/onboard-passengers')
      .then((res) => setOnboard(res.passengers))
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load onboard passengers.'));
  }

  useEffect(() => {
    fetchStats();
    fetchOnboard();
  }, []);
  usePolling(fetchStats, 8000);
  usePolling(fetchOnboard, 5000);

  return (
    <DashboardLayout title="Passenger Monitoring">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-col gap-1">
          <p className="text-sm text-gray-500">Who's actually riding right now.</p>
        </div>
        <Link
          to="/passenger-monitoring/map"
          className="flex items-center gap-2 rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white hover:brightness-110"
        >
          <ExpandIcon />
          Open Full-Screen Map
        </Link>
      </div>

      {stats ? (
        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          <StatCard label="Currently On Board" value={stats.currentlyOnBoard} icon={<BusPersonIcon />} />
          <StatCard
            label="Total Commuters"
            value={stats.totalCommuters}
            icon={<PeopleIcon />}
            changePercent={stats.totalCommutersChangePercent}
            changeLabel="vs last month"
          />
          <StatCard label="Active Commuters" value={stats.activeCommuters} icon={<CheckIcon />} />
          <StatCard label="Ride Requests Today" value={stats.demandSignalsToday} icon={<PinIcon />} />
        </div>
      ) : (
        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {Array.from({ length: 4 }).map((_, i) => (
            <StatCardSkeleton key={i} />
          ))}
        </div>
      )}

      <div className="mt-8">
        <SectionHeader
          icon={<OnboardIcon />}
          title="Currently On Board"
          action={<p className="text-sm text-gray-500">{onboard ? `${onboard.length} passenger(s)` : ''}</p>}
        />
      </div>
      <p className="mt-1 text-sm text-gray-500">
        Recorded whenever a commuter scans a driver's QR code while that driver has an active trip — cleared once the
        driver ends the trip, or the commuter taps End Trip.
      </p>

      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}
      {!error && onboard === null && <TableSkeleton columns={5} />}
      {!error && onboard !== null && onboard.length === 0 && (
        <p className="mt-4 text-sm text-gray-500">No one is currently on board.</p>
      )}

      {onboard !== null && onboard.length > 0 && (
        <div className="mt-4 overflow-x-auto rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
          <table className="w-full min-w-[640px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-5 py-3">Commuter</th>
                <th className="px-5 py-3">Driver</th>
                <th className="px-5 py-3">Plate Number</th>
                <th className="px-5 py-3">Route</th>
                <th className="px-5 py-3">Boarded</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {onboard.map((p) => (
                <tr key={p.id} className="transition hover:bg-gray-50">
                  <td className="px-5 py-3 font-medium text-gray-900">{p.commuterName}</td>
                  <td className="px-5 py-3 text-gray-600">{p.driverName}</td>
                  <td className="px-5 py-3 text-gray-600">{p.plateNumber}</td>
                  <td className="px-5 py-3">
                    <RoutePill route={p.route} />
                  </td>
                  <td className="px-5 py-3 text-gray-600">{formatManilaTime(p.boardedAt)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardLayout>
  );
}
