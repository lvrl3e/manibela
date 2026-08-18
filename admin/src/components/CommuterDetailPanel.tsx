import { useEffect, useState } from 'react';
import { VerificationBadge, type VerificationStatus } from './VerificationBadge';
import { CommuterRideHistorySection } from './CommuterRideHistorySection';
import { apiClient, ApiError } from '../lib/apiClient';
import { formatManilaDate } from '../lib/formatDate';
import { formatPhone } from '../lib/formatPhone';

interface CommuterDetail {
  id: string;
  commuterId: string;
  fullName: string;
  mobileNumber: string;
  dateOfBirth: string | null;
  photoUrl: string | null;
  phoneVerified: boolean;
  idType: string | null;
  idFrontUrl: string | null;
  idBackUrl: string | null;
  selfieUrl: string | null;
  verificationStatus: VerificationStatus;
  isActive: boolean;
  totalSignals: number;
  createdAt: string;
}

function CloseIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M5 5l14 14M19 5 5 19" />
    </svg>
  );
}

function EditIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 20h9" />
      <path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4Z" />
    </svg>
  );
}

/** Date of birth is no longer editable by the commuter themselves (see
 * PATCH /commuter/me) — only an admin can set/correct it, same
 * verified-by-a-human reasoning as a driver's plate/license number (see
 * DriverDetailPanel's own DateOfBirthField). Uses a native
 * `<input type="date">`, whose value format ("YYYY-MM-DD") already
 * matches what the backend's `dateOnly` schema expects/returns. */
function DateOfBirthField({
  commuterId,
  dateOfBirth,
  onChanged,
}: {
  commuterId: string;
  dateOfBirth: string | null;
  onChanged: (dateOfBirth: string | null) => void;
}) {
  const [isEditing, setIsEditing] = useState(false);
  const [value, setValue] = useState(dateOfBirth ?? '');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  function startEditing() {
    setValue(dateOfBirth ?? '');
    setError(null);
    setIsEditing(true);
  }

  async function handleSave() {
    if (isSubmitting) return;
    setError(null);
    setIsSubmitting(true);
    try {
      const res = await apiClient.patch<{ commuter: { dateOfBirth: string | null } }>(
        `/api/admin/commuters/${commuterId}/date-of-birth`,
        { dateOfBirth: value || null },
      );
      onChanged(res.commuter.dateOfBirth);
      setIsEditing(false);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmitting(false);
    }
  }

  if (!isEditing) {
    return (
      <div className="flex justify-between">
        <dt className="text-gray-500">Date of Birth</dt>
        <dd className="flex items-center gap-1.5 font-medium text-gray-900">
          {dateOfBirth ?? '—'}
          <button
            onClick={startEditing}
            className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-brand-blue"
            aria-label="Edit date of birth"
          >
            <EditIcon />
          </button>
        </dd>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-1.5">
      <div className="flex items-center justify-between">
        <dt className="text-gray-500">Date of Birth</dt>
        <div className="flex items-center gap-1.5">
          <input
            autoFocus
            type="date"
            value={value}
            onChange={(e) => setValue(e.target.value)}
            className="rounded-lg border border-border-subtle px-2 py-1 text-sm font-medium focus:border-brand-blue focus:outline-none"
          />
          <button
            onClick={handleSave}
            disabled={isSubmitting}
            className="rounded-lg bg-brand-blue px-2.5 py-1 text-xs font-semibold text-white hover:brightness-110 disabled:opacity-60"
          >
            {isSubmitting ? '...' : 'Save'}
          </button>
          <button
            onClick={() => setIsEditing(false)}
            disabled={isSubmitting}
            className="rounded-lg border border-border-subtle px-2.5 py-1 text-xs font-semibold text-gray-600 hover:bg-gray-50"
          >
            Cancel
          </button>
        </div>
      </div>
      {error && <p className="text-right text-xs font-medium text-brand-red">{error}</p>}
    </div>
  );
}

function PhotoTile({ label, url }: { label: string; url: string | null }) {
  const resolved = apiClient.resolveUrl(url);
  return (
    <div>
      <p className="mb-1.5 text-xs font-semibold text-gray-600">{label}</p>
      <div className="flex aspect-video items-center justify-center overflow-hidden rounded-lg border border-gray-200 bg-gray-50">
        {resolved ? (
          <img src={resolved} alt={label} className="h-full w-full object-contain" />
        ) : (
          <span className="text-xs text-gray-400">Not submitted</span>
        )}
      </div>
    </div>
  );
}

export function CommuterDetailPanel({
  commuterId,
  onClose,
  onStatusChange,
}: {
  commuterId: string;
  onClose: () => void;
  onStatusChange: (isActive: boolean) => void;
}) {
  const [commuter, setCommuter] = useState<CommuterDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    setCommuter(null);
    apiClient
      .get<{ commuter: CommuterDetail }>(`/api/admin/commuters/${commuterId}`)
      .then((res) => setCommuter(res.commuter))
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load this commuter.'));
  }, [commuterId]);

  async function handleVerify(status: 'APPROVED' | 'REJECTED') {
    if (!commuter || isSubmitting) return;
    setActionError(null);
    setIsSubmitting(true);
    try {
      await apiClient.post(`/api/admin/commuters/${commuter.id}/verify`, { status });
      setCommuter({ ...commuter, verificationStatus: status });
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleToggleStatus() {
    if (!commuter || isSubmitting) return;
    setActionError(null);
    setIsSubmitting(true);
    try {
      const nextActive = !commuter.isActive;
      await apiClient.patch(`/api/admin/commuters/${commuter.id}/status`, { isActive: nextActive });
      setCommuter({ ...commuter, isActive: nextActive });
      onStatusChange(nextActive);
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative flex h-full w-full max-w-md flex-col overflow-y-auto bg-white shadow-xl">
        <div className="flex items-center justify-between border-b border-border-subtle px-5 py-4">
          <h2 className="text-sm font-semibold text-gray-900">Commuter Details</h2>
          <button onClick={onClose} className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100" aria-label="Close">
            <CloseIcon />
          </button>
        </div>

        {error && <p className="p-5 text-sm font-medium text-brand-red">{error}</p>}

        {!commuter && !error && <p className="p-5 text-sm text-gray-500">Loading...</p>}

        {commuter && (
          <div className="flex flex-1 flex-col gap-6 p-5">
            <div className="flex items-center gap-4">
              <div className="h-16 w-16 shrink-0 overflow-hidden rounded-full bg-gray-200">
                {commuter.photoUrl && (
                  <img src={apiClient.resolveUrl(commuter.photoUrl) ?? undefined} alt="" className="h-full w-full object-cover" />
                )}
              </div>
              <div>
                <p className="font-semibold text-gray-900">{commuter.fullName}</p>
                <p className="text-xs text-gray-500">
                  {commuter.commuterId} · {formatPhone(commuter.mobileNumber)}
                </p>
                <div className="mt-1 flex flex-wrap items-center gap-1.5">
                  <span
                    className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${
                      commuter.isActive ? 'bg-status-good-bg text-status-good' : 'bg-status-critical-bg text-status-critical'
                    }`}
                  >
                    {commuter.isActive ? 'Active' : 'Inactive'}
                  </span>
                  <VerificationBadge status={commuter.verificationStatus} notSubmitted={!commuter.idFrontUrl} />
                </div>
              </div>
            </div>

            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Commuter Information</h3>
              <dl className="mt-2 space-y-2 text-sm">
                <DateOfBirthField
                  commuterId={commuter.id}
                  dateOfBirth={commuter.dateOfBirth}
                  onChanged={(dateOfBirth) => setCommuter({ ...commuter, dateOfBirth })}
                />
                <div className="flex justify-between">
                  <dt className="text-gray-500">Phone Verified</dt>
                  <dd className="font-medium text-gray-900">{commuter.phoneVerified ? 'Yes' : 'No'}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-gray-500">ID Type</dt>
                  <dd className="font-medium text-gray-900">{commuter.idType ?? '—'}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-gray-500">Ride Requests</dt>
                  <dd className="font-medium text-gray-900">{commuter.totalSignals}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-gray-500">Date Registered</dt>
                  <dd className="font-medium text-gray-900">{formatManilaDate(commuter.createdAt)}</dd>
                </div>
              </dl>
            </div>

            <div>
              <div className="flex items-center justify-between">
                <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">KYC Documents</h3>
                {commuter.idFrontUrl && (
                  <div className="flex gap-1.5">
                    <button
                      onClick={() => handleVerify('REJECTED')}
                      disabled={isSubmitting || commuter.verificationStatus === 'REJECTED'}
                      className="rounded-lg border border-status-critical px-2.5 py-1 text-xs font-semibold text-status-critical hover:bg-status-critical-bg disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      Reject
                    </button>
                    <button
                      onClick={() => handleVerify('APPROVED')}
                      disabled={isSubmitting || commuter.verificationStatus === 'APPROVED'}
                      className="rounded-lg bg-brand-blue px-2.5 py-1 text-xs font-semibold text-white hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      Approve
                    </button>
                  </div>
                )}
              </div>
              {actionError && <p className="mt-2 text-xs font-medium text-brand-red">{actionError}</p>}
              <div className="mt-2 grid grid-cols-2 gap-3">
                <PhotoTile label="ID Front" url={commuter.idFrontUrl} />
                <PhotoTile label="ID Back" url={commuter.idBackUrl} />
                <PhotoTile label="Selfie" url={commuter.selfieUrl} />
              </div>
            </div>

            <CommuterRideHistorySection commuterId={commuter.id} compact />

            <button
              onClick={handleToggleStatus}
              disabled={isSubmitting}
              className={`mt-auto w-full rounded-lg py-2.5 text-sm font-semibold transition disabled:opacity-60 ${
                commuter.isActive
                  ? 'border border-status-critical text-status-critical hover:bg-status-critical-bg'
                  : 'bg-brand-blue text-white hover:brightness-110'
              }`}
            >
              {isSubmitting ? 'Please wait...' : commuter.isActive ? 'Deactivate Commuter' : 'Reactivate Commuter'}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
