export type VerificationStatus = 'PENDING' | 'APPROVED' | 'REJECTED' | null;

function ClockIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2">
      <circle cx="12" cy="12" r="9" />
      <path d="M12 7v5l3.5 2" />
    </svg>
  );
}

function CheckIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6">
      <path d="M5 13l4 4L19 7" />
    </svg>
  );
}

function CrossIcon() {
  return (
    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.6">
      <path d="M6 6l12 12M18 6 6 18" />
    </svg>
  );
}

/** Status is never color-alone here — every badge pairs an icon with a
 * label, per the dataviz skill's status-palette rule. */
export function VerificationBadge({ status, notSubmitted }: { status: VerificationStatus; notSubmitted?: boolean }) {
  if (notSubmitted || !status) {
    return (
      <span className="inline-flex items-center gap-1 rounded-full bg-gray-100 px-2.5 py-1 text-xs font-semibold text-gray-500">
        Not submitted
      </span>
    );
  }

  const config = {
    PENDING: { icon: <ClockIcon />, label: 'Pending', bg: 'bg-status-warning-bg', text: 'text-status-warning' },
    APPROVED: { icon: <CheckIcon />, label: 'Approved', bg: 'bg-status-good-bg', text: 'text-status-good' },
    REJECTED: { icon: <CrossIcon />, label: 'Rejected', bg: 'bg-status-critical-bg', text: 'text-status-critical' },
  }[status];

  return (
    <span className={`inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-xs font-semibold ${config.bg} ${config.text}`}>
      {config.icon}
      {config.label}
    </span>
  );
}
