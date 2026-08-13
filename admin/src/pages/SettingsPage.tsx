import { useState, type FormEvent } from 'react';
import { DashboardLayout } from '../components/DashboardLayout';
import { useAuth } from '../lib/auth';
import { apiClient, ApiError } from '../lib/apiClient';

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
    <div className="rounded-xl border border-border-subtle bg-surface-card p-5 shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
      <h2 className="text-sm font-semibold text-gray-900">Profile</h2>
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
    </div>
  );
}

function PasswordSection() {
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
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
    <div className="mt-6 rounded-xl border border-border-subtle bg-surface-card p-5 shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
      <h2 className="text-sm font-semibold text-gray-900">Change Password</h2>
      <form onSubmit={handleSubmit} className="mt-4 max-w-sm space-y-4">
        <div>
          <label className="block text-sm font-medium text-gray-700" htmlFor="currentPassword">
            Current Password
          </label>
          <input
            id="currentPassword"
            type="password"
            required
            autoComplete="current-password"
            value={currentPassword}
            onChange={(e) => setCurrentPassword(e.target.value)}
            className="mt-1.5 w-full rounded-lg border border-border-subtle px-3 py-2.5 text-sm focus:border-brand-blue focus:outline-none"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700" htmlFor="newPassword">
            New Password
          </label>
          <input
            id="newPassword"
            type="password"
            required
            minLength={8}
            autoComplete="new-password"
            value={newPassword}
            onChange={(e) => setNewPassword(e.target.value)}
            className="mt-1.5 w-full rounded-lg border border-border-subtle px-3 py-2.5 text-sm focus:border-brand-blue focus:outline-none"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-gray-700" htmlFor="confirmPassword">
            Confirm New Password
          </label>
          <input
            id="confirmPassword"
            type="password"
            required
            minLength={8}
            autoComplete="new-password"
            value={confirmPassword}
            onChange={(e) => setConfirmPassword(e.target.value)}
            className="mt-1.5 w-full rounded-lg border border-border-subtle px-3 py-2.5 text-sm focus:border-brand-blue focus:outline-none"
          />
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
    </div>
  );
}

export default function SettingsPage() {
  return (
    <DashboardLayout>
      <h1 className="text-2xl font-semibold tracking-tight text-gray-900">Settings</h1>
      <p className="mt-1 text-sm text-gray-500">Manage your admin account.</p>

      <div className="mt-6">
        <ProfileSection />
        <PasswordSection />
      </div>
    </DashboardLayout>
  );
}
