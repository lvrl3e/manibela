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
}: {
  label: string;
  value: number | string;
  icon: ReactNode;
  changePercent?: number | null;
  changeLabel?: string;
}) {
  const hasChange = changePercent !== undefined && changePercent !== null;
  const isUp = hasChange && changePercent! > 0;
  const isDown = hasChange && changePercent! < 0;

  return (
    <div className="rounded-xl border border-border-subtle bg-surface-card p-5 shadow-[0_1px_2px_rgba(16,24,40,0.04)]">
      <div className="flex items-start justify-between">
        <div>
          <p className="text-sm font-medium text-gray-500">{label}</p>
          <p className="mt-1.5 text-3xl font-semibold tracking-tight text-gray-900">{value}</p>
        </div>
        <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-blue-50 text-brand-blue">
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
                  : 'bg-gray-100 text-gray-500'
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
  );
}
