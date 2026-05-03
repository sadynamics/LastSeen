import { Worker } from 'bullmq';
import { createRedisConnection } from '../config/redis.js';
import { logger } from '../config/logger.js';
import { prisma } from '../config/prisma.js';
import { pushToUser } from '../modules/push/apns.js';
import { QUEUE_NOTIFY, type NotifyJob } from '../modules/tracking/queues.js';

const log = logger.child({ worker: 'notify' });

function isInQuietHours(prefs: { quietHoursStart: number | null; quietHoursEnd: number | null; timezone: string | null }): boolean {
  if (prefs.quietHoursStart == null || prefs.quietHoursEnd == null) return false;
  const tz = prefs.timezone ?? 'UTC';
  const formatter = new Intl.DateTimeFormat('en-GB', {
    timeZone: tz,
    hour: '2-digit',
    hour12: false,
  });
  const hour = parseInt(formatter.format(new Date()), 10);
  const start = prefs.quietHoursStart;
  const end = prefs.quietHoursEnd;
  if (start === end) return false;
  if (start < end) return hour >= start && hour < end;
  // Wraps midnight
  return hour >= start || hour < end;
}

function formatDuration(seconds: number): string {
  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.round(seconds / 60)}m`;
  const h = Math.floor(seconds / 3600);
  const m = Math.round((seconds - h * 3600) / 60);
  return m === 0 ? `${h}h` : `${h}h ${m}m`;
}

export function startNotifyWorker(): Worker<NotifyJob> {
  const worker = new Worker<NotifyJob>(
    QUEUE_NOTIFY,
    async (job) => {
      const tracked = await prisma.trackedNumber.findUnique({
        where: { id: job.data.trackedNumberId },
        include: { prefs: true, user: true },
      });
      if (!tracked || tracked.archivedAt) return;
      const prefs = tracked.prefs;
      if (!prefs) return;

      if (isInQuietHours(prefs)) {
        log.debug({ trackedNumberId: tracked.id, type: job.data.type }, 'silenced (quiet hours)');
        return;
      }

      const display = tracked.displayName ?? tracked.e164;

      switch (job.data.type) {
        case 'online': {
          if (!prefs.onlineEnabled) return;
          await pushToUser(tracked.userId, {
            title: display,
            body: 'Came online',
            threadId: tracked.id,
            data: { trackedNumberId: tracked.id, kind: 'online' },
          });
          return;
        }
        case 'offline': {
          if (!prefs.offlineEnabled && !prefs.sessionEndedEnabled) return;
          const dur = formatDuration(job.data.sessionDurationSeconds);
          await pushToUser(tracked.userId, {
            title: display,
            body: `Went offline after ${dur}`,
            threadId: tracked.id,
            data: { trackedNumberId: tracked.id, kind: 'offline' },
          });
          return;
        }
        case 'daily_summary': {
          if (!prefs.dailySummaryEnabled) return;
          const rollup = await prisma.dailyRollup.findUnique({
            where: { trackedNumberId_day: { trackedNumberId: tracked.id, day: new Date(`${job.data.day}T00:00:00Z`) } },
          });
          if (!rollup) return;
          const total = formatDuration(rollup.totalOnlineSeconds);
          await pushToUser(tracked.userId, {
            title: `${display} — daily report`,
            body: `${total} online across ${rollup.sessionCount} sessions`,
            threadId: tracked.id,
            data: { trackedNumberId: tracked.id, kind: 'daily_summary', day: job.data.day },
          });
          return;
        }
        default:
          return;
      }
    },
    { connection: createRedisConnection(), concurrency: 8 },
  );

  worker.on('failed', (job, err) => {
    log.warn({ jobId: job?.id, err: err.message }, 'notify job failed');
  });
  return worker;
}
