export type ComplaintStatus = 'PENDING' | 'INVESTIGATING' | 'RESOLVED' | 'REJECTED';

// Pending reuses the same amber as ID Verification's "Pending" badge — the
// word means the same thing (and color) everywhere in this app. Blue for
// Investigating since there's no other page to stay consistent with, but
// it needs to read as distinct from Pending's "untouched" amber.
const STATUS_STYLES: Record<ComplaintStatus, string> = {
  PENDING: 'bg-status-warning-bg text-status-warning',
  INVESTIGATING: 'bg-blue-50 text-brand-blue',
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
