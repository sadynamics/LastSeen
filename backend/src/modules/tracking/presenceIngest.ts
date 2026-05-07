import { prisma } from '../../config/prisma.js';
import { logger } from '../../config/logger.js';
import { notifyQueue, rollupQueue } from './queues.js';
import type { PresenceEventPayload } from './baileysSession.js';
import type { PresenceStatus } from '@prisma/client';

const log = logger.child({ mod: 'presenceIngest' });

/**
 * Minimum gap between two events with the SAME status to consider them
 * meaningful. Prevents WhatsApp's bursty "available" pulses from inflating
 * session counts.
 */
const MIN_FLAP_MS = 5_000;

interface LastEvent {
  status: PresenceStatus;
  ts: number;
}

/**
 * Anti-flap + edge-detection cache, keyed by tracked number id. Populated
 * lazily from the DB on first miss (see `loadLastEvent`) so that worker
 * restarts don't:
 *   - lose the AVAILABLE→UNAVAILABLE edge (and silently drop offline /
 *     session-ended pushes for whoever was online at restart time), or
 *   - re-fire a "Came online" push when an already-online contact emits
 *     their next AVAILABLE pulse post-restart.
 */
const lastEventCache = new Map<string, LastEvent>();

async function loadLastEvent(trackedNumberId: string): Promise<LastEvent | null> {
  const cached = lastEventCache.get(trackedNumberId);
  if (cached) return cached;

  const fromDb = await prisma.presenceEvent.findFirst({
    where: { trackedNumberId },
    orderBy: { ts: 'desc' },
    select: { status: true, ts: true },
  });
  if (!fromDb) return null;

  const restored: LastEvent = { status: fromDb.status, ts: fromDb.ts.getTime() };
  lastEventCache.set(trackedNumberId, restored);
  return restored;
}

const STATUS_MAP: Record<PresenceEventPayload['status'], PresenceStatus> = {
  available: 'AVAILABLE',
  unavailable: 'UNAVAILABLE',
  composing: 'COMPOSING',
  recording: 'RECORDING',
  paused: 'PAUSED',
};

/**
 * Ingest a single presence event from a Baileys session. Persists one event
 * per tracked-number row that matches the JID (multiple users can track the
 * same phone number, so events MUST fan out to all of them) and fans out
 * notification + rollup jobs.
 */
export async function ingestPresence(ev: PresenceEventPayload): Promise<void> {
  // WhatsApp publishes presence updates under either the contact's phone JID
  // (@s.whatsapp.net) or LID (@lid). Match either, and return ALL matching
  // tracked-number rows — two different users may track the same number.
  const trackedRows = await prisma.trackedNumber.findMany({
    where: {
      archivedAt: null,
      OR: [{ jid: ev.jid }, { lid: ev.jid }],
    },
    select: { id: true, userId: true },
  });
  if (trackedRows.length === 0) {
    log.debug({ jid: ev.jid, status: ev.status }, 'presence event without matching tracked number');
    return;
  }

  await Promise.all(trackedRows.map((tracked) => ingestForTrackedNumber(ev, tracked)));
}

async function ingestForTrackedNumber(
  ev: PresenceEventPayload,
  tracked: { id: string; userId: string },
): Promise<void> {
  const mapped = STATUS_MAP[ev.status];
  const now = ev.ts.getTime();
  const last = await loadLastEvent(tracked.id);

  // Drop dupes within the flap window.
  if (last && last.status === mapped && now - last.ts < MIN_FLAP_MS) {
    return;
  }

  await prisma.presenceEvent.create({
    data: {
      trackedNumberId: tracked.id,
      scraperAccountId: ev.scraperId,
      status: mapped,
      ts: ev.ts,
    },
  });

  // Compute session duration on `unavailable` transition.
  let sessionDurationSeconds = 0;
  if (mapped === 'UNAVAILABLE' && last?.status === 'AVAILABLE') {
    sessionDurationSeconds = Math.max(0, Math.round((now - last.ts) / 1000));
  }

  lastEventCache.set(tracked.id, { status: mapped, ts: now });

  const day = ev.ts.toISOString().slice(0, 10);
  if (mapped === 'AVAILABLE' && last?.status !== 'AVAILABLE') {
    await notifyQueue().add('online', {
      type: 'online',
      trackedNumberId: tracked.id,
      ts: ev.ts.toISOString(),
    });
  }
  if (mapped === 'UNAVAILABLE' && last?.status === 'AVAILABLE') {
    await notifyQueue().add('offline', {
      type: 'offline',
      trackedNumberId: tracked.id,
      ts: ev.ts.toISOString(),
      sessionDurationSeconds,
    });
  }

  await rollupQueue().add(
    `rollup-${tracked.id}-${day}`,
    { type: 'rollup', trackedNumberId: tracked.id, day },
    { jobId: `rollup-${tracked.id}-${day}`, delay: 30_000 },
  );

  log.info({ trackedNumberId: tracked.id, status: mapped }, 'ingested presence');
}
