import { useEffect, useState, type ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { StatCard } from '../components/StatCard';
import { Card, SectionHeader } from '../components/Card';
import { StatCardSkeleton } from '../components/Skeleton';
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
  totalDriversChangePercent: number | null;
  totalCommutersChangePercent: number | null;
  activeTrips: number;
  openComplaints: number;
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

function TripIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="5" cy="18" r="2" />
      <circle cx="19" cy="6" r="2" />
      <path d="M6.8 16.6C11 12.5 13 11.5 17.2 7.4" strokeDasharray="2.6 2.6" />
    </svg>
  );
}

function ComplaintIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 3 2 20h20L12 3Z" strokeLinejoin="round" />
      <path d="M12 10v4" strokeLinecap="round" />
      <circle cx="12" cy="17" r="0.9" fill="currentColor" stroke="none" />
    </svg>
  );
}

function ChartIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M4 20V10M12 20V4M20 20v-7" strokeLinecap="round" />
    </svg>
  );
}

function ShieldCheckIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M12 3l7 3v5c0 4.5-3 8-7 10-4-2-7-5.5-7-10V6l7-3Z" strokeLinejoin="round" />
      <path d="M9 12l2 2 4-4" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function PulseIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M3 12h4l2 6 4-12 2 6h6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function BoltIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M13 2 4 14h6l-1 8 9-12h-6l1-8Z" strokeLinejoin="round" strokeLinecap="round" />
    </svg>
  );
}

function ChevronRightIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <path d="M9 6l6 6-6 6" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  );
}

function IdCardIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <circle cx="8.5" cy="11" r="1.8" />
      <path d="M6 15.5c.5-1.3 1.5-2 2.5-2s2 .7 2.5 2M14 10h4M14 13.5h4" strokeLinecap="round" />
    </svg>
  );
}

function QuickActionLink({ to, icon, label, badge }: { to: string; icon: ReactNode; label: string; badge?: number }) {
  return (
    <Link
      to={to}
      className="group flex items-center gap-3 rounded-lg border border-border-subtle px-4 py-3 text-sm font-medium text-gray-700 transition hover:border-brand-blue hover:bg-blue-50/40"
    >
      <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-lg bg-gray-50 text-gray-500 transition group-hover:bg-blue-100 group-hover:text-brand-blue">
        {icon}
      </span>
      <span className="flex-1">{label}</span>
      {badge !== undefined && badge > 0 && (
        <span className="rounded-full bg-status-warning-bg px-2 py-0.5 text-xs font-semibold text-status-warning">
          {badge}
        </span>
      )}
      <span className="text-gray-300 transition group-hover:text-brand-blue">
        <ChevronRightIcon />
      </span>
    </Link>
  );
}

// Loading placeholders shaped like the content they'll be replaced by
// (StatCardSkeleton lives in ../components/Skeleton — shared with the
// Jeepney Monitoring stat row).
function ChartSkeleton() {
  return (
    <div className="mt-4 animate-pulse">
      <div className="h-[260px] w-full rounded-lg bg-gray-100" />
    </div>
  );
}

function VerificationRowSkeleton() {
  return (
    <div className="flex items-center justify-between py-2 first:pt-0 last:pb-0">
      <div className="h-6 w-24 animate-pulse rounded-full bg-gray-100" />
      <div className="h-5 w-6 animate-pulse rounded bg-gray-100" />
    </div>
  );
}

function ActivityRowSkeleton() {
  return (
    <>
      <div className="h-8 w-8 shrink-0 animate-pulse rounded-full bg-gray-100" />
      <div className="min-w-0 flex-1 space-y-2">
        <div className="h-3.5 w-32 animate-pulse rounded bg-gray-100" />
        <div className="h-3 w-24 animate-pulse rounded bg-gray-100" />
      </div>
      <div className="h-3 w-10 shrink-0 animate-pulse rounded bg-gray-100" />
    </>
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
    <DashboardLayout title="Dashboard">
      <p className="text-sm text-gray-500">An overview of drivers and commuters on Manibela App.</p>

      {error && <p className="mt-6 text-sm font-medium text-brand-red">{error}</p>}

      {!error &&
        (stats ? (
          <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
            <StatCard
              label="Total Drivers"
              value={stats.totalDrivers}
              icon={<DriverIcon />}
              changePercent={stats.totalDriversChangePercent}
            />
            <StatCard
              label="Total Commuters"
              value={stats.totalCommuters}
              icon={<PeopleIcon />}
              changePercent={stats.totalCommutersChangePercent}
            />
            <StatCard label="Active Trips" value={stats.activeTrips} icon={<TripIcon />} tone="good" />
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
            <StatCard
              label="Open Complaints"
              value={stats.openComplaints}
              icon={<ComplaintIcon />}
              tone={stats.openComplaints > 0 ? 'warning' : 'blue'}
            />
          </div>
        ) : (
          <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2 xl:grid-cols-3">
            {Array.from({ length: 6 }).map((_, i) => (
              <StatCardSkeleton key={i} />
            ))}
          </div>
        ))}

      <div className="mt-6 grid grid-cols-1 gap-4 xl:grid-cols-3">
        {/* Trend chart */}
        <Card className="xl:col-span-2">
          <SectionHeader icon={<ChartIcon />} title="Registrations — last 14 days" />
          {trend ? (
            <div className="mt-4">
              <TrendChart series={trend} />
            </div>
          ) : (
            <ChartSkeleton />
          )}
        </Card>

        {/* ID verification summary */}
        <Card>
          <SectionHeader
            icon={<ShieldCheckIcon />}
            title="ID Verification"
            action={
              <Link to="/id-verification" className="text-xs font-semibold text-brand-blue hover:underline">
                View all
              </Link>
            }
          />
          {stats ? (
            <div className="mt-4 divide-y divide-gray-100">
              <div className="flex items-center justify-between py-2 first:pt-0 last:pb-0">
                <VerificationBadge status="PENDING" />
                <span className="font-display text-lg font-semibold text-gray-900">{stats.pendingVerifications}</span>
              </div>
              <div className="flex items-center justify-between py-2 first:pt-0 last:pb-0">
                <VerificationBadge status="APPROVED" />
                <span className="font-display text-lg font-semibold text-gray-900">{stats.approvedVerifications}</span>
              </div>
              <div className="flex items-center justify-between py-2 first:pt-0 last:pb-0">
                <VerificationBadge status="REJECTED" />
                <span className="font-display text-lg font-semibold text-gray-900">{stats.rejectedVerifications}</span>
              </div>
            </div>
          ) : (
            <div className="mt-4 divide-y divide-gray-100">
              {Array.from({ length: 3 }).map((_, i) => (
                <VerificationRowSkeleton key={i} />
              ))}
            </div>
          )}
        </Card>
      </div>

      <div className="mt-6 grid grid-cols-1 gap-4 xl:grid-cols-3">
        {/* Recent activity */}
        <Card className="xl:col-span-2">
          <SectionHeader icon={<PulseIcon />} title="Recent Activity" />
          {!activity && (
            <ul className="mt-3 divide-y divide-gray-100">
              {Array.from({ length: 4 }).map((_, i) => (
                <li key={i} className="flex items-center gap-3 py-2.5">
                  <ActivityRowSkeleton />
                </li>
              ))}
            </ul>
          )}
          {activity && activity.length === 0 && <p className="mt-4 text-sm text-gray-400">No activity yet.</p>}
          {activity && activity.length > 0 && (
            <ul className="mt-3 divide-y divide-gray-100">
              {activity.map((item) => (
                <li key={`${item.type}-${item.id}`} className="flex items-center gap-3 py-2.5">
                  <div
                    className={`flex h-8 w-8 shrink-0 items-center justify-center overflow-hidden rounded-full ${
                      item.type === 'driver' ? 'bg-blue-50' : 'bg-orange-50'
                    }`}
                    style={{ color: item.type === 'driver' ? 'var(--color-series-drivers)' : 'var(--color-series-commuters)' }}
                  >
                    {item.photoUrl ? (
                      <img
                        src={apiClient.resolveUrl(item.photoUrl) ?? undefined}
                        alt=""
                        className="h-full w-full object-cover"
                      />
                    ) : item.type === 'driver' ? (
                      <DriverIcon />
                    ) : (
                      <PeopleIcon />
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
        </Card>

        {/* Quick actions */}
        <Card>
          <SectionHeader icon={<BoltIcon />} title="Quick Actions" />
          <div className="mt-3 flex flex-col gap-2">
            <QuickActionLink
              to="/id-verification"
              icon={<IdCardIcon />}
              label="Review pending ID submissions"
              badge={stats?.pendingVerifications}
            />
            <QuickActionLink to="/drivers" icon={<DriverIcon />} label="Manage drivers" />
            <QuickActionLink to="/commuters" icon={<PeopleIcon />} label="Manage commuters" />
            <QuickActionLink to="/jeepney-monitoring/history" icon={<TripIcon />} label="Review trip history" />
            <QuickActionLink
              to="/incident-reports"
              icon={<ComplaintIcon />}
              label="View incident reports"
              badge={stats?.openComplaints}
            />
          </div>
        </Card>
      </div>
    </DashboardLayout>
  );
}
