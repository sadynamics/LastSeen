import { prisma } from '../../config/prisma.js';
import { rebuildDailyRollup } from './rollups.js';
import type { PresenceStatus } from '@prisma/client';

export interface LiveStatus {
  isOnline: boolean;
  lastEventAt: Date | null;
  lastStatus: PresenceStatus | null;
  /** When the current session started (if online), or `null`. */
  onlineSince: Date | null;
  /** Seconds since the last "available" event. */
  lastSeenSecondsAgo: number | null;
}

export async function liveStatus(trackedNumberId: string): Promise<LiveStatus> {
  const last = await prisma.presenceEvent.findFirst({
    where: { trackedNumberId },
    orderBy: { ts: 'desc' },
  });
  if (!last) {
    return { isOnline: false, lastEventAt: null, lastStatus: null, onlineSince: null, lastSeenSecondsAgo: null };
  }
  const isOnline = last.status === 'AVAILABLE' || last.status === 'COMPOSING' || last.status === 'RECORDING';

  let onlineSince: Date | null = null;
  if (isOnline) {
    // Walk backwards until we find the AVAILABLE that started the current session.
    const sessionStart = await prisma.presenceEvent.findFirst({
      where: {
        trackedNumberId,
        status: 'AVAILABLE',
        ts: { lte: last.ts },
      },
      orderBy: { ts: 'desc' },
    });
    onlineSince = sessionStart?.ts ?? last.ts;
  }

  const lastAvailable = isOnline
    ? null
    : await prisma.presenceEvent.findFirst({
        where: { trackedNumberId, status: 'AVAILABLE' },
        orderBy: { ts: 'desc' },
      });

  const lastSeenSecondsAgo = isOnline
    ? 0
    : lastAvailable
      ? Math.floor((Date.now() - lastAvailable.ts.getTime()) / 1000)
      : null;

  return {
    isOnline,
    lastEventAt: last.ts,
    lastStatus: last.status,
    onlineSince,
    lastSeenSecondsAgo,
  };
}

export interface SessionsForDay {
  day: string;
  sessions: Array<{ start: string; end: string; durationSeconds: number }>;
  totalOnlineSeconds: number;
  sessionCount: number;
}

export async function sessionsForDay(trackedNumberId: string, day: string): Promise<SessionsForDay> {
  // Lazy-rebuild today's rollup before reading.
  await rebuildDailyRollup(trackedNumberId, day).catch(() => undefined);

  const start = new Date(`${day}T00:00:00.000Z`);
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);
  const events = await prisma.presenceEvent.findMany({
    where: { trackedNumberId, ts: { gte: start, lt: end } },
    orderBy: { ts: 'asc' },
  });

  const out: Array<{ start: string; end: string; durationSeconds: number }> = [];
  let openStart: Date | null = null;
  for (const ev of events) {
    if ((ev.status === 'AVAILABLE' || ev.status === 'COMPOSING' || ev.status === 'RECORDING') && !openStart) {
      openStart = ev.ts;
    } else if (ev.status === 'UNAVAILABLE' && openStart) {
      const dur = Math.max(0, Math.round((ev.ts.getTime() - openStart.getTime()) / 1000));
      if (dur > 0) out.push({ start: openStart.toISOString(), end: ev.ts.toISOString(), durationSeconds: dur });
      openStart = null;
    }
  }
  if (openStart) {
    const endTs = new Date(Math.min(end.getTime(), Date.now()));
    const dur = Math.max(0, Math.round((endTs.getTime() - openStart.getTime()) / 1000));
    if (dur > 0) out.push({ start: openStart.toISOString(), end: endTs.toISOString(), durationSeconds: dur });
  }

  return {
    day,
    sessions: out,
    totalOnlineSeconds: out.reduce((s, x) => s + x.durationSeconds, 0),
    sessionCount: out.length,
  };
}

export interface WeeklyReport {
  weekStart: string;
  weekEnd: string;
  days: Array<{
    day: string;
    totalOnlineSeconds: number;
    sessionCount: number;
    peakHour: number | null;
  }>;
  totalOnlineSeconds: number;
  averagePerDaySeconds: number;
}

export async function weeklyReport(trackedNumberId: string, anchorDay?: string): Promise<WeeklyReport> {
  const now = anchorDay ? new Date(`${anchorDay}T00:00:00.000Z`) : new Date();
  const end = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  const start = new Date(end.getTime() - 6 * 24 * 60 * 60 * 1000);

  const rollups = await prisma.dailyRollup.findMany({
    where: { trackedNumberId, day: { gte: start, lte: end } },
    orderBy: { day: 'asc' },
  });

  const days: WeeklyReport['days'] = [];
  for (let i = 0; i < 7; i += 1) {
    const dayDate = new Date(start.getTime() + i * 24 * 60 * 60 * 1000);
    const iso = dayDate.toISOString().slice(0, 10);
    const r = rollups.find((x) => x.day.toISOString().slice(0, 10) === iso);
    days.push({
      day: iso,
      totalOnlineSeconds: r?.totalOnlineSeconds ?? 0,
      sessionCount: r?.sessionCount ?? 0,
      peakHour: r?.peakHour ?? null,
    });
  }

  const total = days.reduce((s, x) => s + x.totalOnlineSeconds, 0);
  return {
    weekStart: start.toISOString().slice(0, 10),
    weekEnd: end.toISOString().slice(0, 10),
    days,
    totalOnlineSeconds: total,
    averagePerDaySeconds: Math.round(total / 7),
  };
}
