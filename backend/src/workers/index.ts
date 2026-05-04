import 'dotenv-flow/config';
import { logger } from '../config/logger.js';
import { initSentry } from '../config/sentry.js';
import { prisma } from '../config/prisma.js';
import { scraperPool } from '../modules/tracking/scraperPool.js';
import { trackingQueue } from '../modules/tracking/queues.js';
import { startTrackingWorker } from './trackingWorker.js';
import { startNotifyWorker } from './notifyWorker.js';
import { startRollupWorker } from './rollupWorker.js';

const log = logger.child({ mod: 'workers' });

async function main(): Promise<void> {
  initSentry();
  log.info('starting workers');

  await scraperPool.bootstrap();

  const tracking = startTrackingWorker();
  const notify = startNotifyWorker();
  const rollup = startRollupWorker();

  // Periodic maintenance: every 5 minutes, promote any WARMING scrapers whose
  // cooldown expired and reattach any orphan tracked numbers. This guarantees
  // tracking auto-resumes the moment a scraper becomes ready, with no admin
  // intervention required.
  const maintenance = setInterval(() => {
    void runMaintenance().catch((err) => log.warn({ err }, 'maintenance pass failed'));
  }, 5 * 60 * 1000);

  // Run once at startup too.
  void runMaintenance().catch((err) => log.warn({ err }, 'initial maintenance pass failed'));

  for (const sig of ['SIGINT', 'SIGTERM'] as const) {
    process.on(sig, async () => {
      log.info({ sig }, 'shutting down workers');
      clearInterval(maintenance);
      await Promise.all([
        tracking.close(),
        notify.close(),
        rollup.close(),
        scraperPool.stopAll(),
      ]);
      process.exit(0);
    });
  }
}

async function runMaintenance(): Promise<void> {
  const promoted = await scraperPool.promoteReadyScrapers();

  const orphans = await prisma.trackedNumber.findMany({
    where: { archivedAt: null, scraperAccountId: null },
    select: { id: true },
  });
  for (const o of orphans) {
    await trackingQueue().add('track', { type: 'track', trackedNumberId: o.id });
  }

  if (promoted > 0 || orphans.length > 0) {
    log.info({ promoted, requeued: orphans.length }, 'maintenance pass');
  }
}

void main().catch((err) => {
  logger.error({ err }, 'workers crashed');
  process.exit(1);
});
