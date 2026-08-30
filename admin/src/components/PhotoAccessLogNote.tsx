import { formatManilaDateTime } from '../lib/formatDate';

export interface PhotoAccessLogEntry {
  adminId: string;
  adminName: string;
  adminEmail: string | null;
  viewedAt: string;
}

/** Access-audit note shown under a commuter/driver's KYC photos — who on
 * the admin team has viewed this sensitive data, and roughly when. Renders
 * nothing when the log is empty (e.g. this record has no KYC photo yet). */
export function PhotoAccessLogNote({ entries }: { entries: PhotoAccessLogEntry[] }) {
  if (entries.length === 0) return null;

  return (
    <div className="mt-3 rounded-lg border border-gray-200 bg-gray-50 p-3">
      <p className="mb-1.5 text-xs font-semibold text-gray-600">Viewed by</p>
      <ul className="space-y-1">
        {entries.map((entry, i) => (
          <li key={`${entry.adminId}-${entry.viewedAt}-${i}`} className="text-xs text-gray-500">
            <span className="font-medium text-gray-700">{entry.adminName}</span> · {formatManilaDateTime(entry.viewedAt)}
          </li>
        ))}
      </ul>
    </div>
  );
}
