import { useEffect, useState } from 'react';
import { DashboardLayout } from '../components/DashboardLayout';
import { StatCard } from '../components/StatCard';
import { PaginationControls } from '../components/PaginationControls';
import { VerificationBadge, type VerificationStatus } from '../components/VerificationBadge';
import { CommuterDetailPanel } from '../components/CommuterDetailPanel';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { useDebouncedValue } from '../lib/useDebouncedValue';
import { formatManilaDate } from '../lib/formatDate';
import { formatPhone } from '../lib/formatPhone';

interface Commuter {
  id: string;
  commuterId: string;
  fullName: string;
  mobileNumber: string;
  dateOfBirth: string | null;
  photoUrl: string | null;
  phoneVerified: boolean;
  idSubmitted: boolean;
  verificationStatus: VerificationStatus;
  isActive: boolean;
  createdAt: string;
}

interface CommutersResponse {
  commuters: Commuter[];
  currentPage: number;
  pageSize: number;
  totalCommuters: number;
  totalPages: number;
  hasNextPage: boolean;
}

interface CommuterStats {
  totalCommuters: number;
  activeCommuters: number;
  inactiveCommuters: number;
  totalCommutersChangePercent: number | null;
}

function PhoneBadge({ verified }: { verified: boolean }) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ${
        verified ? 'bg-status-good-bg text-status-good' : 'bg-gray-100 text-gray-500'
      }`}
    >
      {verified ? 'Verified' : 'Unverified'}
    </span>
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

function WarningIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 3.5 2.5 20h19L12 3.5Z" />
      <path d="M12 10v4.5M12 17.5h.01" />
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

function EyeIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7-10-7-10-7Z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

const FILTERS: { label: string; value: 'all' | 'active' | 'inactive' }[] = [
  { label: 'All', value: 'all' },
  { label: 'Active', value: 'active' },
  { label: 'Inactive', value: 'inactive' },
];

const PAGE_SIZE = 25;

export default function CommutersPage() {
  const [data, setData] = useState<CommutersResponse | null>(null);
  const [stats, setStats] = useState<CommuterStats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [filter, setFilter] = useState<(typeof FILTERS)[number]['value']>('all');
  const [search, setSearch] = useState('');
  const debouncedSearch = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [selectedCommuterId, setSelectedCommuterId] = useState<string | null>(null);

  function fetchStats() {
    apiClient.get<CommuterStats>('/api/admin/commuter-stats').then(setStats).catch(() => {});
  }

  function fetchCommuters() {
    const params = new URLSearchParams({ page: String(page), pageSize: String(PAGE_SIZE) });
    if (filter !== 'all') params.set('accountStatus', filter);
    if (debouncedSearch.trim()) params.set('search', debouncedSearch.trim());
    apiClient
      .get<CommutersResponse>(`/api/admin/commuters?${params.toString()}`)
      .then((res) => {
        setData(res);
        setError(null);
      })
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load commuters.'));
  }

  useEffect(fetchStats, []);
  usePolling(fetchStats, 8000);

  useEffect(() => {
    setIsLoading(true);
    fetchCommuters();
    setIsLoading(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, debouncedSearch, page]);
  usePolling(fetchCommuters, 8000);

  // Any filter/search change resets to page 1 — a stale page number past
  // the end of a newly-narrowed result set would otherwise render an
  // empty page that looks like "no commuters" even though earlier pages
  // have matches.
  useEffect(() => {
    setPage(1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, debouncedSearch]);

  const commuters = data?.commuters ?? [];

  return (
    <DashboardLayout>
      <h1 className="text-2xl font-semibold tracking-tight text-gray-900">Commuters</h1>
      <p className="mt-1 text-sm text-gray-500">{data ? `${data.totalCommuters} account(s)` : '…'}</p>

      {stats && (
        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <StatCard
            label="Total Commuters"
            value={stats.totalCommuters}
            icon={<PeopleIcon />}
            changePercent={stats.totalCommutersChangePercent}
            changeLabel="vs last month"
          />
          <StatCard label="Active Commuters" value={stats.activeCommuters} icon={<CheckIcon />} />
          <StatCard label="Inactive Commuters" value={stats.inactiveCommuters} icon={<WarningIcon />} />
        </div>
      )}

      <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap gap-2">
          {FILTERS.map((f) => (
            <button
              key={f.value}
              onClick={() => setFilter(f.value)}
              className={`rounded-lg px-3.5 py-2 text-sm font-semibold transition ${
                filter === f.value ? 'bg-brand-blue text-white' : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
        <div className="flex items-center gap-2 rounded-lg border border-border-subtle bg-white px-3 py-2 sm:w-72">
          <SearchIcon />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search name, mobile, or ID"
            className="w-full text-sm text-gray-700 focus:outline-none"
          />
        </div>
      </div>

      {error && <p className="mt-6 text-sm font-medium text-brand-red">{error}</p>}
      {isLoading && <p className="mt-6 text-sm text-gray-500">Loading...</p>}
      {!isLoading && commuters.length === 0 && !error && (
        <p className="mt-6 text-sm text-gray-500">No commuters in this category.</p>
      )}

      {commuters.length > 0 && (
        <div className="mt-6 overflow-x-auto rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
          <table className="w-full min-w-[760px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-5 py-3">Commuter</th>
                <th className="px-5 py-3">Commuter ID</th>
                <th className="px-5 py-3">Mobile Number</th>
                <th className="px-5 py-3">Phone</th>
                <th className="px-5 py-3">ID / KYC</th>
                <th className="px-5 py-3">Account</th>
                <th className="px-5 py-3">Joined</th>
                <th className="px-5 py-3">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {commuters.map((commuter) => (
                <tr key={commuter.id} className="transition hover:bg-gray-50">
                  <td className="px-5 py-3">
                    <div className="flex items-center gap-3">
                      <div className="h-9 w-9 shrink-0 overflow-hidden rounded-full bg-gray-200">
                        {commuter.photoUrl && (
                          <img
                            src={apiClient.resolveUrl(commuter.photoUrl) ?? undefined}
                            alt=""
                            className="h-full w-full object-cover"
                          />
                        )}
                      </div>
                      <span className="font-medium text-gray-900">{commuter.fullName}</span>
                    </div>
                  </td>
                  <td className="px-5 py-3 text-gray-600">{commuter.commuterId}</td>
                  <td className="px-5 py-3 text-gray-600">{formatPhone(commuter.mobileNumber)}</td>
                  <td className="px-5 py-3">
                    <PhoneBadge verified={commuter.phoneVerified} />
                  </td>
                  <td className="px-5 py-3">
                    <VerificationBadge status={commuter.verificationStatus} notSubmitted={!commuter.idSubmitted} />
                  </td>
                  <td className="px-5 py-3">
                    <span
                      className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ${
                        commuter.isActive ? 'bg-status-good-bg text-status-good' : 'bg-status-critical-bg text-status-critical'
                      }`}
                    >
                      {commuter.isActive ? 'Active' : 'Inactive'}
                    </span>
                  </td>
                  <td className="px-5 py-3 text-gray-600">{formatManilaDate(commuter.createdAt)}</td>
                  <td className="px-5 py-3">
                    <button
                      onClick={() => setSelectedCommuterId(commuter.id)}
                      className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100 hover:text-brand-blue"
                      aria-label="View commuter"
                    >
                      <EyeIcon />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {data && (
        <PaginationControls
          currentPage={data.currentPage}
          totalPages={data.totalPages}
          hasNextPage={data.hasNextPage}
          onPageChange={setPage}
        />
      )}

      {selectedCommuterId && (
        <CommuterDetailPanel
          commuterId={selectedCommuterId}
          onClose={() => setSelectedCommuterId(null)}
          onStatusChange={(isActive) =>
            setData((prev) =>
              prev
                ? { ...prev, commuters: prev.commuters.map((c) => (c.id === selectedCommuterId ? { ...c, isActive } : c)) }
                : prev,
            )
          }
        />
      )}
    </DashboardLayout>
  );
}
