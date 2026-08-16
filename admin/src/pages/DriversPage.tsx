import { useEffect, useState, type FormEvent } from 'react';
import { useSearchParams } from 'react-router-dom';
import { DashboardLayout } from '../components/DashboardLayout';
import { StatCard } from '../components/StatCard';
import { PaginationControls } from '../components/PaginationControls';
import { DriverDetailPanel } from '../components/DriverDetailPanel';
import { EyeIcon } from '../components/EyeIcon';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { useDebouncedValue } from '../lib/useDebouncedValue';
import { formatManilaDate } from '../lib/formatDate';
import { formatPhone } from '../lib/formatPhone';

interface Driver {
  id: string;
  driverId: string;
  fullName: string;
  mobileNumber: string;
  plateNumber: string;
  dateOfBirth: string | null;
  photoUrl: string | null;
  isActive: boolean;
  createdAt: string;
}

interface DriversResponse {
  drivers: Driver[];
  currentPage: number;
  pageSize: number;
  totalDrivers: number;
  totalPages: number;
  hasNextPage: boolean;
}

interface DriverStats {
  totalDrivers: number;
  activeDrivers: number;
  inactiveDrivers: number;
  totalDriversChangePercent: number | null;
}

function DriverIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <circle cx="12" cy="12" r="2.4" />
      <path d="M12 3v6.6M4.5 16.5l5-3.2M19.5 16.5l-5-3.2" />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="12" cy="12" r="9" />
      <path d="m8.5 12.5 2.3 2.3 4.7-4.8" />
    </svg>
  );
}

function WarningIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M12 3.5 2.5 20h19L12 3.5Z" />
      <path d="M12 10v4.5M12 17.5h.01" />
    </svg>
  );
}

function SearchIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <circle cx="11" cy="11" r="7" />
      <path d="m21 21-4-4" />
    </svg>
  );
}

const FILTERS: { label: string; value: 'all' | 'active' | 'inactive' }[] = [
  { label: 'All', value: 'all' },
  { label: 'Active', value: 'active' },
  { label: 'Inactive', value: 'inactive' },
];

const PAGE_SIZE = 25;

function AddDriverModal({ onClose, onCreated }: { onClose: () => void; onCreated: (driver: Driver) => void }) {
  const [fullName, setFullName] = useState('');
  const [mobileNumber, setMobileNumber] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
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
            <label className="block text-sm font-medium text-gray-700" htmlFor="newDriverPassword">
              Temporary Password
            </label>
            <div className="relative mt-1.5">
              <input
                id="newDriverPassword"
                required
                minLength={8}
                type={showPassword ? 'text' : 'password'}
                autoComplete="new-password"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="At least 8 characters"
                className="w-full rounded-lg border border-border-subtle px-3 py-2.5 pr-10 text-sm focus:border-brand-blue focus:outline-none"
              />
              <button
                type="button"
                onClick={() => setShowPassword((v) => !v)}
                className="absolute inset-y-0 right-3 flex items-center text-gray-400 hover:text-gray-600"
                aria-label={showPassword ? 'Hide password' : 'Show password'}
              >
                <EyeIcon open={showPassword} />
              </button>
            </div>
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
  const [data, setData] = useState<DriversResponse | null>(null);
  const [stats, setStats] = useState<DriverStats | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [showAddModal, setShowAddModal] = useState(false);
  const [searchParams, setSearchParams] = useSearchParams();
  const [selectedDriverId, setSelectedDriverId] = useState<string | null>(searchParams.get('driverId'));
  const [filter, setFilter] = useState<(typeof FILTERS)[number]['value']>('all');
  const [search, setSearch] = useState('');
  const debouncedSearch = useDebouncedValue(search, 300);
  const [page, setPage] = useState(1);

  // Lets a notification (e.g. "Short trip flagged") deep-link straight to
  // a driver's panel via /drivers?driverId=... — read once on mount so
  // navigating away and back to /drivers plainly doesn't keep reopening it.
  useEffect(() => {
    const driverId = searchParams.get('driverId');
    if (driverId) {
      setSelectedDriverId(driverId);
      searchParams.delete('driverId');
      setSearchParams(searchParams, { replace: true });
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function fetchStats() {
    apiClient.get<DriverStats>('/api/admin/driver-stats').then(setStats).catch(() => {});
  }

  function fetchDrivers() {
    const params = new URLSearchParams({ page: String(page), pageSize: String(PAGE_SIZE) });
    if (filter !== 'all') params.set('accountStatus', filter);
    if (debouncedSearch.trim()) params.set('search', debouncedSearch.trim());
    apiClient
      .get<DriversResponse>(`/api/admin/drivers?${params.toString()}`)
      .then((res) => {
        setData(res);
        setError(null);
      })
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load drivers.'));
  }

  useEffect(fetchStats, []);
  usePolling(fetchStats, 8000);

  useEffect(() => {
    setIsLoading(true);
    fetchDrivers();
    setIsLoading(false);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, debouncedSearch, page]);
  usePolling(fetchDrivers, 8000);

  useEffect(() => {
    setPage(1);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [filter, debouncedSearch]);

  const drivers = data?.drivers ?? [];

  return (
    <DashboardLayout>
      <div className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight text-gray-900">Drivers</h1>
          <p className="mt-1 text-sm text-gray-500">{data ? `${data.totalDrivers} account(s)` : '…'}</p>
        </div>
        <button
          onClick={() => setShowAddModal(true)}
          className="self-start rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white hover:brightness-110 sm:self-auto"
        >
          + Add Driver
        </button>
      </div>

      {stats && (
        <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-3">
          <StatCard
            label="Total Drivers"
            value={stats.totalDrivers}
            icon={<DriverIcon />}
            changePercent={stats.totalDriversChangePercent}
            changeLabel="vs last month"
          />
          <StatCard label="Active Drivers" value={stats.activeDrivers} icon={<CheckIcon />} />
          <StatCard label="Inactive Drivers" value={stats.inactiveDrivers} icon={<WarningIcon />} />
        </div>
      )}

      <div className="mt-6 flex flex-wrap items-center justify-between gap-3">
        <div className="flex flex-wrap gap-2">
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
        <div className="flex items-center gap-2 rounded-lg border border-border-subtle bg-white px-3 py-2 sm:w-72">
          <SearchIcon />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search name, mobile, plate, or ID"
            className="w-full text-sm text-gray-700 focus:outline-none"
          />
        </div>
      </div>

      {error && <p className="mt-6 text-sm font-medium text-brand-red">{error}</p>}
      {isLoading && <p className="mt-6 text-sm text-gray-500">Loading...</p>}

      {!isLoading && drivers.length === 0 && !error && (
        <p className="mt-6 text-sm text-gray-500">No drivers in this category.</p>
      )}

      {drivers.length > 0 && (
        <div className="mt-6 overflow-x-auto rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
          <table className="w-full min-w-[720px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-5 py-3">Driver</th>
                <th className="px-5 py-3">Driver ID</th>
                <th className="px-5 py-3">Mobile Number</th>
                <th className="px-5 py-3">Plate Number</th>
                <th className="px-5 py-3">Status</th>
                <th className="px-5 py-3">Joined</th>
                <th className="px-5 py-3">Actions</th>
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
                  <td className="px-5 py-3 text-gray-600">{formatPhone(driver.mobileNumber)}</td>
                  <td className="px-5 py-3 text-gray-600">{driver.plateNumber}</td>
                  <td className="px-5 py-3">
                    <span
                      className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ${
                        driver.isActive ? 'bg-status-good-bg text-status-good' : 'bg-status-critical-bg text-status-critical'
                      }`}
                    >
                      {driver.isActive ? 'Active' : 'Inactive'}
                    </span>
                  </td>
                  <td className="px-5 py-3 text-gray-600">{formatManilaDate(driver.createdAt)}</td>
                  <td className="px-5 py-3">
                    <button
                      onClick={() => setSelectedDriverId(driver.id)}
                      className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100 hover:text-brand-blue"
                      aria-label="View driver"
                    >
                      <EyeIcon open />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {data && (
        <PaginationControls
          currentPage={data.currentPage}
          totalPages={data.totalPages}
          hasNextPage={data.hasNextPage}
          onPageChange={setPage}
        />
      )}

      {showAddModal && (
        <AddDriverModal
          onClose={() => setShowAddModal(false)}
          onCreated={() => {
            setShowAddModal(false);
            setPage(1);
            fetchDrivers();
          }}
        />
      )}

      {selectedDriverId && (
        <DriverDetailPanel
          driverId={selectedDriverId}
          onClose={() => setSelectedDriverId(null)}
          onStatusChange={(isActive) =>
            setData((prev) =>
              prev
                ? { ...prev, drivers: prev.drivers.map((d) => (d.id === selectedDriverId ? { ...d, isActive } : d)) }
                : prev,
            )
          }
        />
      )}
    </DashboardLayout>
  );
}
