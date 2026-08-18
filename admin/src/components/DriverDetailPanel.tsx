import { useEffect, useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
import { apiClient, ApiError } from '../lib/apiClient';
import { formatManilaDate } from '../lib/formatDate';
import { formatPhone } from '../lib/formatPhone';
import { usePolling } from '../lib/usePolling';
import { DriverTripHistorySection } from './DriverTripHistorySection';
import { VerificationBadge, type VerificationStatus } from './VerificationBadge';

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
  licenseNumber: string | null;
  licenseVerificationStatus: VerificationStatus;
  qrToken: string | null;
  isActive: boolean;
  reportCount: number;
  /** This driver's live average across every commuter rating they've
   * received (see Rating's doc comment in schema.prisma) — null until
   * they have at least one. */
  averageRating: number | null;
  ratingCount: number;
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

/** Read-only license photo — uploading is the driver's own job now
 * (Settings -> License Number, see POST /driver/me/license-photo); an
 * admin only ever reviews what was submitted, same as CommuterDetailPanel's
 * PhotoTile for a commuter's KYC docs. */
function LicensePhotoView({ label, url }: { label: string; url: string | null }) {
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

/** Date of birth is no longer editable by the driver themselves (see
 * PATCH /driver/me) — only an admin can set/correct it, same
 * verified-by-a-human reasoning as plate/license number. Uses a native
 * `<input type="date">`, whose value format ("YYYY-MM-DD") already
 * matches what the backend's `dateOnly` schema expects/returns. */
function DateOfBirthField({
  driverId,
  dateOfBirth,
  onChanged,
}: {
  driverId: string;
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
      const res = await apiClient.patch<{ driver: { dateOfBirth: string | null } }>(
        `/api/admin/drivers/${driverId}/date-of-birth`,
        { dateOfBirth: value || null },
      );
      onChanged(res.driver.dateOfBirth);
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

/** Editable independently of the photo-review flow below (Approve/Reject
 * on a submitted photo also sets this, but an admin can correct it here
 * any time — e.g. fixing a typo from Add Driver, or before any photo's
 * even been submitted). Doesn't touch licenseVerificationStatus — see
 * PATCH /admin/drivers/:id/license-number's own doc comment for how it
 * tells the two kinds of update apart. */
function LicenseNumberField({
  driverId,
  licenseNumber,
  onChanged,
}: {
  driverId: string;
  licenseNumber: string | null;
  onChanged: (licenseNumber: string | null) => void;
}) {
  const [isEditing, setIsEditing] = useState(false);
  const [value, setValue] = useState(licenseNumber ?? '');
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  function startEditing() {
    setValue(licenseNumber ?? '');
    setError(null);
    setIsEditing(true);
  }

  async function handleSave() {
    if (isSubmitting) return;
    if (!value.trim()) {
      setError('License number is required.');
      return;
    }
    setError(null);
    setIsSubmitting(true);
    try {
      const res = await apiClient.patch<{ driver: { licenseNumber: string | null } }>(
        `/api/admin/drivers/${driverId}/license-number`,
        { licenseNumber: value.trim() },
      );
      onChanged(res.driver.licenseNumber);
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
        <dt className="text-gray-500">License Number</dt>
        <dd className="flex items-center gap-1.5 font-medium text-gray-900">
          {licenseNumber ?? '—'}
          <button
            onClick={startEditing}
            className="rounded p-1 text-gray-400 hover:bg-gray-100 hover:text-brand-blue"
            aria-label="Edit license number"
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
        <dt className="text-gray-500">License Number</dt>
        <div className="flex items-center gap-1.5">
          <input
            autoFocus
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder="N01-23-456789"
            className="w-36 rounded-lg border border-border-subtle px-2 py-1 text-right text-sm font-medium focus:border-brand-blue focus:outline-none"
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
  const [licenseNumberInput, setLicenseNumberInput] = useState('');
  const [licenseActionError, setLicenseActionError] = useState<string | null>(null);
  const [isSubmittingLicense, setIsSubmittingLicense] = useState(false);

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

  // Seeds the input from whatever's already on file (e.g. re-reviewing
  // after a rejection) — only once per driver load, not on every poll,
  // so it doesn't stomp on an admin mid-edit.
  useEffect(() => {
    if (driver) setLicenseNumberInput(driver.licenseNumber ?? '');
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [driverId, driver === null]);

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

  // The admin types the number in themselves after looking at the
  // submitted photo — no OCR/auto-detect (see TODO.md).
  async function handleLicenseReview(status: 'APPROVED' | 'REJECTED') {
    if (!driver || isSubmittingLicense) return;
    if (status === 'APPROVED' && !licenseNumberInput.trim()) {
      setLicenseActionError('Enter the license number before approving.');
      return;
    }
    setLicenseActionError(null);
    setIsSubmittingLicense(true);
    try {
      const res = await apiClient.patch<{ driver: { licenseNumber: string | null; licenseVerificationStatus: VerificationStatus } }>(
        `/api/admin/drivers/${driver.id}/license-number`,
        { status, licenseNumber: licenseNumberInput.trim() || undefined },
      );
      setDriver({
        ...driver,
        licenseNumber: res.driver.licenseNumber,
        licenseVerificationStatus: res.driver.licenseVerificationStatus,
      });
    } catch (err) {
      setLicenseActionError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setIsSubmittingLicense(false);
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
                <p className="text-xs text-gray-500">{formatPhone(driver.mobileNumber)}</p>
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
              <div className="flex gap-6">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Rating</p>
                  <p className="mt-1 flex items-baseline gap-1 text-2xl font-semibold text-gray-900">
                    {driver.averageRating != null ? driver.averageRating.toFixed(1) : '—'}
                    {driver.averageRating != null && <span className="text-sm font-medium text-gray-400">/5</span>}
                  </p>
                  <p className="text-xs text-gray-400">
                    {driver.ratingCount > 0 ? `${driver.ratingCount} rating${driver.ratingCount === 1 ? '' : 's'}` : 'No ratings yet'}
                  </p>
                </div>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-wide text-gray-400">Report Count</p>
                  <p className="mt-1 text-2xl font-semibold text-gray-900">{driver.reportCount}</p>
                </div>
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
                <LicenseNumberField
                  driverId={driver.id}
                  licenseNumber={driver.licenseNumber}
                  onChanged={(licenseNumber) => setDriver({ ...driver, licenseNumber })}
                />
                <DateOfBirthField
                  driverId={driver.id}
                  dateOfBirth={driver.dateOfBirth}
                  onChanged={(dateOfBirth) => setDriver({ ...driver, dateOfBirth })}
                />
                <div className="flex justify-between">
                  <dt className="text-gray-500">Date Registered</dt>
                  <dd className="font-medium text-gray-900">{formatManilaDate(driver.createdAt)}</dd>
                </div>
              </dl>
            </div>

            <div>
              <div className="flex items-center justify-between">
                <h3 className="text-xs font-semibold uppercase tracking-wide text-gray-400">License Photos</h3>
                <VerificationBadge status={driver.licenseVerificationStatus} notSubmitted={!driver.licenseFrontUrl} />
              </div>
              <div className="mt-2 grid grid-cols-2 gap-3">
                <LicensePhotoView label="License Front" url={driver.licenseFrontUrl} />
                <LicensePhotoView label="License Back" url={driver.licenseBackUrl} />
              </div>

              {driver.licenseFrontUrl && (
                <div className="mt-3">
                  <p className="mb-1.5 text-xs font-semibold text-gray-600">License Number</p>
                  <div className="flex gap-1.5">
                    <input
                      type="text"
                      value={licenseNumberInput}
                      onChange={(e) => setLicenseNumberInput(e.target.value)}
                      placeholder="Type the number from the photo"
                      className="flex-1 rounded-lg border border-gray-200 px-2.5 py-1.5 text-sm focus:border-brand-blue focus:outline-none"
                    />
                    <button
                      onClick={() => handleLicenseReview('REJECTED')}
                      disabled={isSubmittingLicense || driver.licenseVerificationStatus === 'REJECTED'}
                      className="rounded-lg border border-status-critical px-2.5 py-1 text-xs font-semibold text-status-critical hover:bg-status-critical-bg disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      Reject
                    </button>
                    <button
                      onClick={() => handleLicenseReview('APPROVED')}
                      disabled={isSubmittingLicense || driver.licenseVerificationStatus === 'APPROVED'}
                      className="rounded-lg bg-brand-blue px-2.5 py-1 text-xs font-semibold text-white hover:brightness-110 disabled:cursor-not-allowed disabled:opacity-50"
                    >
                      Approve
                    </button>
                  </div>
                  {licenseActionError && <p className="mt-1.5 text-xs font-medium text-brand-red">{licenseActionError}</p>}
                </div>
              )}
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
