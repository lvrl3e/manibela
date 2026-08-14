import { useEffect, useMemo, useState } from 'react';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { formatManilaDate, formatManilaTime, manilaDateRangeForCustom, manilaDateRangeForPreset } from '../lib/formatDate';
import { ShortTripFlagReviewPanel, type FlaggedTripDetail } from './ShortTripFlagReviewPanel';

interface DriverTrip extends FlaggedTripDetail {
  status: 'ACTIVE' | 'COMPLETED';
  isShortTrip: boolean;
}

interface TripsResponse {
  trips: DriverTrip[];
  currentPage: number;
  pageSize: number;
  totalTrips: number;
  totalPages: number;
  hasNextPage: boolean;
  routes: string[];
}

type DatePreset = 'all' | 'today' | 'week' | 'month' | 'custom';
type FlagFilter = 'all' | 'normal' | 'short';

const PAGE_SIZE = 25;

const DATE_PRESETS: { label: string; value: DatePreset }[] = [
  { label: 'All Time', value: 'all' },
  { label: 'Today', value: 'today' },
  { label: 'This Week', value: 'week' },
  { label: 'This Month', value: 'month' },
  { label: 'Custom Date Range', value: 'custom' },
];

const FLAG_FILTERS: { label: string; value: FlagFilter }[] = [
  { label: 'All', value: 'all' },
  { label: 'Normal', value: 'normal' },
  { label: 'Short Trip – Flagged', value: 'short' },
];

/** e.g. "6 min" or "1h 5min" — matches this panel's Trip History table.
 * Null (still-active trip, no endedAt yet) renders as "—". */
function formatTripDuration(startedAt: string, endedAt: string | null): string {
  if (!endedAt) return '—';
  const totalMinutes = Math.max(0, Math.round((new Date(endedAt).getTime() - new Date(startedAt).getTime()) / 60_000));
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return hours > 0 ? `${hours}h ${minutes}min` : `${minutes} min`;
}

/** What the Flag column shows for a flagged trip — the amber "still
 * needs a look" warning only while PENDING; once an admin has acted on
 * it, this shows the actual outcome instead. */
function flagColumnLabel(reviewStatus: DriverTrip['reviewStatus']): { text: string; className: string } {
  switch (reviewStatus) {
    case 'VALID':
      return { text: 'Reviewed – Valid', className: 'text-status-good hover:brightness-90' };
    case 'INVALID':
      return { text: 'Reviewed – Invalid', className: 'text-status-critical hover:brightness-90' };
    case 'REVIEWED':
      return { text: 'Reviewed', className: 'text-brand-blue hover:brightness-90' };
    case 'PENDING':
    default:
      return { text: 'Short Trip – Flagged', className: 'text-amber-600 hover:text-amber-700' };
  }
}

/** Bounded set of page numbers to render around the current page, so a
 * driver with hundreds of pages doesn't get hundreds of buttons — e.g.
 * for page 8 of 20 this renders [6, 7, 8, 9, 10]. */
function pageNumbersAround(current: number, total: number): number[] {
  const span = 2;
  const start = Math.max(1, Math.min(current - span, total - span * 2));
  const end = Math.min(total, Math.max(current + span, span * 2 + 1));
  const pages: number[] = [];
  for (let p = Math.max(1, start); p <= end; p++) pages.push(p);
  return pages;
}

export function DriverTripHistorySection({
  driverId,
  driverName,
  plateNumber,
}: {
  driverId: string;
  driverName: string;
  plateNumber: string;
}) {
  const [data, setData] = useState<TripsResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [page, setPage] = useState(1);
  const [datePreset, setDatePreset] = useState<DatePreset>('all');
  const [customFrom, setCustomFrom] = useState('');
  const [customTo, setCustomTo] = useState('');
  const [routeFilter, setRouteFilter] = useState('');
  const [flagFilter, setFlagFilter] = useState<FlagFilter>('all');
  const [reviewingTripId, setReviewingTripId] = useState<string | null>(null);

  const dateRange = useMemo(() => {
    if (datePreset === 'all') return null;
    if (datePreset === 'custom') {
      if (!customFrom || !customTo) return null;
      return manilaDateRangeForCustom(customFrom, customTo);
    }
    return manilaDateRangeForPreset(datePreset);
  }, [datePreset, customFrom, customTo]);

  function fetchTrips() {
    const params = new URLSearchParams({ page: String(page), pageSize: String(PAGE_SIZE) });
    if (dateRange) {
      params.set('dateFrom', dateRange.from);
      params.set('dateTo', dateRange.to);
    }
    if (routeFilter) params.set('route', routeFilter);
    if (flagFilter !== 'all') params.set('flag', flagFilter);

    apiClient
      .get<TripsResponse>(`/api/admin/drivers/${driverId}/trips?${params.toString()}`)
      .then((res) => {
        setData(res);
        setError(null);
      })
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load trip history.'));
  }

  useEffect(() => {
    setIsLoading(true);
    fetchTrips();
    setIsLoading(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [driverId, page, datePreset, customFrom, customTo, routeFilter, flagFilter]);

  // Keeps the currently-open page/filters live without resetting either —
  // same "make it feel live" pattern as the rest of this admin site, just
  // scoped to whatever page/filter the admin currently has open instead of
  // always re-pulling page 1.
  usePolling(fetchTrips, 8000);

  // Any filter change resets to page 1 — a stale page number past the end
  // of a newly-narrowed result set would otherwise render an empty page
  // that looks like "no trips" even though earlier pages have matches.
  useEffect(() => {
    setPage(1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [driverId, datePreset, customFrom, customTo, routeFilter, flagFilter]);

  const reviewingTrip = data?.trips.find((t) => t.id === reviewingTripId) ?? null;
  const pageNumbers = data ? pageNumbersAround(data.currentPage, data.totalPages) : [];

  return (
    <div>
      <div className="flex items-center justify-between">
        <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Trip History</h3>
        <span className="text-xs text-gray-400">{data ? `${data.totalTrips} trip(s)` : '…'}</span>
      </div>

      <div className="mt-2 flex flex-col gap-1.5">
        <select
          value={datePreset}
          onChange={(e) => setDatePreset(e.target.value as DatePreset)}
          className="rounded-lg border border-border-subtle px-2 py-1.5 text-xs font-semibold text-gray-600 focus:border-brand-blue focus:outline-none"
        >
          {DATE_PRESETS.map((d) => (
            <option key={d.value} value={d.value}>
              {d.label}
            </option>
          ))}
        </select>

        {datePreset === 'custom' && (
          <div className="flex items-center gap-1.5">
            <input
              type="date"
              value={customFrom}
              onChange={(e) => setCustomFrom(e.target.value)}
              className="w-full rounded-lg border border-border-subtle px-2 py-1.5 text-xs text-gray-600 focus:border-brand-blue focus:outline-none"
            />
            <span className="text-xs text-gray-400">to</span>
            <input
              type="date"
              value={customTo}
              onChange={(e) => setCustomTo(e.target.value)}
              className="w-full rounded-lg border border-border-subtle px-2 py-1.5 text-xs text-gray-600 focus:border-brand-blue focus:outline-none"
            />
          </div>
        )}

        <div className="flex gap-1.5">
          <select
            value={routeFilter}
            onChange={(e) => setRouteFilter(e.target.value)}
            className="w-full rounded-lg border border-border-subtle px-2 py-1.5 text-xs font-semibold text-gray-600 focus:border-brand-blue focus:outline-none"
          >
            <option value="">All Routes</option>
            {(data?.routes ?? []).map((r) => (
              <option key={r} value={r}>
                {r}
              </option>
            ))}
          </select>
          <select
            value={flagFilter}
            onChange={(e) => setFlagFilter(e.target.value as FlagFilter)}
            className="w-full rounded-lg border border-border-subtle px-2 py-1.5 text-xs font-semibold text-gray-600 focus:border-brand-blue focus:outline-none"
          >
            {FLAG_FILTERS.map((f) => (
              <option key={f.value} value={f.value}>
                {f.label}
              </option>
            ))}
          </select>
        </div>
      </div>

      {error && <p className="mt-2 text-xs font-medium text-brand-red">{error}</p>}
      {isLoading && !data && <p className="mt-2 text-sm text-gray-400">Loading...</p>}
      {!isLoading && data && data.trips.length === 0 && !error && (
        <p className="mt-2 text-sm text-gray-400">No trips match these filters.</p>
      )}

      {data && data.trips.length > 0 && (
        <>
          <div className="mt-2 max-h-72 overflow-auto rounded-lg border border-border-subtle">
            <table className="w-full min-w-[520px] text-left text-xs">
              <thead className="sticky top-0 bg-gray-50 font-semibold uppercase tracking-wide text-gray-500">
                <tr>
                  <th className="px-3 py-2">Route</th>
                  <th className="px-3 py-2">Trip Date</th>
                  <th className="px-3 py-2">Start Time</th>
                  <th className="px-3 py-2">End Time</th>
                  <th className="px-3 py-2">Duration</th>
                  <th className="px-3 py-2">Flag</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {data.trips.map((t) => (
                  <tr key={t.id}>
                    <td className="px-3 py-2 font-medium text-gray-900">{t.route ?? 'No route set'}</td>
                    <td className="px-3 py-2 text-gray-600">{formatManilaDate(t.startedAt)}</td>
                    <td className="px-3 py-2 text-gray-600">{formatManilaTime(t.startedAt)}</td>
                    <td className="px-3 py-2 text-gray-600">{t.endedAt ? formatManilaTime(t.endedAt) : '—'}</td>
                    <td className="px-3 py-2 text-gray-600">{formatTripDuration(t.startedAt, t.endedAt)}</td>
                    <td className="px-3 py-2">
                      {t.isShortTrip ? (
                        <button
                          onClick={() => setReviewingTripId(t.id)}
                          className={`font-semibold underline decoration-dotted ${flagColumnLabel(t.reviewStatus).className}`}
                        >
                          {flagColumnLabel(t.reviewStatus).text}
                        </button>
                      ) : (
                        <span className="text-gray-300">—</span>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          {data.totalPages > 1 && (
            <div className="mt-2 flex flex-wrap items-center justify-center gap-1">
              <button
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={data.currentPage <= 1}
                className="rounded-lg border border-border-subtle px-2 py-1 text-xs font-semibold text-gray-600 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50"
              >
                Previous
              </button>
              {pageNumbers.map((p) => (
                <button
                  key={p}
                  onClick={() => setPage(p)}
                  className={`rounded-lg px-2.5 py-1 text-xs font-semibold ${
                    p === data.currentPage ? 'bg-brand-blue text-white' : 'text-gray-600 hover:bg-gray-100'
                  }`}
                >
                  {p}
                </button>
              ))}
              <button
                onClick={() => setPage((p) => (data.hasNextPage ? p + 1 : p))}
                disabled={!data.hasNextPage}
                className="rounded-lg border border-border-subtle px-2 py-1 text-xs font-semibold text-gray-600 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50"
              >
                Next
              </button>
            </div>
          )}
        </>
      )}

      {reviewingTrip && (
        <ShortTripFlagReviewPanel
          trip={reviewingTrip}
          driverName={driverName}
          plateNumber={plateNumber}
          onClose={() => setReviewingTripId(null)}
          onReviewed={(result) =>
            setData((prev) =>
              prev
                ? { ...prev, trips: prev.trips.map((t) => (t.id === reviewingTripId ? { ...t, ...result } : t)) }
                : prev,
            )
          }
        />
      )}
    </div>
  );
}
