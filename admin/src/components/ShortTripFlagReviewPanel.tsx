import { useState } from 'react';
import { apiClient, ApiError } from '../lib/apiClient';
import { useAuth } from '../lib/auth';
import { formatManilaDateTime } from '../lib/formatDate';

export type ReviewStatus = 'PENDING' | 'REVIEWED' | 'VALID' | 'INVALID';

export interface FlaggedTripDetail {
  id: string;
  route: string | null;
  startedAt: string;
  endedAt: string | null;
  flagReason: string | null;
  driverExplanation: string | null;
  explanationSubmittedAt: string | null;
  reviewStatus: ReviewStatus;
  reviewedAt: string | null;
  reviewedByName: string | null;
  adminReviewNote: string | null;
}

function CloseIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M5 5l14 14M19 5 5 19" />
    </svg>
  );
}

const REVIEW_STATUS_STYLES: Record<ReviewStatus, string> = {
  PENDING: 'bg-gray-100 text-gray-600',
  REVIEWED: 'bg-brand-blue/10 text-brand-blue',
  VALID: 'bg-status-good-bg text-status-good',
  INVALID: 'bg-status-critical-bg text-status-critical',
};

const REVIEW_STATUS_LABELS: Record<ReviewStatus, string> = {
  PENDING: 'Pending Review',
  REVIEWED: 'Reviewed',
  VALID: 'Valid',
  INVALID: 'Invalid',
};

function durationLabel(startedAt: string, endedAt: string | null): string {
  if (!endedAt) return '—';
  const ms = new Date(endedAt).getTime() - new Date(startedAt).getTime();
  const totalMinutes = Math.floor(ms / 60_000);
  const hours = Math.floor(totalMinutes / 60);
  const minutes = totalMinutes % 60;
  const seconds = Math.floor((ms % 60_000) / 1000);
  if (hours > 0) return `${hours}h ${minutes}m`;
  return `${minutes}m ${seconds}s`;
}

/** Opened from the Driver Detail Panel's Trip History table by clicking a
 * "Short Trip – Flagged" row — that table (see GET /api/admin/drivers/:id)
 * already carries every field this panel needs, so unlike a standalone
 * list page, this never fetches on its own; it just reviews the trip
 * object it's handed and reports the result back up. */
export function ShortTripFlagReviewPanel({
  trip,
  driverName,
  plateNumber,
  onClose,
  onReviewed,
}: {
  trip: FlaggedTripDetail;
  driverName: string;
  plateNumber: string;
  onClose: () => void;
  onReviewed: (result: { reviewStatus: ReviewStatus; reviewedAt: string; adminReviewNote: string | null; reviewedByName: string }) => void;
}) {
  const { admin } = useAuth();
  const [error, setError] = useState<string | null>(null);
  const [note, setNote] = useState(trip.adminReviewNote ?? '');
  const [noteError, setNoteError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [saved, setSaved] = useState<{
    reviewStatus: ReviewStatus;
    reviewedAt: string;
    adminReviewNote: string | null;
    reviewedByName: string;
  } | null>(null);

  async function handleReview(status: 'REVIEWED' | 'VALID' | 'INVALID') {
    if (isSubmitting) return;
    if (status === 'INVALID' && note.trim().length === 0) {
      setNoteError('A note is required when marking a trip invalid.');
      return;
    }
    setNoteError(null);
    setIsSubmitting(true);
    try {
      await apiClient.patch(`/api/admin/trips/${trip.id}/review`, {
        status,
        note: note.trim().length > 0 ? note.trim() : undefined,
      });
      const result = {
        reviewStatus: status,
        reviewedAt: new Date().toISOString(),
        adminReviewNote: note.trim().length > 0 ? note.trim() : null,
        reviewedByName: admin?.fullName ?? 'You',
      };
      setSaved(result);
      onReviewed(result);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmitting(false);
    }
  }

  const currentStatus = saved?.reviewStatus ?? trip.reviewStatus;
  const currentReviewedAt = saved?.reviewedAt ?? trip.reviewedAt;
  const currentReviewerName = saved?.reviewedByName ?? trip.reviewedByName;
  const currentNote = saved ? saved.adminReviewNote : trip.adminReviewNote;

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative flex h-full w-full max-w-md flex-col overflow-y-auto bg-white shadow-xl">
        <div className="flex items-center justify-between border-b border-border-subtle px-5 py-4">
          <h2 className="text-sm font-semibold text-gray-900">Short Trip Review</h2>
          <button onClick={onClose} className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100" aria-label="Close">
            <CloseIcon />
          </button>
        </div>

        {error && <p className="p-5 text-sm font-medium text-brand-red">{error}</p>}

        <div className="flex flex-1 flex-col gap-6 p-5">
          <div className="flex items-center justify-between">
            <div>
              <p className="font-semibold text-gray-900">{driverName}</p>
              <p className="text-xs text-gray-500">{plateNumber}</p>
            </div>
            <span
              className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ${REVIEW_STATUS_STYLES[currentStatus]}`}
            >
              {REVIEW_STATUS_LABELS[currentStatus]}
            </span>
          </div>

          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Trip</h3>
            <dl className="mt-2 space-y-2 text-sm">
              <div className="flex justify-between">
                <dt className="text-gray-500">Route</dt>
                <dd className="font-medium text-gray-900">{trip.route ?? '—'}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-gray-500">Trip Date</dt>
                <dd className="font-medium text-gray-900">{formatManilaDateTime(trip.startedAt)}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-gray-500">Start Time</dt>
                <dd className="font-medium text-gray-900">{formatManilaDateTime(trip.startedAt)}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-gray-500">End Time</dt>
                <dd className="font-medium text-gray-900">{trip.endedAt ? formatManilaDateTime(trip.endedAt) : '—'}</dd>
              </div>
              <div className="flex justify-between">
                <dt className="text-gray-500">Duration</dt>
                <dd className="font-medium text-gray-900">{durationLabel(trip.startedAt, trip.endedAt)}</dd>
              </div>
            </dl>
          </div>

          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Flag Reason</h3>
            <p className="mt-2 text-sm text-gray-800">{trip.flagReason ?? '—'}</p>
          </div>

          <div>
            <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Driver Explanation</h3>
            {trip.driverExplanation ? (
              <>
                <p className="mt-2 whitespace-pre-wrap text-sm text-gray-800">{trip.driverExplanation}</p>
                {trip.explanationSubmittedAt && (
                  <p className="mt-1 text-xs text-gray-400">
                    Submitted {formatManilaDateTime(trip.explanationSubmittedAt)}
                  </p>
                )}
              </>
            ) : (
              <p className="mt-2 text-sm text-gray-400">No explanation submitted yet.</p>
            )}
          </div>

          {currentReviewedAt && (
            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Previous Review</h3>
              <p className="mt-2 text-sm text-gray-800">
                {REVIEW_STATUS_LABELS[currentStatus]} by {currentReviewerName ?? 'an admin'} on{' '}
                {formatManilaDateTime(currentReviewedAt)}
              </p>
              {currentNote && <p className="mt-1 text-sm text-gray-600">"{currentNote}"</p>}
            </div>
          )}

          <div className="mt-auto flex flex-col gap-3 border-t border-border-subtle pt-4">
            <label className="text-xs font-semibold uppercase tracking-wide text-gray-400" htmlFor="admin-note">
              Admin Note {noteError ? <span className="text-brand-red">(required for Invalid)</span> : null}
            </label>
            <textarea
              id="admin-note"
              value={note}
              onChange={(e) => {
                setNote(e.target.value);
                if (noteError) setNoteError(null);
              }}
              rows={3}
              placeholder="Explain why this trip was accepted or rejected..."
              className={`w-full rounded-lg border px-3 py-2 text-sm focus:outline-none ${
                noteError ? 'border-brand-red' : 'border-border-subtle focus:border-brand-blue'
              }`}
            />
            {noteError && <p className="text-xs font-medium text-brand-red">{noteError}</p>}

            <div className="grid grid-cols-2 gap-2">
              <button
                onClick={() => handleReview('VALID')}
                disabled={isSubmitting}
                className="rounded-lg border border-status-good py-2 text-xs font-semibold text-status-good transition hover:bg-status-good-bg disabled:cursor-not-allowed disabled:opacity-50"
              >
                Valid
              </button>
              <button
                onClick={() => handleReview('INVALID')}
                disabled={isSubmitting}
                className="rounded-lg border border-status-critical py-2 text-xs font-semibold text-status-critical transition hover:bg-status-critical-bg disabled:cursor-not-allowed disabled:opacity-50"
              >
                Invalid
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
