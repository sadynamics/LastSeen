import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { timingSafeEqual } from 'node:crypto';
import qrcode from 'qrcode';
import { env } from '../../config/env.js';
import { prisma } from '../../config/prisma.js';
import { trackingQueue } from '../../modules/tracking/queues.js';
import { ForbiddenError } from '../../lib/errors.js';

const CreateScraperBody = z.object({
  label: z.string().min(1).max(64),
  proxyUrl: z.string().url().optional(),
  capacity: z.number().int().min(1).max(500).optional(),
});

function checkBasicAuth(authHeader: string | undefined): boolean {
  if (!authHeader?.startsWith('Basic ')) return false;
  const decoded = Buffer.from(authHeader.slice(6), 'base64').toString('utf8');
  const idx = decoded.indexOf(':');
  if (idx < 0) return false;
  const user = decoded.slice(0, idx);
  const pass = decoded.slice(idx + 1);
  const expected = `${env.ADMIN_BASIC_USER}:${env.ADMIN_BASIC_PASSWORD}`;
  const got = `${user}:${pass}`;
  if (got.length !== expected.length) return false;
  return timingSafeEqual(Buffer.from(got), Buffer.from(expected));
}

const routes: FastifyPluginAsync = async (app) => {
  app.addHook('preHandler', async (req, reply) => {
    if (!checkBasicAuth(req.headers.authorization)) {
      reply.header('WWW-Authenticate', 'Basic realm="lastseen-admin"');
      throw new ForbiddenError('Admin only');
    }
  });

  app.get('/admin/scrapers', async () => {
    const items = await prisma.scraperAccount.findMany({
      orderBy: { createdAt: 'desc' },
      include: {
        _count: {
          select: { trackedNumbers: { where: { archivedAt: null } } },
        },
      },
    });
    return { items };
  });

  app.post('/admin/scrapers', async (req, reply) => {
    const body = CreateScraperBody.parse(req.body);
    const acc = await prisma.scraperAccount.create({
      data: {
        label: body.label,
        proxyUrl: body.proxyUrl ?? null,
        capacity: body.capacity ?? 50,
        authStateKey: '', // filled below
        status: 'PAIRING',
      },
    });
    const updated = await prisma.scraperAccount.update({
      where: { id: acc.id },
      data: { authStateKey: `scrapers/${acc.id}` },
    });
    await trackingQueue().add('pair', { type: 'pair', scraperAccountId: acc.id });
    return reply.code(201).send({ item: updated });
  });

  app.get('/admin/scrapers/:id/qr', async (req, reply) => {
    const params = z.object({ id: z.string() }).parse(req.params);
    const query = z.object({ format: z.enum(['png', 'svg', 'json']).optional() }).parse(req.query);
    const acc = await prisma.scraperAccount.findUnique({ where: { id: params.id } });
    if (!acc) return reply.code(404).send({ error: 'not found' });

    // The QR is held in worker memory; we expose a Redis-backed pubsub channel.
    // For simplicity, the worker writes the latest QR to a Redis key when one is
    // emitted, and we read it here.
    const { getRedis } = await import('../../config/redis.js');
    const redis = getRedis();
    const qr = await redis.get(`scraper:${acc.id}:qr`);
    if (!qr) return reply.code(404).send({ error: 'no qr available; (re)pair via POST /admin/scrapers/:id/pair' });

    if (query.format === 'json') {
      return reply.send({ qr, scraperId: acc.id, status: acc.status });
    }
    if (query.format === 'svg') {
      const svg = await qrcode.toString(qr, { type: 'svg', width: 320 });
      return reply.type('image/svg+xml').send(svg);
    }
    const png = await qrcode.toBuffer(qr, { width: 320 });
    return reply.type('image/png').send(png);
  });

  app.post('/admin/scrapers/:id/pair', async (req, reply) => {
    const params = z.object({ id: z.string() }).parse(req.params);
    await trackingQueue().add('pair', { type: 'pair', scraperAccountId: params.id });
    return reply.code(202).send({ ok: true });
  });

  /**
   * Force a scraper out of WARMING into HEALTHY immediately. Use to bypass
   * the 24h cooldown when you need to test or want to ship faster.
   */
  app.post('/admin/scrapers/:id/promote', async (req, reply) => {
    const params = z.object({ id: z.string() }).parse(req.params);
    const { scraperPool } = await import('../../modules/tracking/scraperPool.js');
    const updated = await scraperPool.forcePromote(params.id);
    if (!updated) return reply.code(404).send({ error: 'not found' });

    // Kick the worker so any orphan tracked numbers get picked up immediately.
    const orphans = await prisma.trackedNumber.findMany({
      where: { archivedAt: null, scraperAccountId: null },
      select: { id: true },
    });
    for (const o of orphans) {
      await trackingQueue().add('track', { type: 'track', trackedNumberId: o.id });
    }
    return reply.send({ item: updated, reattached: orphans.length });
  });

  /**
   * Re-enqueue every active tracked number. Subscribe is idempotent on the
   * Baileys side, so this is safe to call any time. Also promotes any
   * WARMING scrapers whose cooldown has expired and detaches numbers stuck
   * on retired/banned scrapers so they can be reassigned.
   */
  app.post('/admin/scrapers/reconcile', async (_req, reply) => {
    const { scraperPool } = await import('../../modules/tracking/scraperPool.js');
    const promoted = await scraperPool.promoteReadyScrapers();

    const detach = await prisma.trackedNumber.updateMany({
      where: {
        archivedAt: null,
        scraperAccount: { status: { in: ['RETIRED', 'BANNED'] } },
      },
      data: { scraperAccountId: null },
    });

    const all = await prisma.trackedNumber.findMany({
      where: { archivedAt: null },
      select: { id: true },
    });
    for (const t of all) {
      await trackingQueue().add('track', { type: 'track', trackedNumberId: t.id });
    }
    return reply.send({ promoted, detached: detach.count, requeued: all.length });
  });

  app.delete('/admin/scrapers/:id', async (req, reply) => {
    const params = z.object({ id: z.string() }).parse(req.params);
    // Free the unique identity fields (`phoneE164`, `jid`) on retire — they
    // hold the @unique slot otherwise, which means re-pairing the same WA
    // account on a fresh row crashes the worker on `prisma.update` with a
    // P2002 (unique constraint violation). We also detach any tracked numbers
    // still pointing at this scraper so they can be reassigned elsewhere.
    await prisma.scraperAccount.update({
      where: { id: params.id },
      data: { status: 'RETIRED', jid: null, phoneE164: null },
    });
    await prisma.trackedNumber.updateMany({
      where: { scraperAccountId: params.id, archivedAt: null },
      data: { scraperAccountId: null },
    });
    return reply.code(204).send();
  });

  /**
   * Diagnostic: list devices currently registered for a user. Use to verify
   * the iOS app is actually POSTing /v1/devices.
   */
  app.get('/admin/users/:userId/devices', async (req, reply) => {
    const params = z.object({ userId: z.string() }).parse(req.params);
    const devices = await prisma.device.findMany({
      where: { userId: params.userId },
      orderBy: { lastSeenAt: 'desc' },
    });
    return reply.send({
      items: devices.map((d) => ({
        id: d.id,
        tokenPrefix: d.apnsToken.slice(0, 12) + '…',
        appVersion: d.appVersion,
        osVersion: d.osVersion,
        locale: d.locale,
        lastSeenAt: d.lastSeenAt,
      })),
    });
  });

  /**
   * Diagnostic: send a test push to every device for a user. Returns the
   * number of devices targeted.
   */
  app.post('/admin/users/:userId/test-push', async (req, reply) => {
    const params = z.object({ userId: z.string() }).parse(req.params);
    const body = z
      .object({ title: z.string().optional(), body: z.string().optional() })
      .parse(req.body ?? {});
    const { pushToUser } = await import('../../modules/push/apns.js');
    const devices = await prisma.device.findMany({ where: { userId: params.userId } });
    await pushToUser(params.userId, {
      title: body.title ?? 'LastSeen test',
      body: body.body ?? 'If you can read this, push delivery is working.',
      data: { kind: 'test' },
    });
    return reply.send({ devicesTargeted: devices.length });
  });

  /**
   * Diagnostic: list all users + their device counts. Quick way to spot
   * whether anyone's registered for push at all.
   */
  app.get('/admin/users', async (_req, reply) => {
    const users = await prisma.user.findMany({
      orderBy: { createdAt: 'desc' },
      select: {
        id: true,
        email: true,
        createdAt: true,
        deletedAt: true,
        _count: { select: { devices: true, trackedNumbers: true } },
      },
    });
    return reply.send({ items: users });
  });
};

export default routes;
