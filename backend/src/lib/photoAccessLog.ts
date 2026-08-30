import { prisma } from './prisma';
import type { PhotoAccessTargetType } from '@prisma/client';

// GET /admin/commuters/:id and GET /admin/drivers/:id are polled every few
// seconds by the detail panel while it's open (see those routes' own doc
// comments) — logging every poll would turn this into an unreadable flood
// rather than a meaningful "who looked at this" trail. Collapsing repeat
// views from the same admin on the same record into one row per rolling
// window keeps it meaningful without adding a separate "mark as viewed"
// endpoint the frontend would have to remember to call.
const DEDUPE_WINDOW_MS = 24 * 60 * 60 * 1000;

/** Records that [adminId] viewed [targetType]/[targetId]'s KYC photos —
 * call only when the record actually has a photo to view, right where
 * that record's photo URLs are read for an admin response. Best-effort:
 * a logging failure never blocks the request that triggered it. */
export async function logPhotoAccess(
  adminId: string,
  targetType: PhotoAccessTargetType,
  targetId: string,
): Promise<void> {
  try {
    const recent = await prisma.photoAccessLog.findFirst({
      where: { adminId, targetType, targetId, viewedAt: { gte: new Date(Date.now() - DEDUPE_WINDOW_MS) } },
      select: { id: true },
    });
    if (recent) return;
    await prisma.photoAccessLog.create({ data: { adminId, targetType, targetId } });
  } catch (err) {
    console.error('logPhotoAccess failed:', err);
  }
}

/** The most recent admins to have viewed [targetType]/[targetId]'s KYC
 * photos, newest first — backs the "Viewed by" list on the commuter/
 * driver detail panel. */
export async function getPhotoAccessLog(targetType: PhotoAccessTargetType, targetId: string, take = 20) {
  const entries = await prisma.photoAccessLog.findMany({
    where: { targetType, targetId },
    orderBy: { viewedAt: 'desc' },
    take,
  });
  if (entries.length === 0) return [];

  const admins = await prisma.admin.findMany({
    where: { id: { in: [...new Set(entries.map((e) => e.adminId))] } },
    select: { id: true, fullName: true, email: true },
  });
  const adminById = new Map(admins.map((a) => [a.id, a]));

  return entries.map((e) => ({
    adminId: e.adminId,
    adminName: adminById.get(e.adminId)?.fullName ?? 'Deleted admin',
    adminEmail: adminById.get(e.adminId)?.email ?? null,
    viewedAt: e.viewedAt,
  }));
}
