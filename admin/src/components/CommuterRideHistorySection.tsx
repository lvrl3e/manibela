import { useEffect, useState } from 'react';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { formatManilaDateTime } from '../lib/formatDate';
import { PaginationControls } from './PaginationControls';

interface RideHistoryRow {
  id: string;
  driverName: string;
  plateNumber: string;
  route: string | null;
  boardedAt: string;
  alightedAt: string | null;
}

interface RideHistoryResponse {
  rideHistory: RideHistoryRow[];
  currentPage: number;
  pageSize: number;
  totalRides: number;
  totalPages: number;
  hasNextPage: boolean;
}

const PAGE_SIZE = 25;

/** Paginated ride history for one commuter — used by both the Commuter
 * Detail Panel (compact list, narrow sidebar) and the full Commuter
 * Detail Page (table). Split into its own fetch/component the same way
 * DriverTripHistorySection is: was previously embedded in GET
 * /commuters/:id with a fixed take: 30 and no paging. */
export function CommuterRideHistorySection({ commuterId, compact = false }: { commuterId: string; compact?: boolean }) {
  const [data, setData] = useState<RideHistoryResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [page, setPage] = useState(1);

  function fetchRides() {
    apiClient
      .get<RideHistoryResponse>(`/api/admin/commuters/${commuterId}/trips?page=${page}&pageSize=${PAGE_SIZE}`)
      .then((res) => {
        setData(res);
        setError(null);
      })
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load ride history.'));
  }

  useEffect(() => {
    fetchRides();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [commuterId, page]);
  usePolling(fetchRides, 8000);

  useEffect(() => {
    setPage(1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [commuterId]);

  const rides = data?.rideHistory ?? [];

  if (compact) {
    return (
      <div>
        <div className="flex items-center justify-between">
          <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Ride History</h3>
          <span className="text-xs text-gray-400">{data ? `${data.totalRides} ride(s)` : '…'}</span>
        </div>
        {error && <p className="mt-2 text-xs font-medium text-brand-red">{error}</p>}
        {!data && !error && <p className="mt-2 text-sm text-gray-400">Loading...</p>}
        {data && rides.length === 0 && !error && <p className="mt-2 text-sm text-gray-400">No rides recorded yet.</p>}
        {rides.length > 0 && (
          <ul className="mt-2 max-h-56 divide-y divide-gray-100 overflow-y-auto">
            {rides.map((r) => (
              <li key={r.id} className="py-2 text-sm">
                <div className="flex items-center justify-between">
                  <span className="font-medium text-gray-900">{r.driverName}</span>
                  <span className="text-xs text-gray-500">{r.plateNumber}</span>
                </div>
                <p className="text-xs text-gray-500">
                  {r.route ?? 'No route set'} · {formatManilaDateTime(r.boardedAt)}
                </p>
              </li>
            ))}
          </ul>
        )}
        {data && (
          <PaginationControls
            currentPage={data.currentPage}
            totalPages={data.totalPages}
            hasNextPage={data.hasNextPage}
            onPageChange={setPage}
          />
        )}
      </div>
    );
  }

  return (
    <div className="mt-8">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-gray-900">Ride History</h2>
        <span className="text-xs text-gray-400">{data ? `${data.totalRides} ride(s)` : '…'}</span>
      </div>
      <p className="mt-1 text-sm text-gray-500">Recorded whenever this commuter scans a driver's QR code while boarding.</p>

      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}
      {!data && !error && <p className="mt-4 text-sm text-gray-400">Loading...</p>}
      {data && rides.length === 0 && !error && <p className="mt-4 text-sm text-gray-400">No rides recorded yet.</p>}

      {rides.length > 0 && (
        <div className="mt-4 overflow-x-auto rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
          <table className="w-full min-w-[560px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-5 py-3">Driver</th>
                <th className="px-5 py-3">Plate Number</th>
                <th className="px-5 py-3">Route</th>
                <th className="px-5 py-3">Boarded</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {rides.map((r) => (
                <tr key={r.id} className="transition hover:bg-gray-50">
                  <td className="px-5 py-3 font-medium text-gray-900">{r.driverName}</td>
                  <td className="px-5 py-3 text-gray-600">{r.plateNumber}</td>
                  <td className="px-5 py-3 text-gray-600">{r.route ?? '—'}</td>
                  <td className="px-5 py-3 text-gray-600">{formatManilaDateTime(r.boardedAt)}</td>
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
    </div>
  );
}
