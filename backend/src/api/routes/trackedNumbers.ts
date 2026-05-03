import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { prisma } from '../../config/prisma.js';
import { normalizePhone } from '../../lib/phone.js';
import { trackingQueue } from '../../modules/tracking/queues.js';
import { liveStatus, sessionsForDay, weeklyReport } from '../../modules/reports/queries.js';
import { NotFoundError, PaymentRequiredError } from '../../lib/errors.js';
import { userHasActiveSubscription } from '../../modules/billing/appstore.js';

const FREE_TIER_LIMIT = 1;

const CreateBody = z.object({
  phone: z.string().min(4).max(32),
  defaultCountry: z.string().length(2).optional(),
  displayName: z.string().min(1).max(64).optional(),
});

const PrefsBody = z.object({
  onlineEnabled: z.boolean().optional(),
  offlineEnabled: z.boolean().optional(),
  sessionEndedEnabled: z.boolean().optional(),
  dailySummaryEnabled: z.boolean().optional(),
  quietHoursStart: z.number().int().min(0).max(23).nullable().optional(),
  quietHoursEnd: z.number().int().min(0).max(23).nullable().optional(),
  timezone: z.string().max(64).nullable().optional(),
});

const routes: FastifyPluginAsync = async (app) => {
  app.addHook('preHandler', app.requireAuth);

  app.get('/v1/tracked-numbers', async (req) => {
    const userId = req.auth!.sub;
    const items = await prisma.trackedNumber.findMany({
      where: { userId, archivedAt: null },
      orderBy: { createdAt: 'asc' },
      include: { prefs: true, scraperAccount: { select: { status: true } } },
    });
    return { items };
  });

  app.post('/v1/tracked-numbers', async (req, reply) => {
    const body = CreateBody.parse(req.body);
    const userId = req.auth!.sub;

    const existing = await prisma.trackedNumber.count({
      where: { userId, archivedAt: null },
    });
    if (existing >= FREE_TIER_LIMIT) {
      const subscribed = await userHasActiveSubscription(userId);
      if (!subscribed) throw new PaymentRequiredError('Subscription required to add more numbers');
    }

    const parsed = normalizePhone(
      body.phone,
      body.defaultCountry as Parameters<typeof normalizePhone>[1],
    );

    const tracked = await prisma.trackedNumber.upsert({
      where: { userId_e164: { userId, e164: parsed.e164 } },
      create: {
        userId,
        e164: parsed.e164,
        jid: parsed.jid,
        countryCode: parsed.countryCode ?? null,
        displayName: body.displayName ?? null,
        prefs: { create: {} },
      },
      update: {
        archivedAt: null,
        displayName: body.displayName ?? undefined,
      },
    });

    await trackingQueue().add('track', { type: 'track', trackedNumberId: tracked.id });
    return reply.code(201).send({ item: tracked });
  });

  app.delete('/v1/tracked-numbers/:id', async (req, reply) => {
    const params = z.object({ id: z.string() }).parse(req.params);
    const userId = req.auth!.sub;
    const existing = await prisma.trackedNumber.findFirst({
      where: { id: params.id, userId },
    });
    if (!existing) throw new NotFoundError();
    await prisma.trackedNumber.update({
      where: { id: existing.id },
      data: { archivedAt: new Date() },
    });
    await trackingQueue().add('untrack', {
      type: 'untrack',
      trackedNumberId: existing.id,
      jid: existing.jid,
      scraperAccountId: existing.scraperAccountId,
    });
    return reply.code(204).send();
  });

  app.get('/v1/tracked-numbers/:id/live', async (req) => {
    const params = z.object({ id: z.string() }).parse(req.params);
    const userId = req.auth!.sub;
    const tn = await prisma.trackedNumber.findFirst({ where: { id: params.id, userId } });
    if (!tn) throw new NotFoundError();
    const status = await liveStatus(tn.id);
    return { trackedNumberId: tn.id, ...status };
  });

  app.get('/v1/tracked-numbers/:id/sessions', async (req) => {
    const params = z.object({ id: z.string() }).parse(req.params);
    const query = z
      .object({ day: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional() })
      .parse(req.query);
    const userId = req.auth!.sub;
    const tn = await prisma.trackedNumber.findFirst({ where: { id: params.id, userId } });
    if (!tn) throw new NotFoundError();
    const day = query.day ?? new Date().toISOString().slice(0, 10);
    return await sessionsForDay(tn.id, day);
  });

  app.get('/v1/tracked-numbers/:id/reports/weekly', async (req) => {
    const params = z.object({ id: z.string() }).parse(req.params);
    const query = z.object({ anchor: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional() }).parse(req.query);
    const userId = req.auth!.sub;
    const tn = await prisma.trackedNumber.findFirst({ where: { id: params.id, userId } });
    if (!tn) throw new NotFoundError();
    return await weeklyReport(tn.id, query.anchor);
  });

  app.put('/v1/tracked-numbers/:id/notifications', async (req) => {
    const params = z.object({ id: z.string() }).parse(req.params);
    const body = PrefsBody.parse(req.body);
    const userId = req.auth!.sub;
    const tn = await prisma.trackedNumber.findFirst({ where: { id: params.id, userId } });
    if (!tn) throw new NotFoundError();

    const prefs = await prisma.notificationPref.upsert({
      where: { trackedNumberId: tn.id },
      create: { trackedNumberId: tn.id, ...body },
      update: { ...body },
    });
    return { prefs };
  });
};

export default routes;
