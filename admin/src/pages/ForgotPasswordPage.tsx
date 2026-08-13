import { useState, type FormEvent } from 'react';
import { Link } from 'react-router-dom';
import { LogoMark } from '../components/Logo';
import { apiClient, ApiError } from '../lib/apiClient';

export default function ForgotPasswordPage() {
  const [email, setEmail] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sent, setSent] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (isSubmitting) return;

    setError(null);
    setIsSubmitting(true);
    try {
      await apiClient.post('/api/admin/forgot-password', { email });
      setSent(true);
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
          <h1 className="text-2xl font-extrabold text-gray-900">Forgot Password</h1>
          <p className="text-center text-sm text-gray-500">
            Enter the email on your admin account and we'll send a reset link.
          </p>
        </div>

        {sent ? (
          <div className="mt-8 rounded-xl border border-gray-200 bg-white p-5 text-center text-sm text-gray-700">
            If an account exists for <span className="font-semibold">{email}</span>, a reset link has been sent.
            <div className="mt-4">
              <Link to="/login" className="font-medium text-brand-blue hover:underline">
                Back to Sign In
              </Link>
            </div>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="mt-8">
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
              {isSubmitting ? 'Sending...' : 'Send Reset Link'}
            </button>

            <Link to="/login" className="mt-4 block text-center text-sm font-medium text-brand-blue hover:underline">
              Back to Sign In
            </Link>
          </form>
        )}
      </div>
    </div>
  );
}
