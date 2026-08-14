import { useState, type FormEvent } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { LogoMark } from '../components/Logo';
import { EyeIcon } from '../components/EyeIcon';
import { apiClient, ApiError } from '../lib/apiClient';

/** Step 1: request a code. Step 2: enter the code + a new password. Same
 * two-call shape as the commuter/driver forgot-password flow in the app
 * (issueOtp / verifyOtp), just collapsed into one screen instead of a
 * separate confirm-code step — there's less to gain from that extra
 * screen in a small internal admin tool. */
export default function ForgotPasswordPage() {
  const navigate = useNavigate();
  const [step, setStep] = useState<'email' | 'reset'>('email');

  const [email, setEmail] = useState('');
  const [code, setCode] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [showNewPassword, setShowNewPassword] = useState(false);
  const [showConfirmPassword, setShowConfirmPassword] = useState(false);

  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleRequestCode(e: FormEvent) {
    e.preventDefault();
    if (isSubmitting) return;

    setError(null);
    setIsSubmitting(true);
    try {
      await apiClient.post('/api/admin/forgot-password', { email });
      setStep('reset');
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  }

  async function handleResetPassword(e: FormEvent) {
    e.preventDefault();
    if (isSubmitting) return;

    if (newPassword !== confirmPassword) {
      setError('Passwords do not match.');
      return;
    }

    setError(null);
    setIsSubmitting(true);
    try {
      await apiClient.post('/api/admin/reset-password', { email, code, newPassword });
      navigate('/login', { replace: true });
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-50 px-6">
      <div className="w-full max-w-sm">
        <div className="flex flex-col items-center gap-3">
          <LogoMark size={72} />
          <h1 className="text-2xl font-extrabold text-gray-900">
            {step === 'email' ? 'Forgot Password' : 'Reset Password'}
          </h1>
          <p className="text-center text-sm text-gray-500">
            {step === 'email'
              ? "Enter the email on your admin account and we'll send a verification code."
              : `Enter the code sent for ${email} and choose a new password.`}
          </p>
        </div>

        {step === 'email' ? (
          <form onSubmit={handleRequestCode} className="mt-8">
            <label className="block text-sm font-semibold text-gray-800" htmlFor="email">
              Email Address
            </label>
            <input
              id="email"
              type="email"
              required
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="Enter your email..."
              className="mt-2 w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 text-sm text-gray-800 placeholder:text-gray-400 focus:outline-none"
            />

            {error && <p className="mt-3 text-sm font-medium text-brand-red">{error}</p>}

            <button
              type="submit"
              disabled={isSubmitting}
              className="mt-5 w-full rounded-xl bg-brand-blue py-3.5 text-sm font-bold text-white transition hover:brightness-110 disabled:opacity-60"
            >
              {isSubmitting ? 'Sending...' : 'Send Code'}
            </button>

            <Link to="/login" className="mt-4 block text-center text-sm font-medium text-brand-blue hover:underline">
              Back to Sign In
            </Link>
          </form>
        ) : (
          <form onSubmit={handleResetPassword} className="mt-8">
            <label className="block text-sm font-semibold text-gray-800" htmlFor="code">
              Verification Code
            </label>
            <input
              id="code"
              type="text"
              inputMode="numeric"
              required
              maxLength={6}
              autoComplete="one-time-code"
              value={code}
              onChange={(e) => setCode(e.target.value.replace(/\D/g, ''))}
              placeholder="6-digit code"
              className="mt-2 w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 text-sm tracking-[0.3em] text-gray-800 placeholder:tracking-normal placeholder:text-gray-400 focus:outline-none"
            />

            <label className="mt-5 block text-sm font-semibold text-gray-800" htmlFor="newPassword">
              New Password
            </label>
            <div className="relative mt-2">
              <input
                id="newPassword"
                type={showNewPassword ? 'text' : 'password'}
                required
                minLength={8}
                autoComplete="new-password"
                value={newPassword}
                onChange={(e) => setNewPassword(e.target.value)}
                placeholder="At least 8 characters"
                className="w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 pr-11 text-sm text-gray-800 placeholder:text-gray-400 focus:outline-none"
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

            <label className="mt-5 block text-sm font-semibold text-gray-800" htmlFor="confirmPassword">
              Confirm New Password
            </label>
            <div className="relative mt-2">
              <input
                id="confirmPassword"
                type={showConfirmPassword ? 'text' : 'password'}
                required
                minLength={8}
                autoComplete="new-password"
                value={confirmPassword}
                onChange={(e) => setConfirmPassword(e.target.value)}
                placeholder="Re-enter your new password"
                className="w-full rounded-xl border border-gray-200 bg-gray-50 px-4 py-3 pr-11 text-sm text-gray-800 placeholder:text-gray-400 focus:outline-none"
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

            {error && <p className="mt-3 text-sm font-medium text-brand-red">{error}</p>}

            <button
              type="submit"
              disabled={isSubmitting}
              className="mt-5 w-full rounded-xl bg-brand-blue py-3.5 text-sm font-bold text-white transition hover:brightness-110 disabled:opacity-60"
            >
              {isSubmitting ? 'Resetting...' : 'Reset Password'}
            </button>

            <button
              type="button"
              onClick={() => {
                setStep('email');
                setError(null);
                setCode('');
              }}
              className="mt-4 block w-full text-center text-sm font-medium text-brand-blue hover:underline"
            >
              Wrong email? Start over
            </button>
          </form>
        )}
      </div>
    </div>
  );
}
