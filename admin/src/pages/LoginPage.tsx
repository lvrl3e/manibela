import { useState, type FormEvent } from 'react';
import { Link, useLocation, useNavigate } from 'react-router-dom';
import { LogoMark } from '../components/Logo';
import { EyeIcon } from '../components/EyeIcon';
import { useAuth, ApiError } from '../lib/auth';

function MailIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="3" y="5" width="18" height="14" rx="2" />
      <path d="m3 7 9 6 9-6" />
    </svg>
  );
}

function LockIcon() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <rect x="4" y="11" width="16" height="9" rx="2" />
      <path d="M8 11V7a4 4 0 0 1 8 0v4" />
    </svg>
  );
}

function ArrowIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
      <path d="M5 12h14M13 6l6 6-6 6" />
    </svg>
  );
}

export default function LoginPage() {
  const { login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();

  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [rememberMe, setRememberMe] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [isSubmitting, setIsSubmitting] = useState(false);

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    if (isSubmitting) return;

    setError(null);
    setIsSubmitting(true);
    try {
      await login(email, password, rememberMe);
      const redirectTo = (location.state as { from?: Location })?.from?.pathname ?? '/';
      navigate(redirectTo, { replace: true });
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Something went wrong. Please try again.');
    } finally {
      setIsSubmitting(false);
    }
  }

  return (
    <div className="flex min-h-screen">
      {/* Left panel */}
      <div className="relative hidden w-[45%] flex-col items-center justify-center overflow-hidden bg-gradient-to-br from-ink to-black md:flex">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_38%,rgba(11,87,208,0.35),transparent_60%)]" />

        <div className="relative flex flex-col items-center gap-4">
          <LogoMark size={200} />
        </div>

        {/* City skyline silhouette */}
        <div className="absolute bottom-0 left-0 flex h-40 w-full items-end justify-center gap-3 opacity-40">
          {[60, 100, 70, 140, 90, 120, 65, 110, 75].map((h, i) => (
            <div key={i} className="w-10 rounded-t-sm bg-white/10" style={{ height: h }} />
          ))}
        </div>
        <div className="absolute bottom-0 left-0 h-1.5 w-full bg-brand-blue" />
      </div>

      {/* Right panel */}
      <div className="flex flex-1 items-center justify-center bg-white px-6 py-16">
        <form onSubmit={handleSubmit} className="w-full max-w-sm">
          <h1 className="text-center text-3xl font-extrabold text-gray-900">Admin</h1>
          <p className="mt-2 text-center text-sm text-gray-500">Sign in to your admin account</p>

          <label className="mt-8 block text-sm font-semibold text-gray-800" htmlFor="email">
            Email Address
          </label>
          <div className="mt-2 flex items-center gap-2 rounded-xl border border-gray-200 bg-gray-50 px-4 py-3">
            <span className="text-gray-400">
              <MailIcon />
            </span>
            <input
              id="email"
              type="email"
              required
              autoComplete="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="Enter your email..."
              className="w-full bg-transparent text-sm text-gray-800 placeholder:text-gray-400 focus:outline-none"
            />
          </div>

          <label className="mt-5 block text-sm font-semibold text-gray-800" htmlFor="password">
            Password
          </label>
          <div className="mt-2 flex items-center gap-2 rounded-xl border border-gray-200 bg-gray-50 px-4 py-3">
            <span className="text-gray-400">
              <LockIcon />
            </span>
            <input
              id="password"
              type={showPassword ? 'text' : 'password'}
              required
              autoComplete="current-password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Enter your password..."
              className="w-full bg-transparent text-sm text-gray-800 placeholder:text-gray-400 focus:outline-none"
            />
            <button
              type="button"
              onClick={() => setShowPassword((v) => !v)}
              className="text-gray-400 hover:text-gray-600"
              aria-label={showPassword ? 'Hide password' : 'Show password'}
            >
              <EyeIcon open={showPassword} />
            </button>
          </div>

          <div className="mt-4 flex items-center justify-between text-sm">
            <label className="flex items-center gap-2 text-gray-700">
              <input
                type="checkbox"
                checked={rememberMe}
                onChange={(e) => setRememberMe(e.target.checked)}
                className="h-4 w-4 rounded border-gray-300 accent-brand-blue"
              />
              Remember me
            </label>
            <Link to="/forgot-password" className="font-medium text-brand-blue hover:underline">
              Forgot Password?
            </Link>
          </div>

          {error && <p className="mt-4 text-sm font-medium text-brand-red">{error}</p>}

          <button
            type="submit"
            disabled={isSubmitting}
            className="mt-6 flex w-full items-center justify-center gap-2 rounded-xl bg-brand-blue py-3.5 text-sm font-bold text-white transition hover:brightness-110 disabled:opacity-60"
          >
            <ArrowIcon />
            {isSubmitting ? 'Signing in...' : 'Sign In'}
          </button>
        </form>
      </div>
    </div>
  );
}
