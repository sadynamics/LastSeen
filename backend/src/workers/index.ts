import 'dotenv-flow/config';
import { logger } from '../config/logger.js';
import { initSentry } from '../config/sentry.js';
import { scraperPool } from '../modules/tracking/scraperPool.js';
import { startTrackingWorker } from './trackingWorker.js';
import { startNotifyWorker } from './notifyWorker.js';
import { startRollupWorker } from './rollupWorker.js';

async function main(): Promise<void> {
  initSentry();
  logger.info('starting workers');

  await scraperPool.bootstrap();

  const tracking = startTrackingWorker();
  const notify = startNotifyWorker();
  const rollup = startRollupWorker();

  for (const sig of ['SIGINT', 'SIGTERM'] as const) {
    process.on(sig, async () => {
      logger.info({ sig }, 'shutting down workers');
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

void main().catch((err) => {
  logger.error({ err }, 'workers crashed');
  process.exit(1);
});
