import { Worker } from 'bullmq';
import { createRedisConnection } from '../config/redis.js';
import { logger } from '../config/logger.js';
import { prisma } from '../config/prisma.js';
import { scraperPool } from '../modules/tracking/scraperPool.js';
import { ingestPresence } from '../modules/tracking/presenceIngest.js';
import { QUEUE_TRACKING, type TrackingJob } from '../modules/tracking/queues.js';

const log = logger.child({ worker: 'tracking' });

export function startTrackingWorker(): Worker<TrackingJob> {
  scraperPool.setPresenceHandler((ev) => {
    void ingestPresence(ev).catch((err) => log.error({ err, ev }, 'ingest failed'));
  });

  const worker = new Worker<TrackingJob>(
    QUEUE_TRACKING,
    async (job) => {
      const data = job.data;
      switch (data.type) {
        case 'pair': {
          const acc = await prisma.scraperAccount.findUnique({ where: { id: data.scraperAccountId } });
          if (!acc) return;
          // QR + paired listeners are attached inside scraperPool.start()
          // so they fire on bootstrap-triggered starts too, not just on the
          // explicit pair job.
          await scraperPool.start(acc);
          return;
        }
        case 'track': {
          const tracked = await prisma.trackedNumber.findUnique({ where: { id: data.trackedNumberId } });
          if (!tracked || tracked.archivedAt) return;

          // Pick or reuse a scraper.
          let scraperId = tracked.scraperAccountId;
          if (!scraperId) {
            const assigned = await scraperPool.assignScraper();
            if (!assigned) {
              log.warn({ trackedNumberId: tracked.id }, 'no healthy scraper available');
              throw new Error('no healthy scraper available');
            }
            scraperId = assigned.id;
            await prisma.trackedNumber.update({
              where: { id: tracked.id },
              data: { scraperAccountId: scraperId },
            });
          }

          const session = scraperPool.get(scraperId);
          if (!session) {
            log.warn({ scraperId }, 'scraper session not running');
            throw new Error('scraper session not running');
          }
          if (!session.isOpen()) {
            throw new Error('scraper not open yet');
          }

          // Resolve JID if missing.
          let jid = tracked.jid;
          if (!jid) {
            jid = await session.lookupJid(tracked.e164);
            if (!jid) {
              log.warn({ trackedNumberId: tracked.id, e164: tracked.e164 }, 'number not on whatsapp');
              return;
            }
            await prisma.trackedNumber.update({ where: { id: tracked.id }, data: { jid } });
          }

          await session.subscribe(jid);
          log.info({ trackedNumberId: tracked.id, jid }, 'subscribed');
          return;
        }
        case 'untrack': {
          if (data.scraperAccountId && data.jid) {
            scraperPool.get(data.scraperAccountId)?.unsubscribe(data.jid);
          }
          return;
        }
        default:
          return;
      }
    },
    {
      connection: createRedisConnection(),
      concurrency: 4,
    },
  );

  worker.on('failed', (job, err) => {
    log.warn({ jobId: job?.id, err: err.message }, 'tracking job failed');
  });
  worker.on('completed', (job) => {
    log.debug({ jobId: job.id, type: job.data.type }, 'tracking job completed');
  });
  return worker;
}
