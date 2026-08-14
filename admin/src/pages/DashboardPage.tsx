import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { StatCard } from '../components/StatCard';
import { TrendChart, type TrendPoint } from '../components/TrendChart';
import { VerificationBadge } from '../components/VerificationBadge';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { formatManilaDate } from '../lib/formatDate';

interface Stats {
  totalDrivers: number;
  totalCommuters: number;
  pendingVerifications: number;
  approvedVerifications: number;
  rejectedVerifications: number;
  newCommutersThisWeek: number;
  newDriversThisWeek: number;
  commutersChangePercent: number | null;
  driversChangePercent: number | null;
}

interface ActivityItem {
  type: 'driver' | 'commuter';
  id: string;
  identifier: string;
  fullName: string;
  photoUrl: string | null;
  createdAt: string;
}

function DriverIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <circle cx="12" cy="12" r="2.4" />
      <path d="M12 3v6.6M4.5 16.5l5-3.2M19.5 16.5l-5-3.2" />
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

function relativeTime(iso: string): string {
  const diffMs = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diffMs / 60_000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  return formatManilaDate(iso);
}

export default function DashboardPage() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [trend, setTrend] = useState<TrendPoint[] | null>(null);
  const [activity, setActivity] = useState<ActivityItem[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  function fetchAll() {
    apiClient
      .get<Stats>('/api/admin/stats')
      .then(setStats)
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load stats.'));
    apiClient
      .get<{ series: TrendPoint[] }>('/api/admin/trends?days=14')
      .then((res) => setTrend(res.series))
      .catch(() => {});
    apiClient
      .get<{ activity: ActivityItem[] }>('/api/admin/activity?limit=8')
      .then((res) => setActivity(res.activity))
      .catch(() => {});
  }

  useEffect(fetchAll, []);
  usePolling(fetchAll, 8000);

  return (
    <DashboardLayout>
      <div className="flex flex-col gap-1">
        <h1 className="text-2xl font-semibold tracking-tight text-gray-900">Dashboard</h1>
        <p className="text-sm text-gray-500">An overview of drivers and commuters on ManibelaApp.</p>
      </div>

      {error && <p className="mt-6 text-sm font-medium text-brand-red">{error}</p>}

      {stats && (
        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-4">
          <StatCard label="Total Drivers" value={stats.totalDrivers} icon={<DriverIcon />} />
          <StatCard label="Total Commuters" value={stats.totalCommuters} icon={<PeopleIcon />} />
          <StatCard
            label="New Drivers (7d)"
            value={stats.newDriversThisWeek}
            icon={<DriverIcon />}
            changePercent={stats.driversChangePercent}
          />
          <StatCard
            label="New Commuters (7d)"
            value={stats.newCommutersThisWeek}
            icon={<PeopleIcon />}
            changePercent={stats.commutersChangePercent}
          />
        </div>
      )}

      <div className="mt-6 grid grid-cols-1 gap-4 xl:grid-cols-3">
        {/* Trend chart */}
        <div className="rounded-xl border border-border-subtle bg-surface-card p-5 shadow-[0_1px_2px_rgba(16,24,40,0.04)] xl:col-span-2">
          <h2 className="text-sm font-semibold text-gray-900">Registrations — last 14 days</h2>
          {trend ? (
            <div className="mt-4">
              <TrendChart series={trend} />
            </div>
          ) : (
            <p className="mt-4 text-sm text-gray-400">Loading...</p>
          )}
        </div>

        {/* ID verification summary */}
        <div className="rounded-xl border border-border-subtle bg-surface-card p-5 shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
          <div className="flex items-center justify-between">
            <h2 className="text-sm font-semibold text-gray-900">ID Verification</h2>
            <Link to="/id-verification" className="text-xs font-semibold text-brand-blue hover:underline">
              View all
            </Link>
          </div>
          {stats && (
            <div className="mt-4 space-y-3">
              <div className="flex items-center justify-between">
                <VerificationBadge status="PENDING" />
                <span className="text-lg font-semibold text-gray-900">{stats.pendingVerifications}</span>
              </div>
              <div className="flex items-center justify-between">
                <VerificationBadge status="APPROVED" />
                <span className="text-lg font-semibold text-gray-900">{stats.approvedVerifications}</span>
              </div>
              <div className="flex items-center justify-between">
                <VerificationBadge status="REJECTED" />
                <span className="text-lg font-semibold text-gray-900">{stats.rejectedVerifications}</span>
              </div>
            </div>
          )}
        </div>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 xl:grid-cols-3">
        {/* Recent activity */}
        <div className="rounded-xl border border-border-subtle bg-surface-card p-5 shadow-[0_1px_2px_rgba(16,24,40,0.04)] xl:col-span-2">
          <h2 className="text-sm font-semibold text-gray-900">Recent Activity</h2>
          {!activity && <p className="mt-4 text-sm text-gray-400">Loading...</p>}
          {activity && activity.length === 0 && <p className="mt-4 text-sm text-gray-400">No activity yet.</p>}
          {activity && activity.length > 0 && (
            <ul className="mt-3 divide-y divide-gray-100">
              {activity.map((item) => (
                <li key={`${item.type}-${item.id}`} className="flex items-center gap-3 py-2.5">
                  <div className="h-8 w-8 shrink-0 overflow-hidden rounded-full bg-gray-200">
                    {item.photoUrl && (
                      <img
                        src={apiClient.resolveUrl(item.photoUrl) ?? undefined}
                        alt=""
                        className="h-full w-full object-cover"
                      />
                    )}
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-medium text-gray-900">{item.fullName}</p>
                    <p className="text-xs text-gray-500">
                      New {item.type} · {item.identifier}
                    </p>
                  </div>
                  <span className="shrink-0 text-xs text-gray-400">{relativeTime(item.createdAt)}</span>
                </li>
              ))}
            </ul>
          )}
        </div>

        {/* Quick actions */}
        <div className="rounded-xl border border-border-subtle bg-surface-card p-5 shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
          <h2 className="text-sm font-semibold text-gray-900">Quick Actions</h2>
          <div className="mt-3 flex flex-col gap-2">
            <Link
              to="/id-verification"
              className="flex items-center justify-between rounded-lg border border-border-subtle px-4 py-3 text-sm font-medium text-gray-700 transition hover:border-brand-blue hover:text-brand-blue"
            >
              Review pending ID submissions
              {stats && stats.pendingVerifications > 0 && (
                <span className="rounded-full bg-status-warning-bg px-2 py-0.5 text-xs font-semibold text-status-warning">
                  {stats.pendingVerifications}
                </span>
              )}
            </Link>
            <Link
              to="/drivers"
              className="flex items-center justify-between rounded-lg border border-border-subtle px-4 py-3 text-sm font-medium text-gray-700 transition hover:border-brand-blue hover:text-brand-blue"
            >
              Manage drivers
            </Link>
            <Link
              to="/commuters"
              className="flex items-center justify-between rounded-lg border border-border-subtle px-4 py-3 text-sm font-medium text-gray-700 transition hover:border-brand-blue hover:text-brand-blue"
            >
              Manage commuters
            </Link>
          </div>
        </div>
      </div>
    </DashboardLayout>
  );
}
