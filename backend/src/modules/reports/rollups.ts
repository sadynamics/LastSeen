import { prisma } from '../../config/prisma.js';
import { logger } from '../../config/logger.js';
import { Prisma, type PresenceEvent, type PresenceStatus } from '@prisma/client';

const log = logger.child({ mod: 'rollups' });

interface HourBucket {
  hour: number;
  seconds: number;
  sessions: number;
}

/**
 * Recompute (or finalize) a single day's rollup for one tracked number from
 * the raw presence events. Idempotent — overwrites the existing rollup row.
 *
 * Algorithm: walk events in chronological order, treat AVAILABLE as session
 * start and UNAVAILABLE/midnight as session end. Sessions that span hours
 * are split into hourly buckets.
 */
export async function rebuildDailyRollup(trackedNumberId: string, day: string): Promise<void> {
  const start = new Date(`${day}T00:00:00.000Z`);
  const end = new Date(start.getTime() + 24 * 60 * 60 * 1000);

  const events = await prisma.presenceEvent.findMany({
    where: {
      trackedNumberId,
      ts: { gte: start, lt: end },
    },
    orderBy: { ts: 'asc' },
  });

  // Pull the last event before midnight to know if a session was open.
  const carryIn = await prisma.presenceEvent.findFirst({
    where: { trackedNumberId, ts: { lt: start } },
    orderBy: { ts: 'desc' },
  });

  const sessions = computeSessions(events, carryIn, start, end);
  const hourly = bucketize(sessions, start);
  const totalOnlineSeconds = sessions.reduce((s, x) => s + x.durationSeconds, 0);
  const sessionCount = sessions.length;

  let peakHour: number | null = null;
  let peakSeconds = 0;
  for (const h of hourly) {
    if (h.seconds > peakSeconds) {
      peakSeconds = h.seconds;
      peakHour = h.hour;
    }
  }

  const isPast = end.getTime() <= Date.now();

  await prisma.dailyRollup.upsert({
    where: { trackedNumberId_day: { trackedNumberId, day: start } },
    create: {
      trackedNumberId,
      day: start,
      totalOnlineSeconds,
      sessionCount,
      firstOnline: sessions[0]?.start ?? null,
      lastOnline: sessions[sessions.length - 1]?.end ?? null,
      peakHour,
      hourly: hourly as unknown as Prisma.InputJsonValue,
      finalized: isPast,
    },
    update: {
      totalOnlineSeconds,
      sessionCount,
      firstOnline: sessions[0]?.start ?? null,
      lastOnline: sessions[sessions.length - 1]?.end ?? null,
      peakHour,
      hourly: hourly as unknown as Prisma.InputJsonValue,
      finalized: isPast,
      computedAt: new Date(),
    },
  });

  log.debug({ trackedNumberId, day, totalOnlineSeconds, sessionCount }, 'rebuilt rollup');
}

interface Session {
  start: Date;
  end: Date;
  durationSeconds: number;
}

function computeSessions(
  events: PresenceEvent[],
  carryIn: PresenceEvent | null,
  dayStart: Date,
  dayEnd: Date,
): Session[] {
  const out: Session[] = [];

  // If the previous event before midnight was AVAILABLE, we start with an open session.
  let openStart: Date | null = carryIn?.status === 'AVAILABLE' ? dayStart : null;

  for (const ev of events) {
    if (isOnline(ev.status)) {
      if (!openStart) openStart = ev.ts;
    } else if (ev.status === 'UNAVAILABLE') {
      if (openStart) {
        const end = ev.ts;
        const dur = Math.max(0, Math.round((end.getTime() - openStart.getTime()) / 1000));
        if (dur > 0) {
          out.push({ start: openStart, end, durationSeconds: dur });
        }
        openStart = null;
      }
    }
  }

  // Cap an open session at midnight (or now if today).
  if (openStart) {
    const end = new Date(Math.min(dayEnd.getTime(), Date.now()));
    if (end.getTime() > openStart.getTime()) {
      const dur = Math.max(0, Math.round((end.getTime() - openStart.getTime()) / 1000));
      if (dur > 0) out.push({ start: openStart, end, durationSeconds: dur });
    }
  }

  return out;
}

function isOnline(s: PresenceStatus): boolean {
  return s === 'AVAILABLE' || s === 'COMPOSING' || s === 'RECORDING';
}

function bucketize(sessions: Session[], dayStart: Date): HourBucket[] {
  const buckets: HourBucket[] = Array.from({ length: 24 }, (_, h) => ({ hour: h, seconds: 0, sessions: 0 }));
  for (const s of sessions) {
    let cursor = s.start.getTime();
    const endMs = s.end.getTime();
    let firstHourOfSession = -1;

    while (cursor < endMs) {
      const hour = Math.floor((cursor - dayStart.getTime()) / 3_600_000);
      if (hour < 0 || hour > 23) break;
      const nextHourBoundary = dayStart.getTime() + (hour + 1) * 3_600_000;
      const seg = Math.min(endMs, nextHourBoundary) - cursor;
      const bucket = buckets[hour];
      if (bucket) {
        bucket.seconds += Math.round(seg / 1000);
        if (firstHourOfSession !== hour) {
          bucket.sessions += 1;
          firstHourOfSession = hour;
        }
      }
      cursor = nextHourBoundary;
    }
  }
  return buckets;
}

/** Find tracked numbers that had any events in the last `lookbackHours`. */
export async function findTrackedNumbersWithRecentActivity(lookbackHours = 2): Promise<string[]> {
  const since = new Date(Date.now() - lookbackHours * 60 * 60 * 1000);
  const rows = await prisma.$queryRaw<Array<{ trackedNumberId: string }>>`
    SELECT DISTINCT "trackedNumberId" FROM presence_events WHERE ts >= ${since}
  `;
  return rows.map((r) => r.trackedNumberId);
}
