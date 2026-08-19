import { useEffect, useState, type FormEvent } from 'react';
import { DashboardLayout } from '../components/DashboardLayout';
import { EyeIcon } from '../components/EyeIcon';
import { Card, SectionHeader } from '../components/Card';
import { useAuth, type AdminRole } from '../lib/auth';
import { apiClient, ApiError } from '../lib/apiClient';
import { usePolling } from '../lib/usePolling';
import { formatManilaDate, formatManilaDateTime } from '../lib/formatDate';

function UserIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <circle cx="12" cy="8" r="3.5" />
      <path d="M4.5 20c0-4.1 3.4-7 7.5-7s7.5 2.9 7.5 7" strokeLinecap="round" />
    </svg>
  );
}

function LockIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <rect x="4.5" y="10.5" width="15" height="10" rx="2" />
      <path d="M7.5 10.5V7a4.5 4.5 0 0 1 9 0v3.5" />
    </svg>
  );
}

function TeamIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
      <circle cx="9" cy="8" r="3" />
      <path d="M3 19c0-3.3 2.7-5.5 6-5.5s6 2.2 6 5.5" strokeLinecap="round" />
      <circle cx="17" cy="8.5" r="2.4" />
      <path d="M15.5 13.3c2.6.4 4.2 2.3 4.2 5.7" strokeLinecap="round" />
    </svg>
  );
}

function ProfileSection() {
  const { admin, refreshAdmin } = useAuth();
  const [fullName, setFullName] = useState(admin?.fullName ?? '');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (isSubmitting) return;
    setError(null);
    setSaved(false);
    setIsSubmitting(true);
    try {
      await apiClient.patch('/api/admin/me', { fullName });
      await refreshAdmin();
      setSaved(true);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <Card>
      <SectionHeader icon={<UserIcon />} title="Profile" />
      <form onSubmit={handleSubmit} className="mt-4 max-w-sm space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700">Email</label>
          <p className="mt-1.5 rounded-lg border border-border-subtle bg-gray-50 px-3 py-2.5 text-sm text-gray-500">
            {admin?.email}
          </p>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700" htmlFor="fullName">
            Full Name
          </label>
          <input
            id="fullName"
            required
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
            className="mt-1.5 w-full rounded-lg border border-border-subtle px-3 py-2.5 text-sm focus:border-brand-blue focus:outline-none"
          />
        </div>

        {error && <p className="text-sm font-medium text-brand-red">{error}</p>}
        {saved && <p className="text-sm font-medium text-status-good">Saved.</p>}

        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110 disabled:opacity-60"
        >
          {isSubmitting ? 'Saving...' : 'Save Changes'}
        </button>
      </form>
    </Card>
  );
}

function PasswordSection() {
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showCurrentPassword, setShowCurrentPassword] = useState(false);
  const [showNewPassword, setShowNewPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [saved, setSaved] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (isSubmitting) return;

    if (newPassword !== confirmPassword) {
      setError('New passwords do not match.');
      return;
    }

    setError(null);
    setSaved(false);
    setIsSubmitting(true);
    try {
      await apiClient.patch('/api/admin/me/password', { currentPassword, newPassword });
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
      setSaved(true);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <Card className="mt-6">
      <SectionHeader icon={<LockIcon />} title="Change Password" />
      <form onSubmit={handleSubmit} className="mt-4 max-w-sm space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700" htmlFor="currentPassword">
            Current Password
          </label>
          <div className="relative mt-1.5">
            <input
              id="currentPassword"
              type={showCurrentPassword ? 'text' : 'password'}
              required
              autoComplete="current-password"
              value={currentPassword}
              onChange={(e) => setCurrentPassword(e.target.value)}
              className="w-full rounded-lg border border-border-subtle px-3 py-2.5 pr-10 text-sm focus:border-brand-blue focus:outline-none"
            />
            <button
              type="button"
              onClick={() => setShowCurrentPassword((v) => !v)}
              className="absolute inset-y-0 right-3 flex items-center text-gray-400 hover:text-gray-600"
              aria-label={showCurrentPassword ? 'Hide password' : 'Show password'}
            >
              <EyeIcon open={showCurrentPassword} />
            </button>
          </div>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700" htmlFor="newPassword">
            New Password
          </label>
          <div className="relative mt-1.5">
            <input
              id="newPassword"
              type={showNewPassword ? 'text' : 'password'}
              required
              minLength={8}
              autoComplete="new-password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              className="w-full rounded-lg border border-border-subtle px-3 py-2.5 pr-10 text-sm focus:border-brand-blue focus:outline-none"
            />
            <button
              type="button"
              onClick={() => setShowNewPassword((v) => !v)}
              className="absolute inset-y-0 right-3 flex items-center text-gray-400 hover:text-gray-600"
              aria-label={showNewPassword ? 'Hide password' : 'Show password'}
            >
              <EyeIcon open={showNewPassword} />
            </button>
          </div>
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700" htmlFor="confirmPassword">
            Confirm New Password
          </label>
          <div className="relative mt-1.5">
            <input
              id="confirmPassword"
              type={showConfirmPassword ? 'text' : 'password'}
              required
              minLength={8}
              autoComplete="new-password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className="w-full rounded-lg border border-border-subtle px-3 py-2.5 pr-10 text-sm focus:border-brand-blue focus:outline-none"
            />
            <button
              type="button"
              onClick={() => setShowConfirmPassword((v) => !v)}
              className="absolute inset-y-0 right-3 flex items-center text-gray-400 hover:text-gray-600"
              aria-label={showConfirmPassword ? 'Hide password' : 'Show password'}
            >
              <EyeIcon open={showConfirmPassword} />
            </button>
          </div>
        </div>

        {error && <p className="text-sm font-medium text-brand-red">{error}</p>}
        {saved && <p className="text-sm font-medium text-status-good">Password updated.</p>}

        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110 disabled:opacity-60"
        >
          {isSubmitting ? 'Updating...' : 'Update Password'}
        </button>
      </form>
    </Card>
  );
}

interface AdminAccount {
  id: string;
  fullName: string;
  email: string;
  role: AdminRole;
  isActive: boolean;
  createdAt: string;
  lastLoginAt: string | null;
}

function RoleBadge({ role }: { role: AdminRole }) {
  const isMain = role === 'MAIN_ADMIN';
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${
        isMain ? 'bg-brand-blue/10 text-brand-blue' : 'bg-gray-100 text-gray-600'
      }`}
    >
      {isMain ? 'Main Admin' : 'Admin'}
    </span>
  );
}

function StatusBadge({ isActive }: { isActive: boolean }) {
  return (
    <span
      className={`inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-semibold ${
        isActive ? 'bg-status-good-bg text-status-good' : 'bg-status-critical-bg text-status-critical'
      }`}
    >
      {isActive ? 'Active' : 'Inactive'}
    </span>
  );
}

/** Only ever rendered for the Main Admin — the backend enforces this
 * independently (requireMainAdmin on every mutating /admins endpoint), so
 * this hiding is a UX nicety, not the actual access control. */
function CreateAdminForm({ onCreated, onCancel }: { onCreated: () => void; onCancel: () => void }) {
  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (isSubmitting) return;
    setError(null);
    setIsSubmitting(true);
    try {
      await apiClient.post('/api/admin/admins', { fullName, email, password });
      onCreated();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} className="mt-4 max-w-sm space-y-4 rounded-lg border border-border-subtle bg-gray-50 p-4">
      <div>
        <label className="block text-sm font-medium text-gray-700" htmlFor="newAdminFullName">
          Full Name
        </label>
        <input
          id="newAdminFullName"
          required
          value={fullName}
          onChange={(e) => setFullName(e.target.value)}
          className="mt-1.5 w-full rounded-lg border border-border-subtle bg-white px-3 py-2.5 text-sm focus:border-brand-blue focus:outline-none"
        />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700" htmlFor="newAdminEmail">
          Email
        </label>
        <input
          id="newAdminEmail"
          type="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          className="mt-1.5 w-full rounded-lg border border-border-subtle bg-white px-3 py-2.5 text-sm focus:border-brand-blue focus:outline-none"
        />
      </div>
      <div>
        <label className="block text-sm font-medium text-gray-700" htmlFor="newAdminPassword">
          Temporary Password
        </label>
        <div className="relative mt-1.5">
          <input
            id="newAdminPassword"
            type={showPassword ? 'text' : 'password'}
            required
            minLength={8}
            autoComplete="new-password"
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            placeholder="At least 8 characters"
            className="w-full rounded-lg border border-border-subtle bg-white px-3 py-2.5 pr-10 text-sm focus:border-brand-blue focus:outline-none"
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

      <div className="flex gap-2">
        <button
          type="submit"
          disabled={isSubmitting}
          className="rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110 disabled:opacity-60"
        >
          {isSubmitting ? 'Creating...' : 'Create Admin'}
        </button>
        <button
          type="button"
          onClick={onCancel}
          className="rounded-lg border border-border-subtle px-4 py-2.5 text-sm font-semibold text-gray-600 hover:bg-gray-100"
        >
          Cancel
        </button>
      </div>
    </form>
  );
}

/** With only ADMIN/MAIN_ADMIN existing today and the Main Admin role
 * permanently locked (see PATCH /admins/:id/role), this has nowhere real
 * to send a regular admin's role yet — it still round-trips through the
 * real, backend-enforced endpoint rather than being purely decorative, so
 * it's ready the moment a third role exists. */
function EditRoleModal({ target, onClose, onDone }: { target: AdminAccount; onClose: () => void; onDone: () => void }) {
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSave() {
    if (isSubmitting) return;
    setError(null);
    setIsSubmitting(true);
    try {
      await apiClient.patch(`/api/admin/admins/${target.id}/role`, { role: 'ADMIN' });
      onDone();
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-black/50" onClick={onClose} />
      <div className="relative w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl">
        <h2 className="font-display text-base font-semibold text-gray-900">Edit Role</h2>
        <p className="mt-1 text-sm text-gray-500">{target.fullName}</p>
        <div className="mt-4">
          <label className="block text-sm font-medium text-gray-700">Role</label>
          <select
            disabled
            value="ADMIN"
            className="mt-1.5 w-full rounded-lg border border-border-subtle bg-gray-50 px-3 py-2.5 text-sm text-gray-500"
          >
            <option value="ADMIN">Admin</option>
          </select>
          <p className="mt-1.5 text-xs text-gray-400">
            Admin is the only assignable role right now — the Main Admin role can't be reassigned.
          </p>
        </div>
        {error && <p className="mt-3 text-sm font-medium text-brand-red">{error}</p>}
        <div className="mt-4 flex gap-2">
          <button
            onClick={handleSave}
            disabled={isSubmitting}
            className="flex-1 rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110 disabled:opacity-60"
          >
            {isSubmitting ? 'Saving...' : 'Save'}
          </button>
          <button
            onClick={onClose}
            className="flex-1 rounded-lg border border-border-subtle px-4 py-2.5 text-sm font-semibold text-gray-600 hover:bg-gray-50"
          >
            Cancel
          </button>
        </div>
      </div>
    </div>
  );
}

function ResetPasswordModal({ target, onClose, onDone }: { target: AdminAccount; onClose: () => void; onDone: () => void }) {
  const [newPassword, setNewPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [done, setDone] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (isSubmitting) return;
    setError(null);
    setIsSubmitting(true);
    try {
      await apiClient.post(`/api/admin/admins/${target.id}/reset-password`, { newPassword });
      setDone(true);
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4">
      <div className="absolute inset-0 bg-black/50" onClick={done ? onDone : onClose} />
      <div className="relative w-full max-w-sm rounded-2xl bg-white p-6 shadow-xl">
        <h2 className="font-display text-base font-semibold text-gray-900">Reset Password</h2>
        <p className="mt-1 text-sm text-gray-500">Set a new password for {target.fullName}.</p>

        {done ? (
          <>
            <p className="mt-4 text-sm font-medium text-status-good">
              Password reset. Share the new password with {target.fullName} directly.
            </p>
            <button
              onClick={onDone}
              className="mt-4 w-full rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110"
            >
              Done
            </button>
          </>
        ) : (
          <form onSubmit={handleSubmit} className="mt-4 space-y-4">
            <div>
              <label className="block text-sm font-medium text-gray-700" htmlFor="resetPassword">
                New Password
              </label>
              <div className="relative mt-1.5">
                <input
                  id="resetPassword"
                  type={showPassword ? 'text' : 'password'}
                  required
                  minLength={8}
                  autoComplete="new-password"
                  value={newPassword}
                  onChange={(e) => setNewPassword(e.target.value)}
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
            <div className="flex gap-2">
              <button
                type="submit"
                disabled={isSubmitting}
                className="flex-1 rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110 disabled:opacity-60"
              >
                {isSubmitting ? 'Resetting...' : 'Reset Password'}
              </button>
              <button
                type="button"
                onClick={onClose}
                className="flex-1 rounded-lg border border-border-subtle px-4 py-2.5 text-sm font-semibold text-gray-600 hover:bg-gray-50"
              >
                Cancel
              </button>
            </div>
          </form>
        )}
      </div>
    </div>
  );
}

/** Visible to every admin (read-only context for a regular ADMIN) — only
 * the Create Admin button and the per-row action buttons are gated to the
 * Main Admin. That gating is UX only; the backend independently enforces
 * every one of these via requireMainAdmin, so a regular admin calling the
 * same endpoints directly gets a 403 regardless of what this page shows
 * them. */
function AdminAccountsSection() {
  const { admin: currentAdmin } = useAuth();
  const isMainAdmin = currentAdmin?.role === 'MAIN_ADMIN';

  const [admins, setAdmins] = useState<AdminAccount[] | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [actionError, setActionError] = useState<string | null>(null);
  const [showCreateForm, setShowCreateForm] = useState(false);
  const [editRoleTarget, setEditRoleTarget] = useState<AdminAccount | null>(null);
  const [resetPasswordTarget, setResetPasswordTarget] = useState<AdminAccount | null>(null);
  const [togglingId, setTogglingId] = useState<string | null>(null);

  function fetchAdmins() {
    apiClient
      .get<{ admins: AdminAccount[] }>('/api/admin/admins')
      .then((res) => {
        setAdmins(res.admins);
        setError(null);
      })
      .catch((err) => setError(err instanceof ApiError ? err.message : 'Could not load admin accounts.'));
  }

  useEffect(fetchAdmins, []);
  usePolling(fetchAdmins, 15_000);

  async function handleToggleStatus(target: AdminAccount) {
    if (togglingId) return;
    setActionError(null);
    setTogglingId(target.id);
    try {
      await apiClient.patch(`/api/admin/admins/${target.id}/status`, { isActive: !target.isActive });
      fetchAdmins();
    } catch (err) {
      setActionError(err instanceof ApiError ? err.message : 'Something went wrong.');
    } finally {
      setTogglingId(null);
    }
  }

  return (
    <Card className="mt-6">
      <SectionHeader
        icon={<TeamIcon />}
        title="Admin Accounts"
        action={
          isMainAdmin && (
            <button
              onClick={() => setShowCreateForm((v) => !v)}
              className="rounded-lg bg-brand-blue px-4 py-2.5 text-sm font-semibold text-white transition hover:brightness-110"
            >
              {showCreateForm ? 'Cancel' : 'Create Admin'}
            </button>
          )
        }
      />
      <p className="mt-1 pl-9 text-sm text-gray-500">
        {isMainAdmin ? 'Manage who has access to this dashboard.' : 'Everyone with access to this dashboard.'}
      </p>

      {showCreateForm && isMainAdmin && (
        <CreateAdminForm
          onCreated={() => {
            setShowCreateForm(false);
            fetchAdmins();
          }}
          onCancel={() => setShowCreateForm(false)}
        />
      )}

      {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}
      {actionError && <p className="mt-4 text-sm font-medium text-brand-red">{actionError}</p>}
      {!admins && !error && (
        <div className="mt-4 divide-y divide-gray-100 overflow-hidden rounded-lg border border-border-subtle">
          <div className="h-10 bg-gray-50" />
          {Array.from({ length: 3 }).map((_, i) => (
            <div key={i} className="flex items-center gap-6 px-4 py-3">
              {Array.from({ length: 5 }).map((_, c) => (
                <div key={c} className="h-3.5 flex-1 animate-pulse rounded bg-gray-100" />
              ))}
            </div>
          ))}
        </div>
      )}

      {admins && (
        <div className="mt-4 overflow-x-auto rounded-lg border border-border-subtle">
          <table className="w-full min-w-[760px] text-left text-sm">
            <thead className="bg-gray-50 text-xs font-semibold uppercase tracking-wide text-gray-500">
              <tr>
                <th className="px-4 py-3">Name</th>
                <th className="px-4 py-3">Email</th>
                <th className="px-4 py-3">Role</th>
                <th className="px-4 py-3">Account Status</th>
                <th className="px-4 py-3">Date Created</th>
                <th className="px-4 py-3">Last Login</th>
                {isMainAdmin && <th className="px-4 py-3">Actions</th>}
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {admins.map((a) => (
                <tr key={a.id} className="hover:bg-gray-50">
                  <td className="px-4 py-3 font-medium text-gray-900">
                    {a.fullName}
                    {a.id === currentAdmin?.id && <span className="ml-1.5 text-xs font-normal text-gray-400">(You)</span>}
                  </td>
                  <td className="px-4 py-3 text-gray-600">{a.email}</td>
                  <td className="px-4 py-3">
                    <RoleBadge role={a.role} />
                  </td>
                  <td className="px-4 py-3">
                    <StatusBadge isActive={a.isActive} />
                  </td>
                  <td className="px-4 py-3 text-gray-600">{formatManilaDate(a.createdAt)}</td>
                  <td className="px-4 py-3 text-gray-600">{a.lastLoginAt ? formatManilaDateTime(a.lastLoginAt) : 'Never'}</td>
                  {isMainAdmin && (
                    <td className="px-4 py-3">
                      {a.role === 'MAIN_ADMIN' ? (
                        <span className="text-xs text-gray-400">—</span>
                      ) : (
                        <div className="flex flex-wrap gap-1.5">
                          <button
                            onClick={() => setEditRoleTarget(a)}
                            className="rounded-lg border border-border-subtle px-2.5 py-1 text-xs font-semibold text-gray-600 hover:bg-gray-50"
                          >
                            Edit Role
                          </button>
                          <button
                            onClick={() => setResetPasswordTarget(a)}
                            className="rounded-lg border border-border-subtle px-2.5 py-1 text-xs font-semibold text-gray-600 hover:bg-gray-50"
                          >
                            Reset Password
                          </button>
                          <button
                            onClick={() => handleToggleStatus(a)}
                            disabled={togglingId === a.id}
                            className={`rounded-lg border px-2.5 py-1 text-xs font-semibold transition disabled:cursor-not-allowed disabled:opacity-50 ${
                              a.isActive
                                ? 'border-status-critical text-status-critical hover:bg-status-critical-bg'
                                : 'border-status-good text-status-good hover:bg-status-good-bg'
                            }`}
                          >
                            {togglingId === a.id ? '...' : a.isActive ? 'Deactivate' : 'Reactivate'}
                          </button>
                        </div>
                      )}
                    </td>
                  )}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {editRoleTarget && (
        <EditRoleModal
          target={editRoleTarget}
          onClose={() => setEditRoleTarget(null)}
          onDone={() => {
            setEditRoleTarget(null);
            fetchAdmins();
          }}
        />
      )}
      {resetPasswordTarget && (
        <ResetPasswordModal
          target={resetPasswordTarget}
          onClose={() => setResetPasswordTarget(null)}
          onDone={() => setResetPasswordTarget(null)}
        />
      )}
    </Card>
  );
}

export default function SettingsPage() {
  return (
    <DashboardLayout title="Settings">
      <p className="text-sm text-gray-500">Manage your admin account.</p>

      <div className="mt-6">
        <ProfileSection />
        <PasswordSection />
        <AdminAccountsSection />
      </div>
    </DashboardLayout>
  );
}
