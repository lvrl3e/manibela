import { useEffect, useState } from 'react';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { formatManilaTime, manilaDateRangeForPreset } from '../lib/formatDate';

interface TripRow {
  id: string;
  route: string | null;
  status: 'ACTIVE' | 'COMPLETED';
  startedAt: string;
  endedAt: string | null;
}

function CloseIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M5 5l14 14M19 5 5 19" />
    </svg>
  );
}

function durationLabel(startedAt: string, endedAt: string): string {
  const ms = new Date(endedAt).getTime() - new Date(startedAt).getTime();
  const minutes = Math.max(0, Math.round(ms / 60_000));
  const hours = Math.floor(minutes / 60);
  const mins = minutes % 60;
  return hours > 0 ? `${hours}h ${mins}m` : `${mins} min`;
}

/** A quick "what has this jeepney done today" view opened from Jeepney
 * Monitoring's "View Trips" — deliberately not a full history browser
 * (no pagination, no flag/review detail): that's what Drivers → Driver
 * Detail Panel → Trip History is for. Uses the same paginated
 * GET /api/admin/drivers/:id/trips the detail panel's Trip History table
 * calls, scoped to today's Manila calendar date via dateFrom/dateTo. */
export function JeepneyTripsPanel({
  driverId,
  driverName,
  plateNumber,
  onClose,
}: {
  driverId: string;
  driverName: string;
  plateNumber: string;
  onClose: () => void;
}) {
  const [trips, setTrips] = useState<TripRow[] | null>(null);
  const [error, setError] = useState<string | null>(null);

  function fetchTrips() {
    const { from, to } = manilaDateRangeForPreset('today');
    const params = new URLSearchParams({ pageSize: '100', dateFrom: from, dateTo: to });
    apiClient
      .get<{ trips: TripRow[] }>(`/api/admin/drivers/${driverId}/trips?${params.toString()}`)
      .then((res) => setTrips(res.trips))
      .catch((err) => setError(err instanceof ApiError ? err.message : "Could not load this jeepney's trips."));
  }

  useEffect(fetchTrips, [driverId]);
  usePolling(fetchTrips, 8000);

  // Numbered in the order they happened (Trip #1 = the day's first),
  // then rendered most-recent-first — matches how a driver would
  // actually recall "my third trip today", read top to bottom.
  const numbered = trips
    ? [...trips].sort((a, b) => new Date(a.startedAt).getTime() - new Date(b.startedAt).getTime()).map((t, i) => ({ ...t, number: i + 1 }))
    : [];
  const displayOrder = [...numbered].reverse();

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative flex h-full w-full max-w-md flex-col overflow-y-auto bg-white shadow-xl">
        <div className="flex items-center justify-between border-b border-border-subtle px-5 py-4">
          <div>
            <h2 className="text-sm font-semibold text-gray-900">Today's Trips</h2>
            <p className="text-xs text-gray-500">
              {plateNumber} · {driverName}
            </p>
          </div>
          <button onClick={onClose} className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100" aria-label="Close">
            <CloseIcon />
          </button>
        </div>

        {error && <p className="p-5 text-sm font-medium text-brand-red">{error}</p>}
        {!trips && !error && <p className="p-5 text-sm text-gray-500">Loading...</p>}
        {trips && trips.length === 0 && !error && (
          <p className="p-5 text-sm text-gray-400">No trips for this jeepney today yet.</p>
        )}

        {displayOrder.length > 0 && (
          <div className="flex flex-col gap-3 p-5">
            {displayOrder.map((t) => (
              <div key={t.id} className="rounded-xl border border-border-subtle p-4">
                <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">
                  Trip #{String(t.number).padStart(3, '0')}
                </p>
                <p className="mt-1 text-sm font-semibold text-gray-900">{t.route ?? 'No route set'}</p>
                <p className="mt-1 text-sm text-gray-600">
                  {formatManilaTime(t.startedAt)}
                  {' → '}
                  {t.status === 'ACTIVE' ? (
                    <span className="font-semibold text-status-good">Currently Active</span>
                  ) : (
                    formatManilaTime(t.endedAt!)
                  )}
                </p>
                {t.status === 'COMPLETED' && t.endedAt && (
                  <p className="mt-0.5 text-xs text-gray-400">Duration: {durationLabel(t.startedAt, t.endedAt)}</p>
                )}
              </div>
            ))}
          </div>
        )}

        <p className="mt-auto border-t border-border-subtle px-5 py-3 text-xs text-gray-400">
          Showing today only. For this jeepney's complete trip history, open Drivers → {driverName} → Trip History.
        </p>
      </div>
    </div>
  );
}
