import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { prisma } from '../../config/prisma.js';
import { issueSessionJwt, verifyAppleIdentityToken } from '../../modules/auth/apple.js';

const SignInBody = z.object({
  identityToken: z.string().min(10),
  fullName: z
    .object({
      givenName: z.string().nullable().optional(),
      familyName: z.string().nullable().optional(),
    })
    .optional(),
  email: z.string().email().nullable().optional(),
  locale: z.string().max(16).optional(),
});

const routes: FastifyPluginAsync = async (app) => {
  app.post('/v1/auth/apple', async (req, reply) => {
    const body = SignInBody.parse(req.body);
    const verified = await verifyAppleIdentityToken(body.identityToken);

    const user = await prisma.user.upsert({
      where: { appleSub: verified.sub },
      create: {
        appleSub: verified.sub,
        email: verified.email ?? body.email ?? null,
        locale: body.locale ?? null,
      },
      update: {
        email: verified.email ?? body.email ?? undefined,
        locale: body.locale ?? undefined,
        deletedAt: null,
      },
    });

    const token = await issueSessionJwt({ sub: user.id, appleSub: verified.sub });
    return reply.send({
      token,
      user: { id: user.id, email: user.email, createdAt: user.createdAt.toISOString() },
    });
  });
};

export default routes;
