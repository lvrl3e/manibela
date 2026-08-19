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

function JeepneyIcon({ className }: { className?: string }) {
  return (
    <svg width="20" height="12" viewBox="0 0 28 16" fill="none" className={className}>
      <path
        d="M2 11.5V7.8c0-.6.4-1.1 1-1.3l3-1c.3-.1.6-.2 1-.2h11.5c.5 0 1 .2 1.3.6l2.4 2.7c.3.3.7.5 1.1.5H26c.6 0 1 .4 1 1v1.4"
        fill="currentColor"
        fillOpacity="0.18"
        stroke="currentColor"
        strokeWidth="1.3"
        strokeLinejoin="round"
      />
      <path d="M8.5 5.6v3.7M17 5.6v3.7" stroke="currentColor" strokeWidth="1" strokeOpacity="0.6" />
      <circle cx="7.5" cy="12" r="1.7" fill="#0a0f2c" stroke="currentColor" strokeWidth="1.2" />
      <circle cx="21" cy="12" r="1.7" fill="#0a0f2c" stroke="currentColor" strokeWidth="1.2" />
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
      <div className="relative hidden w-[45%] flex-col overflow-hidden bg-gradient-to-br from-ink to-black md:flex">
        <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_50%_38%,rgba(11,87,208,0.45),transparent_62%)]" />

        {/* City backdrop — fills the whole panel, not just a band at the
            bottom, so the navy gradient doesn't sit empty above it. Two
            depth layers: a dim, dense skyline reaching near the top, and
            a brighter, twinkling near skyline in front of it. Translucent
            fills throughout (no opaque fade layer) so both blend into the
            gradient behind them instead of showing a hard container edge. */}
        <div className="pointer-events-none absolute inset-0 z-0">
          {/* Distant skyline — thin, dense, dim, no windows */}
          <div className="absolute inset-x-0 bottom-0 flex h-[92%] items-end justify-between opacity-60">
            {[
              160, 260, 120, 340, 190, 420, 150, 300, 220, 460, 170, 250, 380, 140, 320, 200, 440, 160, 280, 230, 400,
              180, 260, 150,
            ].map((h, i) => (
              <div key={i} className="w-5 rounded-t-[1px] bg-white/10" style={{ height: h }} />
            ))}
          </div>

          {/* Near skyline — the original row, brighter, with twinkling windows */}
          <div className="absolute inset-x-0 bottom-0 flex h-[70%] items-end justify-between px-2">
            {[80, 130, 70, 190, 100, 230, 90, 160, 110, 210, 95, 145, 75].map((h, i) => (
              <div key={i} className="relative w-9 rounded-t-[2px] bg-white/20" style={{ height: h }}>
                {h > 100 && (
                  <div className="absolute inset-x-1.5 top-3 grid grid-cols-2 gap-1.5">
                    {Array.from({ length: Math.floor((h - 40) / 14) }).map((_, w) => (
                      <span
                        key={w}
                        className="h-1 w-1 rounded-full bg-brand-yellow/80 animate-twinkle"
                        style={{ animationDelay: `${((i * 7 + w * 3) % 16) * 0.2}s` }}
                      />
                    ))}
                  </div>
                )}
              </div>
            ))}
          </div>
          <div className="absolute inset-x-0 bottom-0 h-1 bg-brand-blue" />
        </div>

        {/* Brand block — cascades in, logo first, so it isn't perfectly
            static next to the animated form on the right. */}
        <div className="relative z-10 flex flex-1 flex-col items-center justify-center gap-6 px-10">
          <div className="animate-form-rise">
            <LogoMark size={220} />
          </div>
          <div className="animate-form-rise flex flex-col items-center gap-6" style={{ animationDelay: '0.12s' }}>
            <p className="text-sm font-medium text-white/60">Admin Portal</p>
            <p className="max-w-[280px] text-center text-sm leading-relaxed text-white/45">
              Fleet oversight, trip review, and rider support for the Pasig&ndash;Quiapo jeepney line.
            </p>
          </div>

          <div
            className="animate-form-rise mt-2 flex items-center gap-3 font-mono text-[11px] font-semibold uppercase tracking-widest text-white/35"
            style={{ animationDelay: '0.24s' }}
          >
            <span>Pasig</span>
            <span className="relative h-px w-20 bg-white/20">
              <JeepneyIcon className="animate-jeepney-drive absolute -top-[6px] left-0 text-brand-yellow" />
            </span>
            <span>Quiapo</span>
          </div>
        </div>
      </div>

      {/* Right panel */}
      <div className="relative flex flex-1 flex-col overflow-hidden bg-white px-6">
        {/* Faint corner glow, echoing the left panel's radial glow so the
            two sides read as one page instead of two unrelated halves. */}
        <div className="pointer-events-none absolute -top-24 -right-24 h-96 w-96 rounded-full bg-[radial-gradient(circle,rgba(11,87,208,0.08),transparent_70%)]" />
        {/* Barely-there dot grid watermark — texture, not decoration. */}
        <div
          className="pointer-events-none absolute inset-0 opacity-[0.05]"
          style={{
            backgroundImage: 'radial-gradient(circle, #0b57d0 1px, transparent 1px)',
            backgroundSize: '28px 28px',
          }}
        />

        <div className="relative flex flex-1 items-center justify-center py-16">
          <form onSubmit={handleSubmit} className="w-full max-w-sm animate-form-rise">
            <div className="mb-8 flex justify-center md:hidden">
              <LogoMark size={64} />
            </div>

            <h1 className="font-display text-center text-3xl font-extrabold text-gray-900">Welcome back</h1>
            <p className="mt-2 text-center text-sm text-gray-500">Sign in to the Manibela App admin portal</p>

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

        <p className="relative pb-6 text-center text-xs text-gray-400">
          &copy; 2026 Manibela App <span className="text-gray-300">&middot;</span> v1.0 &middot; Internal Use Only
        </p>
      </div>
    </div>
  );
}
