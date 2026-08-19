import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { ShortTripFlagReviewPanel, type FlaggedTripDetail } from '../components/ShortTripFlagReviewPanel';
import { ConfirmDialog } from '../components/ConfirmDialog';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { formatManilaDateTime } from '../lib/formatDate';

interface TripRow extends FlaggedTripDetail {
  driverName: string;
  plateNumber: string;
  status: 'ACTIVE' | 'COMPLETED';
  isShortTrip: boolean;
}

interface TripsResponse {
  trips: TripRow[];
  total: number;
  page: number;
  pageSize: number;
}

const FILTERS: { label: string; value: '' | 'active' | 'completed' }[] = [
  { label: 'All', value: '' },
  { label: 'Online', value: 'active' },
  { label: 'Offline', value: 'completed' },
];

function BackIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M15 19l-7-7 7-7" />
    </svg>
  );
}

function StatusBadge({ online }: { online: boolean }) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ${
        online ? 'bg-status-good-bg text-status-good' : 'bg-gray-100 text-gray-500'
      }`}
    >
      {online ? 'Online' : 'Offline'}
    </span>
  );
}

function FlagIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M5 21V4" />
      <path d="M5 4.5c1.5-1 3.5-1 5 0s3.5 1 5 0v9c-1.5 1-3.5 1-5 0s-3.5-1-5 0" />
    </svg>
  );
}

function UndoIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M4 10h9a6 6 0 0 1 0 12h-2" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M8 5 4 10l4 5" strokeLinecap="round" strokeLinejoin="round" />
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

function tripDurationMs(t: TripRow): number | null {
  if (!t.endedAt) return null;
  return new Date(t.endedAt).getTime() - new Date(t.startedAt).getTime();
}

function formatDurationMs(ms: number): string {
  const totalMinutes = Math.floor(ms / 60_000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  return hours > 0 ? `${hours}h ${minutes}m` : `${minutes}m`;
}

export default function TripHistoryPage() {
  const [data, setData] = useState<TripsResponse | null>(null);
  const [filter, setFilter] = useState<(typeof FILTERS)[number]['value']>('');
  const [page, setPage] = useState(1);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [actingId, setActingId] = useState<string | null>(null);
  const [reviewingTripId, setReviewingTripId] = useState<string | null>(null);
  const [confirmingFlagTrip, setConfirmingFlagTrip] = useState<TripRow | null>(null);
  const [confirmingUnflagTrip, setConfirmingUnflagTrip] = useState<TripRow | null>(null);

  function fetchTrips() {
    const params = new URLSearchParams({ page: String(page), pageSize: '25' });
    if (filter) params.set('status', filter);
    apiClient
      .get<TripsResponse>(`/api/admin/trips?${params.toString()}`)
      .then(setData)
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load trips.'));
  }

  useEffect(() => {
    setIsLoading(true);
    fetchTrips();
    setIsLoading(false);
  }, [filter, page]);
  usePolling(fetchTrips, 8000);

  useEffect(() => {
    setPage(1);
  }, [filter]);

  async function handleConfirmFlag() {
    const trip = confirmingFlagTrip;
    if (!trip) return;
    setActingId(trip.id);
    try {
      await apiClient.patch(`/api/admin/trips/${trip.id}/flag`, {});
      fetchTrips();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Could not flag trip.');
    } finally {
      setActingId(null);
      setConfirmingFlagTrip(null);
    }
  }

  async function handleConfirmUnflag() {
    const trip = confirmingUnflagTrip;
    if (!trip) return;
    setActingId(trip.id);
    try {
      await apiClient.delete(`/api/admin/trips/${trip.id}/flag`);
      fetchTrips();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Could not undo the flag.');
    } finally {
      setActingId(null);
      setConfirmingUnflagTrip(null);
    }
  }

  const reviewingTrip = data?.trips.find((t) => t.id === reviewingTripId) ?? null;

  const totalPages = data ? Math.max(1, Math.ceil(data.total / data.pageSize)) : 1;

  return (
    <DashboardLayout title="Trip History">
      <Link
        to="/jeepney-monitoring"
        className="flex w-fit items-center gap-1.5 text-sm font-semibold text-brand-blue hover:underline"
      >
        <BackIcon />
        Back to Jeepney Monitoring
      </Link>

      <div className="mt-4 flex flex-wrap items-center justify-between gap-3">
        <div>
          <p className="text-sm text-gray-500">Every trip a driver has started, online or completed.</p>
        </div>
      </div>

      <div className="mt-6 flex flex-wrap gap-2">
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

      {error && <p className="mt-6 text-sm font-medium text-brand-red">{error}</p>}
      {isLoading && <p className="mt-6 text-sm text-gray-500">Loading...</p>}
      {!isLoading && data && data.trips.length === 0 && !error && (
        <p className="mt-6 text-sm text-gray-500">No trips found.</p>
      )}

      {data && data.trips.length > 0 && (
        <>
          <div className="mt-6 overflow-x-auto rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
            <table className="w-full min-w-[880px] text-left text-sm">
              <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
                <tr>
                  <th className="px-5 py-3">Plate Number</th>
                  <th className="px-5 py-3">Driver</th>
                  <th className="px-5 py-3">Route</th>
                  <th className="px-5 py-3">Status</th>
                  <th className="px-5 py-3">Start Trip</th>
                  <th className="px-5 py-3">End Trip</th>
                  <th className="px-5 py-3">Duration</th>
                  <th className="px-5 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-100">
                {data.trips.map((t) => {
                  const durationMs = tripDurationMs(t);
                  return (
                    <tr key={t.id} className="transition hover:bg-gray-50">
                      <td className="px-5 py-3 font-medium text-gray-900">{t.plateNumber}</td>
                      <td className="px-5 py-3 text-gray-600">{t.driverName}</td>
                      <td className="px-5 py-3 text-gray-600">{t.route ?? '—'}</td>
                      <td className="px-5 py-3">
                        <StatusBadge online={t.status === 'ACTIVE'} />
                      </td>
                      <td className="px-5 py-3 text-gray-600">{formatManilaDateTime(t.startedAt)}</td>
                      <td className="px-5 py-3 text-gray-600">{t.endedAt ? formatManilaDateTime(t.endedAt) : '—'}</td>
                      <td className="px-5 py-3 text-gray-600">
                        <div className="flex items-center gap-2">
                          {durationMs !== null ? formatDurationMs(durationMs) : '—'}
                          {t.isShortTrip && (
                            <span className="inline-flex items-center rounded-full border border-amber-200 bg-amber-50 px-2 py-0.5 text-[11px] font-semibold text-amber-700">
                              Short Trip – Flagged
                            </span>
                          )}
                        </div>
                      </td>
                      <td className="px-5 py-3">
                        {t.isShortTrip ? (
                          <div className="flex flex-wrap gap-2">
                            <button
                              onClick={() => setReviewingTripId(t.id)}
                              className="flex items-center gap-1.5 rounded-lg border border-border-subtle px-2.5 py-1.5 text-xs font-semibold text-gray-600 hover:bg-gray-50 hover:text-brand-blue"
                            >
                              <EyeIcon />
                              Review
                            </button>
                            {t.flagReason === 'Flagged by admin for review.' && t.reviewStatus === 'PENDING' && (
                              <button
                                onClick={() => setConfirmingUnflagTrip(t)}
                                disabled={actingId === t.id}
                                title="Undo this flag"
                                className="flex items-center gap-1.5 rounded-lg border border-border-subtle px-2.5 py-1.5 text-xs font-semibold text-gray-600 hover:bg-gray-50 hover:text-gray-900 disabled:cursor-not-allowed disabled:opacity-50"
                              >
                                <UndoIcon />
                                Unflag
                              </button>
                            )}
                          </div>
                        ) : t.status === 'COMPLETED' ? (
                          <button
                            onClick={() => setConfirmingFlagTrip(t)}
                            disabled={actingId === t.id}
                            title="Flag this trip for review"
                            className="flex items-center gap-1.5 rounded-lg border border-border-subtle px-2.5 py-1.5 text-xs font-semibold text-gray-600 hover:bg-gray-50 hover:text-amber-700 disabled:cursor-not-allowed disabled:opacity-50"
                          >
                            <FlagIcon />
                            Flag
                          </button>
                        ) : (
                          <span
                            title="Trip is still in progress — it can be flagged once it ends"
                            className="text-xs text-gray-300"
                          >
                            —
                          </span>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>

          <div className="mt-4 flex items-center justify-between">
            <p className="text-sm text-gray-500">
              Page {data.page} of {totalPages} · {data.total} trip(s) total
            </p>
            <div className="flex gap-2">
              <button
                onClick={() => setPage((p) => Math.max(1, p - 1))}
                disabled={data.page <= 1}
                className="rounded-lg border border-border-subtle px-3.5 py-2 text-sm font-semibold text-gray-600 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50"
              >
                Previous
              </button>
              <button
                onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
                disabled={data.page >= totalPages}
                className="rounded-lg border border-border-subtle px-3.5 py-2 text-sm font-semibold text-gray-600 hover:bg-gray-50 disabled:cursor-not-allowed disabled:opacity-50"
              >
                Next
              </button>
            </div>
          </div>
        </>
      )}

      {reviewingTrip && (
        <ShortTripFlagReviewPanel
          trip={reviewingTrip}
          driverName={reviewingTrip.driverName}
          plateNumber={reviewingTrip.plateNumber}
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

      {confirmingFlagTrip && (
        <ConfirmDialog
          icon={<FlagIcon />}
          title="Flag this trip?"
          message={`${confirmingFlagTrip.plateNumber}, ${confirmingFlagTrip.driverName} — the driver will be notified and asked to explain what happened.`}
          confirmLabel="Flag"
          tone="warning"
          isSubmitting={actingId === confirmingFlagTrip.id}
          onCancel={() => setConfirmingFlagTrip(null)}
          onConfirm={handleConfirmFlag}
        />
      )}

      {confirmingUnflagTrip && (
        <ConfirmDialog
          icon={<UndoIcon />}
          title="Undo this flag?"
          message={`${confirmingUnflagTrip.plateNumber}, ${confirmingUnflagTrip.driverName} — the driver will be notified that no explanation is needed.`}
          confirmLabel="Unflag"
          tone="neutral"
          isSubmitting={actingId === confirmingUnflagTrip.id}
          onCancel={() => setConfirmingUnflagTrip(null)}
          onConfirm={handleConfirmUnflag}
        />
      )}
    </DashboardLayout>
  );
}
