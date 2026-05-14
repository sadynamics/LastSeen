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

  /**
   * Self-diagnostic: how many devices does the server currently have on file
   * for the signed-in user? Powers the PushDiagnosticsView so the user can
   * verify the iOS -> backend handshake without needing admin credentials.
   */
  app.get('/v1/me/devices', async (req) => {
    const devices = await prisma.device.findMany({
      where: { userId: req.auth!.sub },
      orderBy: { lastSeenAt: 'desc' },
    });
    return {
      count: devices.length,
      items: devices.map((d) => ({
        id: d.id,
        tokenPrefix: d.apnsToken.slice(0, 12) + '…',
        environment: d.environment,
        appVersion: d.appVersion,
        osVersion: d.osVersion,
        lastSeenAt: d.lastSeenAt.toISOString(),
      })),
    };
  });

  /**
   * Self-diagnostic: send a test push to every device currently registered
   * for the signed-in user. Returns how many were targeted so the client can
   * report "sent to 1 device" / "no devices registered". Cheaper to diagnose
   * APNs problems than fishing through server logs.
   */
  app.post('/v1/me/test-push', async (req) => {
    const userId = req.auth!.sub;
    const { pushToUser } = await import('../../modules/push/apns.js');
    const devices = await prisma.device.findMany({ where: { userId } });
    await pushToUser(userId, {
      title: 'LastSeen test',
      body: 'If you can read this, push delivery is working.',
      data: { kind: 'test' },
    });
    return { devicesTargeted: devices.length };
  });
};

export default routes;
