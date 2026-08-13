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
  photoUrl: string | null;
  idSubmitted: boolean;
  verificationStatus: VerificationStatus;
  createdAt: string;
}

type Filter = 'all' | 'pending' | 'approved' | 'rejected';

const filters: { key: Filter; label: string }[] = [
  { key: 'all', label: 'All' },
  { key: 'pending', label: 'Pending' },
  { key: 'approved', label: 'Approved' },
  { key: 'rejected', label: 'Rejected' },
];

export default function IdVerificationPage() {
  const [filter, setFilter] = useState<Filter>('pending');
  const [commuters, setCommuters] = useState<Commuter[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    setIsLoading(true);
    const query = filter === 'all' ? '' : `?status=${filter}`;
    apiClient
      .get<{ commuters: Commuter[] }>(`/api/admin/commuters${query}`)
      .then((res) => setCommuters(res.commuters.filter((c) => filter !== 'all' || c.idSubmitted)))
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load commuters.'))
      .finally(() => setIsLoading(false));
  }, [filter]);

  return (
    <DashboardLayout>
      <h1 className="text-2xl font-semibold tracking-tight text-gray-900">ID Verification</h1>
      <p className="mt-1 text-sm text-gray-500">
        Review government ID and selfie submissions. No automated face-match runs yet — every decision here is manual.
      </p>

      <div className="mt-5 flex gap-1 border-b border-gray-200">
        {filters.map((f) => (
          <button
            key={f.key}
            onClick={() => setFilter(f.key)}
            className={`border-b-2 px-4 py-2.5 text-sm font-semibold transition ${
              filter === f.key
                ? 'border-brand-blue text-brand-blue'
                : 'border-transparent text-gray-500 hover:text-gray-700'
            }`}
          >
            {f.label}
          </button>
        ))}
      </div>

      {error && <p className="mt-6 text-sm font-medium text-brand-red">{error}</p>}
      {isLoading && <p className="mt-6 text-sm text-gray-500">Loading...</p>}
      {!isLoading && commuters.length === 0 && !error && (
        <p className="mt-6 text-sm text-gray-500">No submissions in this category.</p>
      )}

      {commuters.length > 0 && (
        <div className="mt-6 overflow-x-auto rounded-xl border border-border-subtle bg-surface-card">
          <table className="w-full min-w-[640px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-5 py-3">Commuter</th>
                <th className="px-5 py-3">Commuter ID</th>
                <th className="px-5 py-3">Mobile Number</th>
                <th className="px-5 py-3">Status</th>
                <th className="px-5 py-3">Submitted</th>
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
                      <div className="h-9 w-9 overflow-hidden rounded-full bg-gray-200">
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
