import { ulid } from 'ulidx';
import { prisma } from '../../config/prisma.js';
import { logger } from '../../config/logger.js';
import { env } from '../../config/env.js';
import { getRedis } from '../../config/redis.js';
import { BaileysSession } from './baileysSession.js';
import type { ScraperAccount } from '@prisma/client';

const log = logger.child({ mod: 'scraperPool' });

/**
 * In-process registry of live Baileys sessions, keyed by ScraperAccount.id.
 * One worker process owns the pool. The API process talks to the worker via
 * the BullMQ queue (jobs: `track`, `untrack`, `pair`, `wipe`).
 */
export class ScraperPool {
  private readonly sessions = new Map<string, BaileysSession>();
  private onPresence?: (ev: import('./baileysSession.js').PresenceEventPayload) => void;

  setPresenceHandler(fn: (ev: import('./baileysSession.js').PresenceEventPayload) => void): void {
    this.onPresence = fn;
  }

  async bootstrap(): Promise<void> {
    const accounts = await prisma.scraperAccount.findMany({
      where: { status: { in: ['HEALTHY', 'WARMING', 'PAIRING', 'COOLING'] } },
    });
    log.info({ count: accounts.length }, 'bootstrapping scraper pool');
    for (const acc of accounts) {
      try {
        await this.start(acc);
      } catch (err) {
        log.error({ err, scraperId: acc.id }, 'failed to start scraper');
      }
    }
  }

  async createNew(label: string): Promise<ScraperAccount> {
    const id = ulid();
    const acc = await prisma.scraperAccount.create({
      data: {
        id,
        label,
        authStateKey: `scrapers/${id}`,
        status: 'PAIRING',
      },
    });
    await this.start(acc);
    return acc;
  }

  async start(acc: ScraperAccount): Promise<BaileysSession> {
    if (this.sessions.has(acc.id)) {
      return this.sessions.get(acc.id) as BaileysSession;
    }
    const session = new BaileysSession({
      scraperId: acc.id,
      authStateKey: acc.authStateKey,
      bucket: env.S3_BUCKET_BAILEYS,
    });

    session.on('qr', (qr) => {
      const redis = getRedis();
      void redis
        .set(`scraper:${acc.id}:qr`, qr, 'EX', 120)
        .catch((err) => log.error({ err, scraperId: acc.id }, 'failed to cache QR'));
      log.info({ scraperId: acc.id }, 'QR emitted; cached for 120s');
    });

    session.on('paired', () => {
      const redis = getRedis();
      void redis.del(`scraper:${acc.id}:qr`).catch(() => undefined);
      // CRITICAL: any throw here propagates as an unhandled rejection and
      // crashes the worker process. We've been bitten by exactly this:
      // a unique-constraint conflict on phoneE164 (when the same WA account
      // was previously paired on a now-banned/retired scraper row that still
      // owned the unique field) cascaded into a Node.js process exit, which
      // Railway then restart-loops until it gives up. Always swallow.
      void this.onPaired(acc.id, session).catch((err) => {
        log.error({ err, scraperId: acc.id }, 'onPaired handler failed; session stays open');
      });
    });

    session.on('banned', (reason) => {
      // Free the unique identity fields so a fresh scraper paired with the
      // same WhatsApp account (or even the same number on a fresh SIM after
      // recovery) doesn't blow up on the @unique constraint.
      void prisma.scraperAccount
        .update({
          where: { id: acc.id },
          data: { status: 'BANNED', banReason: reason, jid: null, phoneE164: null },
        })
        .catch((err) => log.error({ err }, 'mark banned failed'));
      this.sessions.delete(acc.id);
    });

    session.on('terminated', () => {
      this.sessions.delete(acc.id);
    });

    session.on('presence', (ev) => {
      this.onPresence?.(ev);
    });

    this.sessions.set(acc.id, session);
    await session.connect();
    return session;
  }

  get(scraperId: string): BaileysSession | undefined {
    return this.sessions.get(scraperId);
  }

  /**
   * Pick the best scraper to assign a new tracked number to. Strategy: the
   * healthy scraper with the most remaining capacity; ties broken by oldest
   * lastHeartbeat to spread load.
   */
  async assignScraper(): Promise<ScraperAccount | null> {
    // Promote any WARMING accounts whose warmup window has expired before
    // we filter for HEALTHY ones, so newly-paired scrapers automatically
    // become assignable as soon as their cooldown ends.
    await this.promoteReadyScrapers();

    const candidates = await prisma.scraperAccount.findMany({
      where: { status: 'HEALTHY' },
      include: { _count: { select: { trackedNumbers: { where: { archivedAt: null } } } } },
      orderBy: { lastHeartbeat: 'asc' },
    });
    const ranked = candidates
      .map((c) => ({ acc: c, free: c.capacity - c._count.trackedNumbers }))
      .filter((c) => c.free > 0)
      .sort((a, b) => b.free - a.free);
    return ranked[0]?.acc ?? null;
  }

  /**
   * Flip any WARMING scrapers whose `warmupUntil` has passed to HEALTHY.
   * Cheap idempotent maintenance; safe to call frequently.
   */
  async promoteReadyScrapers(): Promise<number> {
    const result = await prisma.scraperAccount.updateMany({
      where: {
        status: 'WARMING',
        OR: [{ warmupUntil: null }, { warmupUntil: { lte: new Date() } }],
      },
      data: { status: 'HEALTHY' },
    });
    if (result.count > 0) {
      log.info({ promoted: result.count }, 'promoted scrapers WARMING -> HEALTHY');
    }
    return result.count;
  }

  /**
   * Force a specific scraper to HEALTHY immediately, bypassing warmup.
   * Used by the admin endpoint when you need to test right away.
   */
  async forcePromote(scraperId: string): Promise<ScraperAccount | null> {
    const updated = await prisma.scraperAccount.update({
      where: { id: scraperId },
      data: { status: 'HEALTHY', warmupUntil: null },
    });
    log.info({ scraperId }, 'force-promoted scraper to HEALTHY');
    return updated;
  }

  async stop(scraperId: string): Promise<void> {
    const s = this.sessions.get(scraperId);
    if (!s) return;
    await s.disconnect();
    this.sessions.delete(scraperId);
  }

  async stopAll(): Promise<void> {
    await Promise.all([...this.sessions.values()].map((s) => s.disconnect().catch(() => undefined)));
    this.sessions.clear();
  }

  private async onPaired(scraperId: string, session: BaileysSession): Promise<void> {
    const phoneJid = session['sock']?.user?.id; // TS-friendly via private peek
    const e164 = phoneJid ? '+' + phoneJid.split('@')[0]!.split(':')[0]! : null;

    // Distinguish a *first* pair from a reconnect of an already-paired account.
    // Only first pairs should trigger the WARMING cooldown — otherwise every
    // worker restart would reset the warmup clock indefinitely.
    const existing = await prisma.scraperAccount.findUnique({
      where: { id: scraperId },
      select: { status: true, jid: true, warmupUntil: true },
    });
    const isFirstPair = !existing?.jid || existing.status === 'PAIRING';

    // If another (typically RETIRED/BANNED) scraper row still owns the same
    // `phoneE164` or `jid`, the unique constraint will fire and crash the
    // process. Null those fields on any conflicting row before we claim them.
    // This also covers the case where a banned scraper was retired manually
    // via DELETE /admin/scrapers/:id (which historically only flipped status).
    if (e164 || phoneJid) {
      const stolen = await prisma.scraperAccount.updateMany({
        where: {
          AND: [
            { id: { not: scraperId } },
            {
              OR: [
                e164 ? { phoneE164: e164 } : { phoneE164: '__never__' },
                phoneJid ? { jid: phoneJid } : { jid: '__never__' },
              ],
            },
          ],
        },
        data: { phoneE164: null, jid: null },
      });
      if (stolen.count > 0) {
        log.warn(
          { scraperId, e164, phoneJid, stolen: stolen.count },
          'reclaimed phoneE164/jid from prior scraper row',
        );
      }
    }

    if (isFirstPair) {
      await prisma.scraperAccount.update({
        where: { id: scraperId },
        data: {
          status: 'WARMING',
          warmupUntil: new Date(Date.now() + 1000 * 60 * 60 * 24),
          lastHeartbeat: new Date(),
          jid: phoneJid ?? null,
          phoneE164: e164,
        },
      });
    } else {
      // Reconnect: keep existing status (HEALTHY / WARMING / COOLING),
      // just refresh the heartbeat and identity fields.
      await prisma.scraperAccount.update({
        where: { id: scraperId },
        data: {
          lastHeartbeat: new Date(),
          jid: phoneJid ?? existing.jid ?? null,
          phoneE164: e164 ?? undefined,
        },
      });
    }
    // Re-subscribe to all existing tracked numbers assigned to this scraper.
    // CRITICAL: subscribe under BOTH the phone-JID and the LID. WhatsApp fans
    // out presence events keyed under either form, and which one it picks for
    // a given contact can change. If we only re-subscribe under `jid` after a
    // reconnect/deploy, we silently stop receiving presence for every contact
    // whose updates are LID-keyed — which means "Came online" pushes never
    // fire for those users until somebody manually re-tracks the number.
    const tracked = await prisma.trackedNumber.findMany({
      where: { scraperAccountId: scraperId, archivedAt: null },
      select: { id: true, jid: true, lid: true },
    });
    for (const t of tracked) {
      if (t.jid) {
        await session
          .subscribe(t.jid)
          .catch((err) => log.warn({ err, trackedNumberId: t.id, jid: t.jid }, 'resubscribe jid failed'));
      }
      if (t.lid) {
        await session
          .subscribe(t.lid)
          .catch((err) => log.warn({ err, trackedNumberId: t.id, lid: t.lid }, 'resubscribe lid failed'));
      }
    }
    log.info({ scraperId, count: tracked.length }, 'resubscribed tracked numbers after pair');
  }
}

export const scraperPool = new ScraperPool();
