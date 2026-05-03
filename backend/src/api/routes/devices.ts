import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { prisma } from '../../config/prisma.js';

const RegisterBody = z.object({
  apnsToken: z.string().min(32).max(256),
  appVersion: z.string().max(32).optional(),
  osVersion: z.string().max(32).optional(),
  locale: z.string().max(16).optional(),
});

const routes: FastifyPluginAsync = async (app) => {
  app.addHook('preHandler', app.requireAuth);

  app.post('/v1/devices', async (req, reply) => {
    const body = RegisterBody.parse(req.body);
    const userId = req.auth!.sub;

    const device = await prisma.device.upsert({
      where: { apnsToken: body.apnsToken },
      create: {
        userId,
        apnsToken: body.apnsToken,
        appVersion: body.appVersion ?? null,
        osVersion: body.osVersion ?? null,
        locale: body.locale ?? null,
      },
      update: {
        userId,
        appVersion: body.appVersion ?? undefined,
        osVersion: body.osVersion ?? undefined,
        locale: body.locale ?? undefined,
        lastSeenAt: new Date(),
      },
    });

    return reply.send({ id: device.id });
  });

  app.delete('/v1/devices/:id', async (req, reply) => {
    const params = z.object({ id: z.string() }).parse(req.params);
    await prisma.device.deleteMany({ where: { id: params.id, userId: req.auth!.sub } });
    return reply.code(204).send();
  });
};

export default routes;
