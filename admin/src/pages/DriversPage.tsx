import { useEffect, useState, type FormEvent } from 'react';
import { DashboardLayout } from '../components/DashboardLayout';
import { apiClient, ApiError } from '../lib/apiClient';

interface Driver {
  id: string;
  driverId: string;
  fullName: string;
  mobileNumber: string;
  plateNumber: string;
  dateOfBirth: string | null;
  photoUrl: string | null;
  createdAt: string;
}

function AddDriverModal({ onClose, onCreated }: { onClose: () => void; onCreated: (driver: Driver) => void }) {
  const [fullName, setFullName] = useState('');
  const [mobileNumber, setMobileNumber] = useState('');
  const [password, setPassword] = useState('');
  const [plateNumber, setPlateNumber] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (isSubmitting) return;

    setError(null);
    setIsSubmitting(true);
    try {
      const res = await apiClient.post<{ driver: Driver }>('/api/admin/drivers', {
        fullName,
        mobileNumber,
        password,
        plateNumber,
      });
      onCreated(res.driver);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/40 px-4">
      <div className="w-full max-w-md rounded-xl bg-white p-6 shadow-xl">
        <h2 className="text-lg font-semibold text-gray-900">Add Driver</h2>
        <p className="mt-1 text-sm text-gray-500">Creates the account directly — drivers don't self-register.</p>

        <form onSubmit={handleSubmit} className="mt-5 space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700">Full Name</label>
            <input
              required
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              className="mt-1.5 w-full rounded-lg border border-border-subtle px-3 py-2.5 text-sm focus:border-brand-blue focus:outline-none"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700">Mobile Number</label>
            <input
              required
              value={mobileNumber}
              onChange={(e) => setMobileNumber(e.target.value)}
              placeholder="09XXXXXXXXX"
              className="mt-1.5 w-full rounded-lg border border-border-subtle px-3 py-2.5 text-sm focus:border-brand-blue focus:outline-none"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700">Plate Number</label>
            <input
              required
              value={plateNumber}
              onChange={(e) => setPlateNumber(e.target.value)}
              placeholder="ABC123"
              className="mt-1.5 w-full rounded-lg border border-border-subtle px-3 py-2.5 text-sm focus:border-brand-blue focus:outline-none"
            />
          </div>
          <div>
            <label className="block text-sm font-medium text-gray-700">Temporary Password</label>
            <input
              required
              minLength={8}
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="At least 8 characters"
              className="mt-1.5 w-full rounded-lg border border-border-subtle px-3 py-2.5 text-sm focus:border-brand-blue focus:outline-none"
            />
          </div>

          {error && <p className="text-sm font-medium text-brand-red">{error}</p>}

          <div className="flex gap-3 pt-2">
            <button
              type="button"
              onClick={onClose}
              className="flex-1 rounded-lg border border-border-subtle py-2.5 text-sm font-semibold text-gray-700 hover:bg-gray-50"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={isSubmitting}
              className="flex-1 rounded-lg bg-brand-blue py-2.5 text-sm font-semibold text-white hover:brightness-110 disabled:opacity-60"
            >
              {isSubmitting ? 'Creating...' : 'Create Driver'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
}

export default function DriversPage() {
  const [drivers, setDrivers] = useState<Driver[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);

  useEffect(() => {
    apiClient
      .get<{ drivers: Driver[] }>('/api/admin/drivers')
      .then((res) => setDrivers(res.drivers))
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load drivers.'))
      .finally(() => setIsLoading(false));
  }, []);

  return (
    <DashboardLayout>
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-gray-900">Drivers</h1>
          <p className="mt-1 text-sm text-gray-500">{drivers.length} account(s)</p>
        </div>
        <button
          onClick={() => setShowAddModal(true)}
          className="self-start rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white hover:brightness-110 sm:self-auto"
        >
          + Add Driver
        </button>
      </div>

      {error && <p className="mt-6 text-sm font-medium text-brand-red">{error}</p>}
      {isLoading && <p className="mt-6 text-sm text-gray-500">Loading...</p>}

      {!isLoading && drivers.length === 0 && !error && (
        <p className="mt-6 text-sm text-gray-500">No drivers yet.</p>
      )}

      {drivers.length > 0 && (
        <div className="mt-6 overflow-x-auto rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
          <table className="w-full min-w-[640px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-5 py-3">Driver</th>
                <th className="px-5 py-3">Driver ID</th>
                <th className="px-5 py-3">Mobile Number</th>
                <th className="px-5 py-3">Plate Number</th>
                <th className="px-5 py-3">Joined</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {drivers.map((driver) => (
                <tr key={driver.id} className="transition hover:bg-gray-50">
                  <td className="px-5 py-3">
                    <div className="flex items-center gap-3">
                      <div className="h-9 w-9 shrink-0 overflow-hidden rounded-full bg-gray-200">
                        {driver.photoUrl && (
                          <img
                            src={apiClient.resolveUrl(driver.photoUrl) ?? undefined}
                            alt=""
                            className="h-full w-full object-cover"
                          />
                        )}
                      </div>
                      <span className="font-medium text-gray-900">{driver.fullName}</span>
                    </div>
                  </td>
                  <td className="px-5 py-3 text-gray-600">{driver.driverId}</td>
                  <td className="px-5 py-3 text-gray-600">{driver.mobileNumber}</td>
                  <td className="px-5 py-3 text-gray-600">{driver.plateNumber}</td>
                  <td className="px-5 py-3 text-gray-600">{new Date(driver.createdAt).toLocaleDateString()}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {showAddModal && (
        <AddDriverModal
          onClose={() => setShowAddModal(false)}
          onCreated={(driver) => {
            setDrivers((prev) => [driver, ...prev]);
            setShowAddModal(false);
          }}
        />
      )}
    </DashboardLayout>
  );
}
