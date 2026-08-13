import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { VerificationBadge, type VerificationStatus } from '../components/VerificationBadge';
import { apiClient, ApiError } from '../lib/apiClient';

interface Commuter {
  id: string;
  commuterId: string;
  fullName: string;
  mobileNumber: string;
  dateOfBirth: string | null;
  photoUrl: string | null;
  phoneVerified: boolean;
  idSubmitted: boolean;
  verificationStatus: VerificationStatus;
  createdAt: string;
}

function PhoneBadge({ verified }: { verified: boolean }) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ${
        verified ? 'bg-status-good-bg text-status-good' : 'bg-gray-100 text-gray-500'
      }`}
    >
      {verified ? 'Verified' : 'Unverified'}
    </span>
  );
}

export default function CommutersPage() {
  const [commuters, setCommuters] = useState<Commuter[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    apiClient
      .get<{ commuters: Commuter[] }>('/api/admin/commuters')
      .then((res) => setCommuters(res.commuters))
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load commuters.'))
      .finally(() => setIsLoading(false));
  }, []);

  return (
    <DashboardLayout>
      <h1 className="text-2xl font-semibold tracking-tight text-gray-900">Commuters</h1>
      <p className="mt-1 text-sm text-gray-500">{commuters.length} account(s)</p>

      {error && <p className="mt-6 text-sm font-medium text-brand-red">{error}</p>}
      {isLoading && <p className="mt-6 text-sm text-gray-500">Loading...</p>}
      {!isLoading && commuters.length === 0 && !error && (
        <p className="mt-6 text-sm text-gray-500">No commuters yet.</p>
      )}

      {commuters.length > 0 && (
        <div className="mt-6 overflow-x-auto rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
          <table className="w-full min-w-[720px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-5 py-3">Commuter</th>
                <th className="px-5 py-3">Commuter ID</th>
                <th className="px-5 py-3">Mobile Number</th>
                <th className="px-5 py-3">Phone</th>
                <th className="px-5 py-3">ID / KYC</th>
                <th className="px-5 py-3">Joined</th>
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
                      <div className="h-9 w-9 shrink-0 overflow-hidden rounded-full bg-gray-200">
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
                    <PhoneBadge verified={commuter.phoneVerified} />
                  </td>
                  <td className="px-5 py-3">
                    <VerificationBadge status={commuter.verificationStatus} notSubmitted={!commuter.idSubmitted} />
                  </td>
                  <td className="px-5 py-3 text-gray-600">{new Date(commuter.createdAt).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </DashboardLayout>
  );
}
