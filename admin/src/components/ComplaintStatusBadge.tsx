export type ComplaintStatus = 'PENDING' | 'INVESTIGATING' | 'RESOLVED' | 'REJECTED';

// Pending reuses the same amber as ID Verification's "Pending" badge — the
// word means the same thing (and color) everywhere in this app.
// Investigating is yellow too now (brand-blue's value, not a separate
// scheme), so it deliberately uses a darker/more saturated shade than
// Pending's pale amber rather than the same brand-blue token everything
// else uses — otherwise two different statuses in the same list would be
// indistinguishable at a glance.
const STATUS_STYLES: Record<ComplaintStatus, string> = {
  PENDING: 'bg-status-warning-bg text-status-warning',
  INVESTIGATING: 'bg-yellow-200 text-yellow-900',
  RESOLVED: 'bg-status-good-bg text-status-good',
  REJECTED: 'bg-status-critical-bg text-status-critical',
};

export function ComplaintStatusBadge({ status }: { status: ComplaintStatus }) {
  return (
    <span className={`inline-flex items-center rounded-full px-2.5 py-1 text-xs font-semibold ${STATUS_STYLES[status]}`}>
      {status}
    </span>
  );
}
