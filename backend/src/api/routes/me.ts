import type { FastifyPluginAsync } from 'fastify';
import { prisma } from '../../config/prisma.js';
import { markUserDeleted } from '../../modules/sync/firestoreSync.js';

const routes: FastifyPluginAsync = async (app) => {
  app.addHook('preHandler', app.requireAuth);

  app.get('/v1/me', async (req) => {
    const user = await prisma.user.findUnique({
      where: { id: req.auth!.sub },
      include: {
        subscriptions: {
          orderBy: { expiresAt: 'desc' },
          take: 1,
        },
        _count: {
          select: { trackedNumbers: { where: { archivedAt: null } } },
        },
      },
    });
    if (!user) {
      return { user: null };
    }
    const sub = user.subscriptions[0] ?? null;
    return {
      user: {
        id: user.id,
        email: user.email,
        locale: user.locale,
        createdAt: user.createdAt.toISOString(),
        trackedNumbersCount: user._count.trackedNumbers,
      },
      subscription: sub
        ? {
            productId: sub.productId,
            status: sub.status,
            expiresAt: sub.expiresAt.toISOString(),
            autoRenewEnabled: sub.autoRenewEnabled,
          }
        : null,
    };
  });

  app.delete('/v1/me', async (req, reply) => {
    const userId = req.auth!.sub;
    // Soft-delete: cascade deletes via Prisma will remove devices, tracked numbers,
    // events, rollups, subscriptions linked by FK with onDelete: Cascade.
    await prisma.user.update({
      where: { id: userId },
      data: { deletedAt: new Date(), email: null },
    });
    await prisma.device.deleteMany({ where: { userId } });
    await prisma.trackedNumber.updateMany({
      where: { userId, archivedAt: null },
      data: { archivedAt: new Date() },
    });

    void markUserDeleted(userId);

    return reply.code(204).send();
  });
};

export default routes;
