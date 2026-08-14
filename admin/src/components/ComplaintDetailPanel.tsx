import { useEffect, useState } from 'react';
import { apiClient, ApiError } from '../lib/apiClient';
import { formatManilaDateTime } from '../lib/formatDate';

type ComplaintStatus = 'PENDING' | 'INVESTIGATING' | 'RESOLVED' | 'REJECTED';

interface ComplaintDetail {
  id: string;
  complainantName: string;
  complainantMobileNumber: string | null;
  driverName: string;
  plateNumber: string;
  complaintType: string;
  description: string;
  attachmentUrl: string | null;
  status: ComplaintStatus;
  createdAt: string;
}

function CloseIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M5 5l14 14M19 5 5 19" />
    </svg>
  );
}

const STATUS_STYLES: Record<ComplaintStatus, string> = {
  PENDING: 'bg-gray-100 text-gray-600',
  INVESTIGATING: 'bg-amber-100 text-amber-700',
  RESOLVED: 'bg-status-good-bg text-status-good',
  REJECTED: 'bg-status-critical-bg text-status-critical',
};

export function ComplaintDetailPanel({
  complaintId,
  onClose,
  onStatusChange,
}: {
  complaintId: string;
  onClose: () => void;
  onStatusChange: (status: ComplaintStatus) => void;
}) {
  const [complaint, setComplaint] = useState<ComplaintDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    setComplaint(null);
    apiClient
      .get<{ complaint: ComplaintDetail }>(`/api/admin/complaints/${complaintId}`)
      .then((res) => setComplaint(res.complaint))
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load this complaint.'));
  }, [complaintId]);

  async function handleSetStatus(status: 'INVESTIGATING' | 'RESOLVED' | 'REJECTED') {
    if (!complaint || isSubmitting) return;
    setIsSubmitting(true);
    try {
      await apiClient.patch(`/api/admin/complaints/${complaint.id}/status`, { status });
      setComplaint({ ...complaint, status });
      onStatusChange(status);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmitting(false);
    }
  }

  const resolvedAttachment = complaint ? apiClient.resolveUrl(complaint.attachmentUrl) : null;

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative flex h-full w-full max-w-md flex-col overflow-y-auto bg-white shadow-xl">
        <div className="flex items-center justify-between border-b border-border-subtle px-5 py-4">
          <h2 className="text-sm font-semibold text-gray-900">Complaint Details</h2>
          <button onClick={onClose} className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100" aria-label="Close">
            <CloseIcon />
          </button>
        </div>

        {error && <p className="p-5 text-sm font-medium text-brand-red">{error}</p>}

        {!complaint && !error && <p className="p-5 text-sm text-gray-500">Loading...</p>}

        {complaint && (
          <div className="flex flex-1 flex-col gap-6 p-5">
            <div className="flex items-center justify-between">
              <div>
                <p className="font-semibold text-gray-900">{complaint.complaintType}</p>
                <p className="text-xs text-gray-500">{formatManilaDateTime(complaint.createdAt)}</p>
              </div>
              <span
                className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ${STATUS_STYLES[complaint.status]}`}
              >
                {complaint.status}
              </span>
            </div>

            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Description</h3>
              <p className="mt-2 text-sm text-gray-800">{complaint.description}</p>
            </div>

            {resolvedAttachment && (
              <div>
                <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Attachment</h3>
                <div className="mt-2 overflow-hidden rounded-xl border border-border-subtle">
                  <img src={resolvedAttachment} alt="Complaint attachment" className="w-full object-cover" />
                </div>
              </div>
            )}

            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Complainant</h3>
              <dl className="mt-2 space-y-2 text-sm">
                <div className="flex justify-between">
                  <dt className="text-gray-500">Name</dt>
                  <dd className="font-medium text-gray-900">{complaint.complainantName}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-gray-500">Mobile Number</dt>
                  <dd className="font-medium text-gray-900">{complaint.complainantMobileNumber ?? '—'}</dd>
                </div>
              </dl>
            </div>

            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Reported Driver</h3>
              <dl className="mt-2 space-y-2 text-sm">
                <div className="flex justify-between">
                  <dt className="text-gray-500">Name</dt>
                  <dd className="font-medium text-gray-900">{complaint.driverName}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-gray-500">Plate Number</dt>
                  <dd className="font-medium text-gray-900">{complaint.plateNumber}</dd>
                </div>
              </dl>
            </div>

            <div className="mt-auto grid grid-cols-3 gap-2 pt-2">
              <button
                onClick={() => handleSetStatus('INVESTIGATING')}
                disabled={isSubmitting || complaint.status === 'INVESTIGATING'}
                className="rounded-lg border border-amber-500 py-2 text-xs font-semibold text-amber-700 transition hover:bg-amber-50 disabled:cursor-not-allowed disabled:opacity-50"
              >
                Investigating
              </button>
              <button
                onClick={() => handleSetStatus('RESOLVED')}
                disabled={isSubmitting || complaint.status === 'RESOLVED'}
                className="rounded-lg border border-status-good py-2 text-xs font-semibold text-status-good transition hover:bg-status-good-bg disabled:cursor-not-allowed disabled:opacity-50"
              >
                Resolved
              </button>
              <button
                onClick={() => handleSetStatus('REJECTED')}
                disabled={isSubmitting || complaint.status === 'REJECTED'}
                className="rounded-lg border border-status-critical py-2 text-xs font-semibold text-status-critical transition hover:bg-status-critical-bg disabled:cursor-not-allowed disabled:opacity-50"
              >
                Rejected
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}
