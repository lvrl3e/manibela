import { useEffect, useRef, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { adminNotificationPath, type AdminNotification } from '../lib/useAdminNotificationFeed';

function BellIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="M6 9a6 6 0 0 1 12 0c0 4.2 1.5 5.8 2 6.5H4c.5-.7 2-2.3 2-6.5Z" />
      <path d="M10 19.5a2 2 0 0 0 4 0" />
    </svg>
  );
}

function relativeTime(iso: string): string {
  const diffMs = Date.now() - new Date(iso).getTime();
  const mins = Math.floor(diffMs / 60_000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins}m ago`;
  const hours = Math.floor(mins / 60);
  if (hours < 24) return `${hours}h ago`;
  const days = Math.floor(hours / 24);
  if (days < 7) return `${days}d ago`;
  return new Date(iso).toLocaleDateString('en-PH', { timeZone: 'Asia/Manila', month: 'short', day: 'numeric' });
}

/** Bell icon + unread-count badge + dropdown. Purely presentational —
 * fetching/polling lives in useAdminNotificationFeed, called once by
 * DashboardLayout and passed down, since this component itself renders
 * twice (once per responsive header) and each instance polling
 * independently would double every request. Opening the dropdown clears
 * the badge, same "tap clears the badge" behavior the commuter/driver
 * apps use. */
export function NotificationBell({
  notifications,
  unreadCount,
  onMarkAllRead,
  hasNextPage,
  isLoadingMore,
  onLoadMore,
}: {
  notifications: AdminNotification[];
  unreadCount: number;
  onMarkAllRead: () => void;
  hasNextPage: boolean;
  isLoadingMore: boolean;
  onLoadMore: () => void;
}) {
  const navigate = useNavigate();
  const [open, setOpen] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (!open) return;
    function handleClickOutside(e: MouseEvent) {
      if (containerRef.current && !containerRef.current.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [open]);

  const handleToggle = () => {
    const next = !open;
    setOpen(next);
    if (next) onMarkAllRead();
  };

  const handleNotificationClick = (n: AdminNotification) => {
    const path = adminNotificationPath(n);
    if (!path) return;
    setOpen(false);
    navigate(path);
  };

  return (
    <div ref={containerRef} className="relative">
      <button
        onClick={handleToggle}
        className="relative rounded-lg p-2 text-gray-600 transition hover:bg-gray-100"
        aria-label="Notifications"
      >
        <BellIcon />
        {unreadCount > 0 && (
          <span className="absolute right-1 top-1 flex h-4 min-w-4 items-center justify-center rounded-full bg-red-500 px-1 text-[10px] font-bold leading-none text-white">
            {unreadCount > 9 ? '9+' : unreadCount}
          </span>
        )}
      </button>

      {open && (
        <div className="absolute right-0 z-30 mt-2 w-80 max-w-[90vw] overflow-hidden rounded-xl border border-gray-200 bg-white shadow-lg">
          <div className="border-b border-gray-100 px-4 py-3">
            <p className="text-sm font-semibold text-gray-900">Notifications</p>
          </div>
          <div className="max-h-96 overflow-y-auto">
            {notifications.length === 0 ? (
              <p className="px-4 py-6 text-center text-sm text-gray-400">No notifications yet.</p>
            ) : (
              notifications.map((n) => {
                const isNavigable = !!adminNotificationPath(n);
                return (
                  <div
                    key={n.id}
                    onClick={isNavigable ? () => handleNotificationClick(n) : undefined}
                    className={`border-b border-gray-50 px-4 py-3 last:border-b-0 ${n.isRead ? '' : 'bg-brand-blue/5'} ${
                      isNavigable ? 'cursor-pointer hover:bg-gray-50' : ''
                    }`}
                  >
                    <div className="flex items-start justify-between gap-2">
                      <p className="text-sm font-semibold text-gray-900">{n.title}</p>
                      {!n.isRead && <span className="mt-1 h-2 w-2 flex-shrink-0 rounded-full bg-brand-blue" />}
                    </div>
                    <p className="mt-0.5 whitespace-pre-line text-xs text-gray-600">{n.message}</p>
                    <p className="mt-1 text-[11px] text-gray-400">{relativeTime(n.createdAt)}</p>
                  </div>
                );
              })
            )}
            {hasNextPage && (
              <div className="border-t border-gray-50 px-4 py-2.5 text-center">
                <button
                  onClick={onLoadMore}
                  disabled={isLoadingMore}
                  className="text-xs font-semibold text-brand-blue hover:underline disabled:cursor-not-allowed disabled:opacity-50"
                >
                  {isLoadingMore ? 'Loading...' : 'Load More'}
                </button>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
