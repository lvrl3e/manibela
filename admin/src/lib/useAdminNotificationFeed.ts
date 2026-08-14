import { useEffect, useRef, useState } from 'react';
import { apiClient } from './apiClient';
import { usePolling } from './usePolling';

export interface AdminNotification {
  id: string;
  title: string;
  message: string;
  isRead: boolean;
  createdAt: string;
  /// See Notification's doc comment in schema.prisma. Null for a
  /// notification with nothing to navigate to.
  type: string | null;
  /// An id [type] tells the reader how to interpret — see
  /// [adminNotificationPath] for what each type's id actually points at.
  referenceId: string | null;
}

const PAGE_SIZE = 50;

/** How long a toast stays up before auto-dismissing. */
const TOAST_DURATION_MS = 8_000;

/** Notification types with somewhere to navigate to — shared between the
 * bell dropdown and the toast layer so "is this clickable" is answered
 * the same way in both places. */
export const NAVIGABLE_ADMIN_NOTIFICATION_TYPES = new Set([
  'TRIP_SHORT_FLAGGED',
  'TRIP_EXPLANATION_SUBMITTED',
  'ID_VERIFICATION_SUBMITTED',
  'COMPLAINT_FILED',
]);

/** Where tapping a notification should navigate to, keyed by its type —
 * shared between the bell dropdown and the toast layer (same reasoning as
 * [NAVIGABLE_ADMIN_NOTIFICATION_TYPES]) so both answer "go where" the same
 * way. Null for anything not in that set, or missing a referenceId. */
export function adminNotificationPath(n: Pick<AdminNotification, 'type' | 'referenceId'>): string | null {
  if (!n.type || !n.referenceId || !NAVIGABLE_ADMIN_NOTIFICATION_TYPES.has(n.type)) return null;
  switch (n.type) {
    case 'TRIP_SHORT_FLAGGED':
    case 'TRIP_EXPLANATION_SUBMITTED':
      // This app's trip-review UI lives entirely in a driver's Driver
      // Detail Panel (see DriverDetailPanel.tsx) — referenceId is a Driver id.
      return `/drivers?driverId=${n.referenceId}`;
    case 'ID_VERIFICATION_SUBMITTED':
      // referenceId is a Commuter id.
      return `/commuters/${n.referenceId}`;
    case 'COMPLAINT_FILED':
      // referenceId is a Complaint id.
      return `/incident-reports?complaintId=${n.referenceId}`;
    default:
      return null;
  }
}

/**
 * Fetches + polls the shared admin `Notification` feed once, and tracks
 * which ones are new since the last fetch as toasts. Deliberately a
 * single hook instance owned by DashboardLayout (not called from inside
 * NotificationBell itself) — NotificationBell renders twice, once per
 * responsive header, and calling this from there would mean two
 * independent pollers each popping their own toast for the same event.
 */
export function useAdminNotificationFeed() {
  // Page 1 — kept live by polling, drives the badge/toasts, exactly as
  // before. [extra] holds anything loaded via "Load More" beyond it —
  // kept separate so polling page 1 doesn't need to re-fetch (and
  // potentially reorder/duplicate) pages the admin already scrolled past.
  const [notifications, setNotifications] = useState<AdminNotification[]>([]);
  const [extra, setExtra] = useState<AdminNotification[]>([]);
  const [loadedPages, setLoadedPages] = useState(1);
  const [hasNextPage, setHasNextPage] = useState(false);
  const [isLoadingMore, setIsLoadingMore] = useState(false);
  const [toasts, setToasts] = useState<AdminNotification[]>([]);

  // Null until the first fetch resolves — distinguishes "nothing seen
  // yet" from "seen everything currently in the list", so the very first
  // load doesn't toast every pre-existing notification at once.
  const seenIdsRef = useRef<Set<string> | null>(null);
  const toastTimersRef = useRef<Map<string, ReturnType<typeof setTimeout>>>(new Map());

  const unreadCount = notifications.filter((n) => !n.isRead).length;

  const dismissToast = (id: string) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
    const timer = toastTimersRef.current.get(id);
    if (timer) {
      clearTimeout(timer);
      toastTimersRef.current.delete(id);
    }
  };

  const fetchNotifications = () => {
    apiClient
      .get<{ notifications: AdminNotification[]; hasNextPage: boolean }>(
        `/api/admin/notifications?page=1&pageSize=${PAGE_SIZE}`,
      )
      .then((res) => {
        setNotifications(res.notifications);
        setHasNextPage(res.hasNextPage);

        if (seenIdsRef.current === null) {
          seenIdsRef.current = new Set(res.notifications.map((n) => n.id));
          return;
        }

        const freshlySeen = res.notifications.filter((n) => !seenIdsRef.current!.has(n.id));
        if (freshlySeen.length === 0) return;
        for (const n of freshlySeen) seenIdsRef.current.add(n.id);

        setToasts((prev) => [...freshlySeen, ...prev]);
        for (const n of freshlySeen) {
          const timer = setTimeout(() => dismissToast(n.id), TOAST_DURATION_MS);
          toastTimersRef.current.set(n.id, timer);
        }
      })
      .catch(() => {
        // Best-effort — leave whatever's currently shown.
      });
  };

  const loadMore = () => {
    if (isLoadingMore || !hasNextPage) return;
    setIsLoadingMore(true);
    const nextPage = loadedPages + 1;
    apiClient
      .get<{ notifications: AdminNotification[]; hasNextPage: boolean }>(
        `/api/admin/notifications?page=${nextPage}&pageSize=${PAGE_SIZE}`,
      )
      .then((res) => {
        setExtra((prev) => [...prev, ...res.notifications]);
        setLoadedPages(nextPage);
        setHasNextPage(res.hasNextPage);
      })
      .finally(() => setIsLoadingMore(false));
  };

  useEffect(fetchNotifications, []);
  usePolling(fetchNotifications, 10_000);

  useEffect(() => {
    const timers = toastTimersRef.current;
    return () => {
      for (const timer of timers.values()) clearTimeout(timer);
    };
  }, []);

  const markAllRead = () => {
    if (unreadCount === 0) return;
    setNotifications((prev) => prev.map((n) => ({ ...n, isRead: true })));
    setExtra((prev) => prev.map((n) => ({ ...n, isRead: true })));
    // Best-effort — badge is already cleared locally either way.
    apiClient.post('/api/admin/notifications/mark-read').catch(() => {});
  };

  return {
    notifications: [...notifications, ...extra],
    unreadCount,
    markAllRead,
    toasts,
    dismissToast,
    hasNextPage,
    isLoadingMore,
    loadMore,
  };
}
