import { Worker } from 'bullmq';
import { createRedisConnection } from '../config/redis.js';
import { logger } from '../config/logger.js';
import { rebuildDailyRollup, findTrackedNumbersWithRecentActivity } from '../modules/reports/rollups.js';
import { notifyQueue, QUEUE_ROLLUP, rollupQueue, type RollupJob } from '../modules/tracking/queues.js';

const log = logger.child({ worker: 'rollup' });

export function startRollupWorker(): Worker<RollupJob> {
  const worker = new Worker<RollupJob>(
    QUEUE_ROLLUP,
    async (job) => {
      await rebuildDailyRollup(job.data.trackedNumberId, job.data.day);
    },
    { connection: createRedisConnection(), concurrency: 4 },
  );
  worker.on('failed', (job, err) => {
    log.warn({ jobId: job?.id, err: err.message }, 'rollup job failed');
  });

  startCron();
  return worker;
}

function startCron(): void {
  const queue = rollupQueue();

  // Hourly: rebuild today's rollup for any active tracked number.
  setInterval(
    () => {
      void (async () => {
        try {
          const ids = await findTrackedNumbersWithRecentActivity(2);
          const day = new Date().toISOString().slice(0, 10);
          for (const id of ids) {
            await queue.add(
              `rollup-${id}-${day}`,
              { type: 'rollup', trackedNumberId: id, day },
              { jobId: `rollup-${id}-${day}` },
            );
          }
          log.debug({ count: ids.length }, 'enqueued hourly rollups');
        } catch (err) {
          log.error({ err }, 'hourly rollup cron failed');
        }
      })();
    },
    60 * 60 * 1000, // 1h
  );

  // Daily at 09:00 UTC (rough cron via interval): enqueue daily summary pushes
  // for yesterday's rollups.
  setInterval(
    () => {
      const now = new Date();
      if (now.getUTCHours() !== 9 || now.getUTCMinutes() > 5) return;
      void (async () => {
        try {
          const yesterday = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
          const ids = await findTrackedNumbersWithRecentActivity(36);
          for (const id of ids) {
            await notifyQueue().add('daily_summary', {
              type: 'daily_summary',
              trackedNumberId: id,
              day: yesterday,
            });
          }
          log.info({ count: ids.length }, 'enqueued daily summaries');
        } catch (err) {
          log.error({ err }, 'daily summary cron failed');
        }
      })();
    },
    5 * 60 * 1000, // check every 5m
  );
}
