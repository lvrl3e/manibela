import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { Card, SectionHeader } from '../components/Card';
import { VerificationBadge, type VerificationStatus } from '../components/VerificationBadge';
import { CommuterRideHistorySection } from '../components/CommuterRideHistorySection';
import { apiClient, ApiError } from '../lib/apiClient';
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

function IdCardIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <circle cx="8.5" cy="11" r="1.8" />
      <path d="M6 15.5c.5-1.3 1.5-2 2.5-2s2 .7 2.5 2M14 10h4M14 13.5h4" strokeLinecap="round" />
    </svg>
  );
}

// Shaped like the content it's replaced by, matching every other page's
// skeleton pattern — this page previously rendered nothing at all while
// loading (not even a "Loading..." line), which read as a broken/blank
// page rather than "still fetching."
function DetailSkeleton() {
  return (
    <div className="mt-4 animate-pulse">
      <div className="flex items-center gap-4">
        <div className="h-16 w-16 shrink-0 rounded-full bg-gray-100" />
        <div className="space-y-2">
          <div className="h-5 w-40 rounded bg-gray-100" />
          <div className="h-4 w-56 rounded bg-gray-100" />
        </div>
      </div>
      <div className="mt-6 grid grid-cols-1 gap-4 rounded-xl border border-border-subtle bg-surface-card p-5 shadow-[0_1px_2px_rgba(16,24,40,0.04)] sm:grid-cols-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="space-y-2">
            <div className="h-3 w-20 rounded bg-gray-100" />
            <div className="h-4 w-16 rounded bg-gray-100" />
          </div>
        ))}
      </div>
      <div className="mt-8 grid grid-cols-1 gap-6 sm:grid-cols-3">
        {Array.from({ length: 3 }).map((_, i) => (
          <div key={i} className="aspect-video rounded-xl bg-gray-100" />
        ))}
      </div>
    </div>
  );
}

function PhotoTile({ label, url }: { label: string; url: string | null }) {
  const resolved = apiClient.resolveUrl(url);
  return (
    <div>
      <p className="mb-2 text-sm font-semibold text-gray-700">{label}</p>
      <div className="flex aspect-video items-center justify-center overflow-hidden rounded-xl border border-gray-200 bg-gray-50">
        {resolved ? (
          <img src={resolved} alt={label} className="h-full w-full object-contain" />
        ) : (
          <span className="text-sm text-gray-400">Not submitted</span>
        )}
      </div>
    </div>
  );
}

export default function CommuterDetailPage() {
  const { id } = useParams<{ id: string }>();
  const [commuter, setCommuter] = useState<CommuterDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  useEffect(() => {
    if (!id) return;
    apiClient
      .get<{ commuter: CommuterDetail }>(`/api/admin/commuters/${id}`)
      .then((res) => setCommuter(res.commuter))
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load this commuter.'));
  }, [id]);

  async function handleVerify(status: 'APPROVED' | 'REJECTED') {
    if (!commuter || isSubmitting) return;
    setActionError(null);
    setIsSubmitting(true);
    try {
      await apiClient.post(`/api/admin/commuters/${commuter.id}/verify`, { status });
      setCommuter({ ...commuter, verificationStatus: status });
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Something went wrong. Please try again.');
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
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Something went wrong. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <DashboardLayout title={commuter?.fullName ?? 'Commuter'}>
      <Link to="/commuters" className="text-sm font-medium text-brand-blue hover:underline">
        ← Back to Commuters
      </Link>

      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}

      {!commuter && !error && <DetailSkeleton />}

      {commuter && (
        <>
          <div className="mt-4 flex flex-wrap items-center justify-between gap-4">
            <div className="flex items-center gap-4">
              <div className="h-16 w-16 overflow-hidden rounded-full bg-gray-200">
                {commuter.photoUrl && (
                  <img
                    src={apiClient.resolveUrl(commuter.photoUrl) ?? undefined}
                    alt=""
                    className="h-full w-full object-cover"
                  />
                )}
              </div>
              <div>
                <p className="font-display text-lg font-semibold tracking-tight text-gray-900">{commuter.fullName}</p>
                <p className="text-sm text-gray-500">
                  {commuter.commuterId} · {formatPhone(commuter.mobileNumber)}
                </p>
              </div>
            </div>
            <div className="flex items-center gap-3">
              <span
                className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ${
                  commuter.isActive ? 'bg-status-good-bg text-status-good' : 'bg-status-critical-bg text-status-critical'
                }`}
              >
                {commuter.isActive ? 'Active' : 'Inactive'}
              </span>
              <VerificationBadge status={commuter.verificationStatus} notSubmitted={!commuter.idFrontUrl} />
              <button
                onClick={handleToggleStatus}
                disabled={isSubmitting}
                className={`rounded-lg px-4 py-2 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-50 ${
                  commuter.isActive
                    ? 'border border-status-critical text-status-critical hover:bg-status-critical-bg'
                    : 'bg-brand-blue text-white hover:brightness-110'
                }`}
              >
                {isSubmitting ? 'Please wait...' : commuter.isActive ? 'Deactivate' : 'Reactivate'}
              </button>
            </div>
          </div>

          <Card className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-4">
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Date of Birth</p>
              <p className="mt-1 text-sm text-gray-800">{commuter.dateOfBirth ?? '—'}</p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Phone Verified</p>
              <p className="mt-1 text-sm text-gray-800">{commuter.phoneVerified ? 'Yes' : 'No'}</p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">ID Type</p>
              <p className="mt-1 text-sm text-gray-800">{commuter.idType ?? '—'}</p>
            </div>
            <div>
              <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Ride Requests</p>
              <p className="mt-1 text-sm text-gray-800">{commuter.totalSignals}</p>
            </div>
          </Card>

          <div className="mt-8">
            <SectionHeader
              icon={<IdCardIcon />}
              title="KYC Documents"
              action={
                commuter.idFrontUrl && (
                  <div className="flex items-center gap-2">
                    <button
                      onClick={() => handleVerify('REJECTED')}
                      disabled={isSubmitting || commuter.verificationStatus === 'REJECTED'}
                      className="rounded-lg border border-status-critical px-4 py-2 text-sm font-semibold text-status-critical transition hover:bg-status-critical-bg disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      Reject
                    </button>
                    <button
                      onClick={() => handleVerify('APPROVED')}
                      disabled={isSubmitting || commuter.verificationStatus === 'APPROVED'}
                      className="rounded-lg bg-brand-blue px-4 py-2 text-sm font-semibold text-white transition hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      Approve
                    </button>
                  </div>
                )
              }
            />
            <p className="mt-1 pl-9 text-sm text-gray-500">
              Submitted during sign-up. No automated face-match runs against these yet — review manually.
            </p>
          </div>

          {actionError && <p className="mt-2 text-sm font-medium text-brand-red">{actionError}</p>}

          <div className="mt-4 grid grid-cols-1 gap-6 sm:grid-cols-3">
            <PhotoTile label="ID Front" url={commuter.idFrontUrl} />
            <PhotoTile label="ID Back" url={commuter.idBackUrl} />
            <PhotoTile label="Selfie" url={commuter.selfieUrl} />
          </div>

          <CommuterRideHistorySection commuterId={commuter.id} />
        </>
      )}
    </DashboardLayout>
  );
}
