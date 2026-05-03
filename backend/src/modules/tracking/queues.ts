import { Queue, QueueEvents } from 'bullmq';
import { createRedisConnection } from '../../config/redis.js';

export const QUEUE_TRACKING = 'tracking';
export const QUEUE_NOTIFY = 'notify';
export const QUEUE_ROLLUP = 'rollup';

export interface TrackJob {
  type: 'track';
  trackedNumberId: string;
}

export interface UntrackJob {
  type: 'untrack';
  trackedNumberId: string;
  jid: string | null;
  scraperAccountId: string | null;
}

export interface PairJob {
  type: 'pair';
  scraperAccountId: string;
}

export type TrackingJob = TrackJob | UntrackJob | PairJob;

export interface IngestEventJob {
  type: 'ingest';
  scraperId: string;
  jid: string;
  status: 'available' | 'unavailable' | 'composing' | 'recording' | 'paused';
  ts: string; // ISO
  lastKnownPresence?: number;
}

export interface NotifyOnlineJob {
  type: 'online';
  trackedNumberId: string;
  ts: string;
}

export interface NotifyOfflineJob {
  type: 'offline';
  trackedNumberId: string;
  ts: string;
  sessionDurationSeconds: number;
}

export interface NotifyDailySummaryJob {
  type: 'daily_summary';
  trackedNumberId: string;
  day: string; // YYYY-MM-DD
}

export type NotifyJob = NotifyOnlineJob | NotifyOfflineJob | NotifyDailySummaryJob;

export interface RollupJob {
  type: 'rollup';
  trackedNumberId: string;
  day: string; // YYYY-MM-DD
}

// Lazy-instantiated to avoid creating Redis connections at import time.
let _trackingQueue: Queue<TrackingJob> | undefined;
let _notifyQueue: Queue<NotifyJob> | undefined;
let _rollupQueue: Queue<RollupJob> | undefined;

export function trackingQueue(): Queue<TrackingJob> {
  if (!_trackingQueue) {
    _trackingQueue = new Queue<TrackingJob>(QUEUE_TRACKING, {
      connection: createRedisConnection(),
      defaultJobOptions: {
        attempts: 5,
        backoff: { type: 'exponential', delay: 2_000 },
        removeOnComplete: 1000,
        removeOnFail: 5000,
      },
    });
  }
  return _trackingQueue;
}

export function notifyQueue(): Queue<NotifyJob> {
  if (!_notifyQueue) {
    _notifyQueue = new Queue<NotifyJob>(QUEUE_NOTIFY, {
      connection: createRedisConnection(),
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: 'exponential', delay: 1_000 },
        removeOnComplete: 500,
        removeOnFail: 1000,
      },
    });
  }
  return _notifyQueue;
}

export function rollupQueue(): Queue<RollupJob> {
  if (!_rollupQueue) {
    _rollupQueue = new Queue<RollupJob>(QUEUE_ROLLUP, {
      connection: createRedisConnection(),
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: 'exponential', delay: 5_000 },
        removeOnComplete: 200,
        removeOnFail: 500,
      },
    });
  }
  return _rollupQueue;
}

export function trackingEvents(): QueueEvents {
  return new QueueEvents(QUEUE_TRACKING, { connection: createRedisConnection() });
}
