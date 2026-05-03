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

  app.delete('/admin/scrapers/:id', async (req, reply) => {
    const params = z.object({ id: z.string() }).parse(req.params);
    await prisma.scraperAccount.update({
      where: { id: params.id },
      data: { status: 'RETIRED' },
    });
    return reply.code(204).send();
  });
};

export default routes;
