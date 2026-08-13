import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { VerificationBadge, type VerificationStatus } from '../components/VerificationBadge';
import { apiClient, ApiError } from '../lib/apiClient';

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
  createdAt: string;
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

  return (
    <DashboardLayout>
      <Link to="/commuters" className="text-sm font-medium text-brand-blue hover:underline">
        ← Back to Commuters
      </Link>

      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}

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
                <h1 className="text-2xl font-semibold tracking-tight text-gray-900">{commuter.fullName}</h1>
                <p className="text-sm text-gray-500">
                  {commuter.commuterId} · {commuter.mobileNumber}
                </p>
              </div>
            </div>
            <VerificationBadge status={commuter.verificationStatus} notSubmitted={!commuter.idFrontUrl} />
          </div>

          <div className="mt-6 grid grid-cols-1 gap-4 rounded-xl border border-border-subtle bg-surface-card p-5 sm:grid-cols-3">
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
          </div>

          <div className="mt-8 flex flex-wrap items-center justify-between gap-3">
            <div>
              <h2 className="text-lg font-semibold text-gray-900">KYC Documents</h2>
              <p className="mt-1 text-sm text-gray-500">
                Submitted during sign-up. No automated face-match runs against these yet — review manually.
              </p>
            </div>

            {commuter.idFrontUrl && (
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
            )}
          </div>

          {actionError && <p className="mt-2 text-sm font-medium text-brand-red">{actionError}</p>}

          <div className="mt-4 grid grid-cols-1 gap-6 sm:grid-cols-3">
            <PhotoTile label="ID Front" url={commuter.idFrontUrl} />
            <PhotoTile label="ID Back" url={commuter.idBackUrl} />
            <PhotoTile label="Selfie" url={commuter.selfieUrl} />
          </div>
        </>
      )}
    </DashboardLayout>
  );
}
