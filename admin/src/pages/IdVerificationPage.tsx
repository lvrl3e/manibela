import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { StatCard } from '../components/StatCard';
import { SectionHeader } from '../components/Card';
import { StatCardSkeleton, TableSkeleton } from '../components/Skeleton';
import { PaginationControls } from '../components/PaginationControls';
import { VerificationBadge, type VerificationStatus } from '../components/VerificationBadge';
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
  photoUrl: string | null;
  idSubmitted: boolean;
  verificationStatus: VerificationStatus;
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

interface VerificationStats {
  pendingVerifications: number;
  approvedVerifications: number;
  rejectedVerifications: number;
}

type Filter = 'all' | 'pending' | 'approved' | 'rejected';

const filters: { key: Filter; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'pending', label: 'Pending' },
  { key: 'approved', label: 'Approved' },
  { key: 'rejected', label: 'Rejected' },
];

function SearchIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="11" cy="11" r="7" />
      <path d="m21 21-4-4" />
    </svg>
  );
}

function ClockIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7v5l3.5 2" />
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

function CrossIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <path d="m9 9 6 6m0-6-6 6" />
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

const PAGE_SIZE = 25;

export default function IdVerificationPage() {
  const [filter, setFilter] = useState<Filter>('pending');
  const [search, setSearch] = useState('');
  const debouncedSearch = useDebouncedValue(search, 300);
  const [data, setData] = useState<CommutersResponse | null>(null);
  const [stats, setStats] = useState<VerificationStats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(1);

  function fetchStats() {
    apiClient.get<VerificationStats>('/api/admin/stats').then(setStats).catch(() => {});
  }

  function fetchCommuters() {
    const params = new URLSearchParams({ page: String(page), pageSize: String(PAGE_SIZE), submittedOnly: 'true' });
    if (filter !== 'all') params.set('status', filter);
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
    fetchCommuters();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, debouncedSearch, page]);
  usePolling(fetchCommuters, 8000);

  useEffect(() => {
    setPage(1);
  }, [filter, debouncedSearch]);

  const commuters = data?.commuters ?? [];

  return (
    <DashboardLayout title="ID Verification">
      <p className="text-sm text-gray-500">
        Review government ID and selfie submissions. No automated face-match runs yet — every decision here is manual.
      </p>

      {stats ? (
        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <StatCard label="Pending Review" value={stats.pendingVerifications} icon={<ClockIcon />} tone="warning" />
          <StatCard label="Approved" value={stats.approvedVerifications} icon={<CheckIcon />} tone="good" />
          <StatCard label="Rejected" value={stats.rejectedVerifications} icon={<CrossIcon />} tone="critical" />
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
          icon={<ShieldCheckIcon />}
          title="Submissions"
          action={<p className="text-sm text-gray-500">{data ? `${data.totalCommuters} submission(s)` : ''}</p>}
        />
      </div>

      <div className="mt-3 flex flex-wrap items-center justify-between gap-3 border-b border-gray-200">
        <div className="flex gap-1">
          {filters.map((f) => (
            <button
              key={f.key}
              onClick={() => setFilter(f.key)}
              className={`border-b-2 px-4 py-2.5 text-sm font-semibold transition ${
                filter === f.key
                  ? 'border-brand-blue text-brand-blue'
                  : 'border-transparent text-gray-500 hover:text-gray-700'
              }`}
            >
              {f.label}
            </button>
          ))}
        </div>
        <div className="mb-2 flex items-center gap-2 rounded-lg border border-border-subtle bg-white px-3 py-2 sm:w-64">
          <SearchIcon />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search name, mobile, or ID"
            className="w-full text-sm text-gray-700 focus:outline-none"
          />
        </div>
      </div>

      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}
      {!error && data === null && <TableSkeleton columns={5} />}
      {!error && data !== null && commuters.length === 0 && (
        <p className="mt-4 text-sm text-gray-500">No submissions in this category.</p>
      )}

      {commuters.length > 0 && (
        <div className="mt-4 overflow-x-auto rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
          <table className="w-full min-w-[640px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-5 py-3">Commuter</th>
                <th className="px-5 py-3">Commuter ID</th>
                <th className="px-5 py-3">Mobile Number</th>
                <th className="px-5 py-3">Status</th>
                <th className="px-5 py-3">Submitted</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {commuters.map((commuter) => (
                <tr key={commuter.id} className="transition hover:bg-gray-50">
                  <td className="px-5 py-3">
                    <Link
                      to={`/commuters/${commuter.id}`}
                      className="flex items-center gap-3 font-medium text-gray-900 hover:text-brand-blue"
                    >
                      <div className="h-9 w-9 overflow-hidden rounded-full bg-gray-200">
                        {commuter.photoUrl && (
                          <img
                            src={apiClient.resolveUrl(commuter.photoUrl) ?? undefined}
                            alt=""
                            className="h-full w-full object-cover"
                          />
                        )}
                      </div>
                      {commuter.fullName}
                    </Link>
                  </td>
                  <td className="px-5 py-3 text-gray-600">{commuter.commuterId}</td>
                  <td className="px-5 py-3 text-gray-600">{formatPhone(commuter.mobileNumber)}</td>
                  <td className="px-5 py-3">
                    <VerificationBadge status={commuter.verificationStatus} notSubmitted={!commuter.idSubmitted} />
                  </td>
                  <td className="px-5 py-3 text-gray-600">{formatManilaDate(commuter.createdAt)}</td>
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
    </DashboardLayout>
  );
}
