import type { FastifyPluginAsync, FastifyReply, FastifyRequest } from 'fastify';
import fp from 'fastify-plugin';
import { verifySessionJwt, type SessionClaims } from '../../modules/auth/apple.js';
import { prisma } from '../../config/prisma.js';
import { UnauthorizedError, PaymentRequiredError } from '../../lib/errors.js';
import { userHasActiveSubscription } from '../../modules/billing/appstore.js';

declare module 'fastify' {
  interface FastifyRequest {
    auth?: SessionClaims;
    /** Cached entitlement check. */
    isSubscribed?: boolean;
  }
  interface FastifyInstance {
    requireAuth: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
    requireSubscription: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}

const plugin: FastifyPluginAsync = async (app) => {
  app.decorate('requireAuth', async (req: FastifyRequest, _reply: FastifyReply) => {
    const header = req.headers.authorization;
    if (!header?.startsWith('Bearer ')) {
      throw new UnauthorizedError('Missing bearer token');
    }
    const token = header.slice('Bearer '.length).trim();
    const claims = await verifySessionJwt(token);
    // Confirm user still exists and isn't deleted.
    const user = await prisma.user.findUnique({ where: { id: claims.sub }, select: { deletedAt: true } });
    if (!user || user.deletedAt) {
      throw new UnauthorizedError('Account not found');
    }
    req.auth = claims;
  });

  app.decorate('requireSubscription', async (req: FastifyRequest, _reply: FastifyReply) => {
    if (!req.auth) {
      throw new UnauthorizedError();
    }
    const ok = await userHasActiveSubscription(req.auth.sub);
    req.isSubscribed = ok;
    if (!ok) {
      throw new PaymentRequiredError();
    }
  });
};

export default fp(plugin, { name: 'auth' });
