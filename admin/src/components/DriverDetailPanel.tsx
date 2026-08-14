import { useEffect, useState, type ChangeEvent } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { apiClient, ApiError } from '../lib/apiClient';
import { formatManilaDate } from '../lib/formatDate';
import { usePolling } from '../lib/usePolling';
import { DriverTripHistorySection } from './DriverTripHistorySection';

interface DriverDetail {
  id: string;
  driverId: string;
  fullName: string;
  mobileNumber: string;
  plateNumber: string;
  dateOfBirth: string | null;
  photoUrl: string | null;
  licenseFrontUrl: string | null;
  licenseBackUrl: string | null;
  qrToken: string | null;
  isActive: boolean;
  reportCount: number;
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

/** Front/back license photo — unlike CommuterDetailPanel's read-only
 * PhotoTile (a commuter's own KYC submission, just displayed for review),
 * this one can upload/replace, since a driver has no self-serve doc
 * upload and an admin is the only way this ever gets populated. */
function LicensePhotoTile({
  label,
  url,
  field,
  driverId,
  onUploaded,
}: {
  label: string;
  url: string | null;
  field: 'licenseFront' | 'licenseBack';
  driverId: string;
  onUploaded: (url: string) => void;
}) {
  const inputId = `${field}-${driverId}`;
  const resolved = apiClient.resolveUrl(url);
  const [isUploading, setIsUploading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleFileChange(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file || isUploading) return;
    setError(null);
    setIsUploading(true);
    try {
      const res = await apiClient.uploadFiles<{ licenseFrontUrl: string | null; licenseBackUrl: string | null }>(
        `/api/admin/drivers/${driverId}/license`,
        { [field]: file },
      );
      const newUrl = field === 'licenseFront' ? res.licenseFrontUrl : res.licenseBackUrl;
      if (newUrl) onUploaded(newUrl);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Upload failed.');
    } finally {
      setIsUploading(false);
    }
  }

  return (
    <div>
      <div className="mb-1.5 flex items-center justify-between">
        <p className="text-xs font-semibold text-gray-600">{label}</p>
        <label
          htmlFor={inputId}
          className="cursor-pointer text-xs font-semibold text-brand-blue hover:underline"
        >
          {isUploading ? 'Uploading...' : resolved ? 'Replace' : 'Upload'}
        </label>
        <input
          id={inputId}
          type="file"
          accept="image/jpeg,image/png,image/webp"
          className="hidden"
          disabled={isUploading}
          onChange={handleFileChange}
        />
      </div>
      <div className="flex aspect-video items-center justify-center overflow-hidden rounded-lg border border-gray-200 bg-gray-50">
        {resolved ? (
          <img src={resolved} alt={label} className="h-full w-full object-contain" />
        ) : (
          <span className="text-xs text-gray-400">Not uploaded</span>
        )}
      </div>
      {error && <p className="mt-1 text-xs font-medium text-brand-red">{error}</p>}
    </div>
  );
}

function PlateNumberField({
  driverId,
  plateNumber,
  onChanged,
}: {
  driverId: string;
  plateNumber: string;
  onChanged: (plateNumber: string) => void;
}) {
  const [isEditing, setIsEditing] = useState(false);
  const [value, setValue] = useState(plateNumber);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  function startEditing() {
    setValue(plateNumber);
    setError(null);
    setIsEditing(true);
  }

  async function handleSave() {
    if (isSubmitting) return;
    setError(null);
    setIsSubmitting(true);
    try {
      const res = await apiClient.patch<{ driver: { plateNumber: string } }>(
        `/api/admin/drivers/${driverId}/plate-number`,
        { plateNumber: value },
      );
      onChanged(res.driver.plateNumber);
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
        <dt className="text-gray-500">Plate Number</dt>
        <dd className="flex items-center gap-1.5 font-medium text-gray-900">
          {plateNumber}
          <button
            onClick={startEditing}
            className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-brand-blue"
            aria-label="Edit plate number"
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
        <dt className="text-gray-500">Plate Number</dt>
        <div className="flex items-center gap-1.5">
          <input
            autoFocus
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="ABC123"
            className="w-28 rounded-lg border border-border-subtle px-2 py-1 text-right text-sm font-medium uppercase focus:border-brand-blue focus:outline-none"
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

export function DriverDetailPanel({
  driverId,
  onClose,
  onStatusChange,
}: {
  driverId: string;
  onClose: () => void;
  onStatusChange: (isActive: boolean) => void;
}) {
  const [driver, setDriver] = useState<DriverDetail | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  function fetchDriver() {
    apiClient
      .get<{ driver: DriverDetail }>(`/api/admin/drivers/${driverId}`)
      .then((res) => setDriver(res.driver))
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load this driver.'));
  }

  useEffect(() => {
    setDriver(null);
    fetchDriver();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [driverId]);

  // Keeps this panel current while it's open — a driver submitting an
  // explanation, or another admin reviewing a trip, should show up here
  // without having to close and reopen the panel.
  usePolling(fetchDriver, 8000);

  async function handleToggleStatus() {
    if (!driver || isSubmitting) return;
    setIsSubmitting(true);
    try {
      const nextActive = !driver.isActive;
      await apiClient.patch(`/api/admin/drivers/${driver.id}/status`, { isActive: nextActive });
      setDriver({ ...driver, isActive: nextActive });
      onStatusChange(nextActive);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex justify-end">
      <div className="absolute inset-0 bg-black/40" onClick={onClose} />
      <div className="relative flex h-full w-full max-w-md flex-col overflow-y-auto bg-white shadow-xl">
        <div className="flex items-center justify-between border-b border-border-subtle px-5 py-4">
          <h2 className="text-sm font-semibold text-gray-900">Driver Details</h2>
          <button onClick={onClose} className="rounded-lg p-1.5 text-gray-500 hover:bg-gray-100" aria-label="Close">
            <CloseIcon />
          </button>
        </div>

        {error && <p className="p-5 text-sm font-medium text-brand-red">{error}</p>}

        {!driver && !error && <p className="p-5 text-sm text-gray-500">Loading...</p>}

        {driver && (
          <div className="flex flex-1 flex-col gap-6 p-5">
            <div className="flex items-center gap-4">
              <div className="h-16 w-16 shrink-0 overflow-hidden rounded-full bg-gray-200">
                {driver.photoUrl && (
                  <img src={apiClient.resolveUrl(driver.photoUrl) ?? undefined} alt="" className="h-full w-full object-cover" />
                )}
              </div>
              <div>
                <p className="font-semibold text-gray-900">{driver.fullName}</p>
                <p className="text-xs text-gray-500">{driver.mobileNumber}</p>
                <span
                  className={`mt-1 inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${
                    driver.isActive ? 'bg-status-good-bg text-status-good' : 'bg-status-critical-bg text-status-critical'
                  }`}
                >
                  {driver.isActive ? 'Active' : 'Inactive'}
                </span>
              </div>
            </div>

            <div className="flex items-center justify-between rounded-xl border border-border-subtle p-4">
              <div>
                <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Report Count</p>
                <p className="mt-1 text-2xl font-semibold text-gray-900">{driver.reportCount}</p>
              </div>
              {driver.qrToken && (
                <div className="rounded-lg border border-border-subtle bg-white p-2">
                  <QRCodeSVG value={`MNBL-DRV:${driver.qrToken}`} size={72} />
                </div>
              )}
            </div>

            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">Driver Information</h3>
              <dl className="mt-2 space-y-2 text-sm">
                <div className="flex justify-between">
                  <dt className="text-gray-500">Driver ID</dt>
                  <dd className="font-medium text-gray-900">{driver.driverId}</dd>
                </div>
                <PlateNumberField
                  driverId={driver.id}
                  plateNumber={driver.plateNumber}
                  onChanged={(plateNumber) => setDriver({ ...driver, plateNumber })}
                />
                <div className="flex justify-between">
                  <dt className="text-gray-500">Date of Birth</dt>
                  <dd className="font-medium text-gray-900">{driver.dateOfBirth ?? '—'}</dd>
                </div>
                <div className="flex justify-between">
                  <dt className="text-gray-500">Date Registered</dt>
                  <dd className="font-medium text-gray-900">{formatManilaDate(driver.createdAt)}</dd>
                </div>
              </dl>
            </div>

            <div>
              <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">License Photos</h3>
              <div className="mt-2 grid grid-cols-2 gap-3">
                <LicensePhotoTile
                  label="License Front"
                  url={driver.licenseFrontUrl}
                  field="licenseFront"
                  driverId={driver.id}
                  onUploaded={(url) => setDriver({ ...driver, licenseFrontUrl: url })}
                />
                <LicensePhotoTile
                  label="License Back"
                  url={driver.licenseBackUrl}
                  field="licenseBack"
                  driverId={driver.id}
                  onUploaded={(url) => setDriver({ ...driver, licenseBackUrl: url })}
                />
              </div>
            </div>

            <DriverTripHistorySection driverId={driver.id} driverName={driver.fullName} plateNumber={driver.plateNumber} />

            <button
              onClick={handleToggleStatus}
              disabled={isSubmitting}
              className={`mt-auto w-full rounded-lg py-2.5 text-sm font-semibold transition disabled:opacity-60 ${
                driver.isActive
                  ? 'border border-status-critical text-status-critical hover:bg-status-critical-bg'
                  : 'bg-brand-blue text-white hover:brightness-110'
              }`}
            >
              {isSubmitting ? 'Please wait...' : driver.isActive ? 'Deactivate Driver' : 'Reactivate Driver'}
            </button>
          </div>
        )}
      </div>
    </div>
  );
}
