import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { StatCard } from '../components/StatCard';
import { PaginationControls } from '../components/PaginationControls';
import { ComplaintDetailPanel } from '../components/ComplaintDetailPanel';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { useDebouncedValue } from '../lib/useDebouncedValue';
import { formatManilaDate } from '../lib/formatDate';

type ComplaintStatus = 'PENDING' | 'INVESTIGATING' | 'RESOLVED' | 'REJECTED';

interface ComplaintStats {
  totalComplaints: number;
  pending: number;
  investigating: number;
  resolved: number;
  rejected: number;
  totalComplaintsChangePercent: number | null;
}

interface ComplaintRow {
  id: string;
  complainantName: string;
  driverName: string;
  plateNumber: string;
  complaintType: string;
  status: ComplaintStatus;
  createdAt: string;
}

interface ComplaintsResponse {
  complaints: ComplaintRow[];
  currentPage: number;
  pageSize: number;
  totalComplaints: number;
  totalPages: number;
  hasNextPage: boolean;
}

const FILTERS: { label: string; value: '' | 'pending' | 'investigating' | 'resolved' | 'rejected' }[] = [
  { label: 'All', value: '' },
  { label: 'Pending', value: 'pending' },
  { label: 'Investigating', value: 'investigating' },
  { label: 'Resolved', value: 'resolved' },
  { label: 'Rejected', value: 'rejected' },
];

// Must match COMPLAINT_TYPES in the backend's admin.ts/commuter.ts — what a
// commuter's complaintType is actually restricted to at submission.
const COMPLAINT_TYPES = ['Reckless Driving', 'Overcharging', 'Rude Behavior', 'Route Deviation', 'Other'];

const STATUS_STYLES: Record<ComplaintStatus, string> = {
  PENDING: 'bg-gray-100 text-gray-600',
  INVESTIGATING: 'bg-amber-100 text-amber-700',
  RESOLVED: 'bg-status-good-bg text-status-good',
  REJECTED: 'bg-status-critical-bg text-status-critical',
};

function AlertIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 3.5 2.5 20h19L12 3.5Z" />
      <path d="M12 10v4.5M12 17.5h.01" />
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

function SearchIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="11" cy="11" r="7" />
      <path d="m21 21-4-4" />
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

function EyeIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7-10-7-10-7Z" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}

const PAGE_SIZE = 25;

export default function IncidentReportsPage() {
  const [stats, setStats] = useState<ComplaintStats | null>(null);
  const [data, setData] = useState<ComplaintsResponse | null>(null);
  const [filter, setFilter] = useState<(typeof FILTERS)[number]['value']>('');
  const [typeFilter, setTypeFilter] = useState('');
  const [search, setSearch] = useState('');
  const debouncedSearch = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [searchParams, setSearchParams] = useSearchParams();
  const [selectedComplaintId, setSelectedComplaintId] = useState<string | null>(searchParams.get('complaintId'));

  // Lets a notification (e.g. "New complaint filed") deep-link straight to
  // a complaint's panel via /incident-reports?complaintId=... — read once
  // on mount, same pattern as DriversPage's ?driverId=.
  useEffect(() => {
    const complaintId = searchParams.get('complaintId');
    if (complaintId) {
      setSelectedComplaintId(complaintId);
      searchParams.delete('complaintId');
      setSearchParams(searchParams, { replace: true });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function fetchStats() {
    apiClient.get<ComplaintStats>('/api/admin/complaint-stats').then(setStats).catch(() => {});
  }

  function fetchComplaints() {
    const params = new URLSearchParams({ page: String(page), pageSize: String(PAGE_SIZE) });
    if (filter) params.set('status', filter);
    if (typeFilter) params.set('type', typeFilter);
    if (debouncedSearch.trim()) params.set('search', debouncedSearch.trim());
    apiClient
      .get<ComplaintsResponse>(`/api/admin/complaints?${params.toString()}`)
      .then((res) => {
        setData(res);
        setError(null);
      })
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load complaints.'));
  }

  useEffect(fetchStats, []);
  usePolling(fetchStats, 8000);

  useEffect(() => {
    setIsLoading(true);
    fetchComplaints();
    setIsLoading(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, typeFilter, debouncedSearch, page]);
  usePolling(fetchComplaints, 8000);

  useEffect(() => {
    setPage(1);
  }, [filter, typeFilter, debouncedSearch]);

  const filteredComplaints = data?.complaints ?? [];

  return (
    <DashboardLayout>
      <h1 className="text-2xl font-semibold tracking-tight text-gray-900">Incident Reports</h1>
      <p className="mt-1 text-sm text-gray-500">Complaints filed by commuters against drivers.</p>

      {stats && (
        <div className="mt-6 grid grid-cols-2 gap-4 sm:grid-cols-4">
          <StatCard
            label="Total Complaints"
            value={stats.totalComplaints}
            icon={<AlertIcon />}
            changePercent={stats.totalComplaintsChangePercent}
            changeLabel="vs last month"
          />
          <StatCard label="Pending" value={stats.pending} icon={<ClockIcon />} />
          <StatCard label="Investigating" value={stats.investigating} icon={<SearchIcon />} />
          <StatCard label="Resolved" value={stats.resolved} icon={<CheckIcon />} />
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
        <div className="flex flex-wrap items-center gap-2">
          <select
            value={typeFilter}
            onChange={(e) => setTypeFilter(e.target.value)}
            className="rounded-lg border border-border-subtle bg-white px-3 py-2 text-sm font-semibold text-gray-600 focus:border-brand-blue focus:outline-none"
          >
            <option value="">All Types</option>
            {COMPLAINT_TYPES.map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </select>
          <div className="flex items-center gap-2 rounded-lg border border-border-subtle bg-white px-3 py-2 sm:w-64">
            <SearchIcon />
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search complainant, driver, or plate"
              className="w-full text-sm text-gray-700 focus:outline-none"
            />
          </div>
        </div>
      </div>

      {error && <p className="mt-6 text-sm font-medium text-brand-red">{error}</p>}
      {isLoading && <p className="mt-6 text-sm text-gray-500">Loading...</p>}
      {!isLoading && filteredComplaints.length === 0 && !error && (
        <p className="mt-6 text-sm text-gray-500">No complaints found.</p>
      )}

      {filteredComplaints.length > 0 && (
        <div className="mt-6 overflow-x-auto rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
          <table className="w-full min-w-[840px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-5 py-3">Complainant</th>
                <th className="px-5 py-3">Driver</th>
                <th className="px-5 py-3">Plate Number</th>
                <th className="px-5 py-3">Type</th>
                <th className="px-5 py-3">Status</th>
                <th className="px-5 py-3">Filed</th>
                <th className="px-5 py-3">Actions</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {filteredComplaints.map((c) => (
                <tr key={c.id} className="transition hover:bg-gray-50">
                  <td className="px-5 py-3 font-medium text-gray-900">{c.complainantName}</td>
                  <td className="px-5 py-3 text-gray-600">{c.driverName}</td>
                  <td className="px-5 py-3 text-gray-600">{c.plateNumber}</td>
                  <td className="px-5 py-3 text-gray-600">{c.complaintType}</td>
                  <td className="px-5 py-3">
                    <span
                      className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ${STATUS_STYLES[c.status]}`}
                    >
                      {c.status}
                    </span>
                  </td>
                  <td className="px-5 py-3 text-gray-600">{formatManilaDate(c.createdAt)}</td>
                  <td className="px-5 py-3">
                    <button
                      onClick={() => setSelectedComplaintId(c.id)}
                      className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100 hover:text-brand-blue"
                      aria-label="View complaint"
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

      {selectedComplaintId && (
        <ComplaintDetailPanel
          complaintId={selectedComplaintId}
          onClose={() => setSelectedComplaintId(null)}
          onStatusChange={(status) =>
            setData((prev) =>
              prev
                ? { ...prev, complaints: prev.complaints.map((c) => (c.id === selectedComplaintId ? { ...c, status } : c)) }
                : prev,
            )
          }
        />
      )}
    </DashboardLayout>
  );
}
