import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { processAppleNotification, verifyTransaction, userHasActiveSubscription } from '../../modules/billing/appstore.js';
import { prisma } from '../../config/prisma.js';
import { logger } from '../../config/logger.js';

const log = logger.child({ mod: 'billingRoutes' });

const VerifyBody = z.object({
  signedTransaction: z.string().min(20),
});

const NotificationBody = z.object({
  signedPayload: z.string().min(20),
});

const routes: FastifyPluginAsync = async (app) => {
  // Authenticated routes
  app.register(async (scope) => {
    scope.addHook('preHandler', scope.requireAuth);

    scope.post('/v1/billing/verify', async (req) => {
      const body = VerifyBody.parse(req.body);
      const result = await verifyTransaction(req.auth!.sub, body.signedTransaction);
      return { ok: true, ...result, expiresAt: result.expiresAt.toISOString() };
    });

    scope.get('/v1/billing/status', async (req) => {
      const isSubscribed = await userHasActiveSubscription(req.auth!.sub);
      const sub = await prisma.subscription.findFirst({
        where: { userId: req.auth!.sub },
        orderBy: { expiresAt: 'desc' },
      });
      return {
        isSubscribed,
        subscription: sub
          ? {
              productId: sub.productId,
              status: sub.status,
              expiresAt: sub.expiresAt.toISOString(),
              autoRenewEnabled: sub.autoRenewEnabled,
              environment: sub.environment,
            }
          : null,
      };
    });
  });

  // Public webhook for Apple S2S v2 notifications.
  app.post('/v1/billing/apple-notifications', async (req, reply) => {
    const body = NotificationBody.parse(req.body);
    try {
      await processAppleNotification(body.signedPayload);
      return reply.code(200).send({ ok: true });
    } catch (err) {
      log.error({ err }, 'apple notification processing failed');
      // Apple retries non-2xx; return 200 only if we definitely processed it.
      return reply.code(500).send({ ok: false });
    }
  });
};

export default routes;
