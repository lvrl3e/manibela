import type { ReactNode } from 'react';

function ArrowUpIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
      <path d="M12 19V5M5 12l7-7 7 7" />
    </svg>
  );
}

function ArrowDownIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3">
      <path d="M12 5v14M5 12l7 7 7-7" />
    </svg>
  );
}

// Outlined — a thin colored top border and an outline-ring icon are the
// only color on an otherwise plain white card; the value itself stays
// neutral black, matching every other number on the dashboard.
const TONE_STYLES = {
  blue: { top: 'bg-brand-blue', ring: 'border-blue-200 text-brand-blue', changeNeutral: 'bg-gray-100 text-gray-500' },
  warning: {
    top: 'bg-status-warning',
    ring: 'border-status-warning/40 text-status-warning',
    changeNeutral: 'bg-gray-100 text-gray-500',
  },
  good: {
    top: 'bg-status-good',
    ring: 'border-status-good/40 text-status-good',
    changeNeutral: 'bg-gray-100 text-gray-500',
  },
  critical: {
    top: 'bg-status-critical',
    ring: 'border-status-critical/40 text-status-critical',
    changeNeutral: 'bg-gray-100 text-gray-500',
  },
} as const;

export function StatCard({
  label,
  value,
  icon,
  /** Signed percent change vs. the prior period, or null if there's no
   * meaningful prior-period baseline (see percentChange() on the
   * backend). Up is always treated as "good" here — every metric on
   * this dashboard (accounts, submissions) is a count where growth is
   * the positive direction. */
  changePercent,
  changeLabel = 'vs last week',
  /** Accent color — blue (default) for neutral/informational counts;
   * warning for a count that means "needs attention" once it's nonzero;
   * good/critical for a count whose label already has an established
   * color elsewhere on the same page (e.g. an "Active"/"Inactive" or
   * "Online"/"Offline" badge in the table below it) — all reuse the same
   * status tokens as those badges, so a word means the same color
   * everywhere in the app instead of every count looking equally
   * neutral. */
  tone = 'blue',
}: {
  label: string;
  value: number | string;
  icon: ReactNode;
  changePercent?: number | null;
  changeLabel?: string;
  tone?: keyof typeof TONE_STYLES;
}) {
  const hasChange = changePercent !== undefined && changePercent !== null;
  const isUp = hasChange && changePercent! > 0;
  const isDown = hasChange && changePercent! < 0;
  const t = TONE_STYLES[tone];

  return (
    <div className="overflow-hidden rounded-xl border border-border-subtle bg-surface-card shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
      <div className={`h-[3px] w-full ${t.top}`} />
      <div className="p-5">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-sm font-medium text-gray-500">{label}</p>
            <p className="mt-1.5 font-display text-3xl font-semibold tracking-tight text-gray-900">{value}</p>
          </div>
          <div className={`flex h-9 w-9 shrink-0 items-center justify-center rounded-full border-2 ${t.ring}`}>
            {icon}
          </div>
        </div>

        {hasChange && (
          <div className="mt-3 flex items-center gap-1.5 text-xs">
            <span
              className={`inline-flex items-center gap-0.5 rounded-full px-1.5 py-0.5 font-semibold ${
                isUp
                  ? 'bg-status-good-bg text-status-good'
                  : isDown
                    ? 'bg-status-critical-bg text-status-critical'
                    : t.changeNeutral
              }`}
            >
              {isUp && <ArrowUpIcon />}
              {isDown && <ArrowDownIcon />}
              {Math.abs(changePercent!)}%
            </span>
            <span className="text-gray-400">{changeLabel}</span>
          </div>
        )}
      </div>
    </div>
  );
}
