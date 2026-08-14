import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { PaginationControls } from '../components/PaginationControls';
import { VerificationBadge, type VerificationStatus } from '../components/VerificationBadge';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { useDebouncedValue } from '../lib/useDebouncedValue';
import { formatManilaDate } from '../lib/formatDate';

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

const PAGE_SIZE = 25;

export default function IdVerificationPage() {
  const [filter, setFilter] = useState<Filter>('pending');
  const [search, setSearch] = useState('');
  const debouncedSearch = useDebouncedValue(search, 300);
  const [data, setData] = useState<CommutersResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [page, setPage] = useState(1);

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

  useEffect(() => {
    setIsLoading(true);
    fetchCommuters();
    setIsLoading(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, debouncedSearch, page]);
  usePolling(fetchCommuters, 8000);

  useEffect(() => {
    setPage(1);
  }, [filter, debouncedSearch]);

  const commuters = data?.commuters ?? [];

  return (
    <DashboardLayout>
      <h1 className="text-2xl font-semibold tracking-tight text-gray-900">ID Verification</h1>
      <p className="mt-1 text-sm text-gray-500">
        Review government ID and selfie submissions. No automated face-match runs yet — every decision here is manual.
      </p>

      <div className="mt-5 flex flex-wrap items-center justify-between gap-3 border-b border-gray-200">
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

      {error && <p className="mt-6 text-sm font-medium text-brand-red">{error}</p>}
      {isLoading && <p className="mt-6 text-sm text-gray-500">Loading...</p>}
      {!isLoading && commuters.length === 0 && !error && (
        <p className="mt-6 text-sm text-gray-500">No submissions in this category.</p>
      )}

      {commuters.length > 0 && (
        <div className="mt-6 overflow-x-auto rounded-xl border border-border-subtle bg-surface-card">
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
                  <td className="px-5 py-3 text-gray-600">{commuter.mobileNumber}</td>
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
