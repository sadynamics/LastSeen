import { timingSafeEqual } from 'node:crypto';
import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { env } from '../../config/env.js';
import { logger } from '../../config/logger.js';
import { prisma } from '../../config/prisma.js';
import { issueSessionJwt, verifyAppleIdentityToken } from '../../modules/auth/apple.js';
import { upsertUser } from '../../modules/sync/firestoreSync.js';

const log = logger.child({ mod: 'authRoutes' });

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

    // Mirror customer to Firestore (fire-and-forget — never blocks the response).
    void upsertUser(user.id, {
      appleSub: verified.sub,
      email: user.email,
      locale: user.locale,
      createdAt: user.createdAt,
      lastSignInAt: new Date(),
    });

    return reply.send({
      token,
      user: { id: user.id, email: user.email, createdAt: user.createdAt.toISOString() },
    });
  });

  /**
   * App Review-only login. Validates a shared secret stored in
   * `REVIEWER_LOGIN_CODE` and returns a session JWT bound to a
   * Premium-flagged reviewer user. Disabled (404) whenever the env var is
   * unset, so flipping it off on Railway immediately closes the door
   * without redeploying the app.
   *
   * Accepts two payload shapes:
   * - `{ code }`            — legacy single-field path used by the hidden
   *                            triple-tap-on-the-logo sheet.
   * - `{ username, password }` — new path that maps cleanly to the
   *                            Username/Password fields Apple expects in
   *                            App Store Connect → Sign-In Information.
   *                            `username` is logged but otherwise ignored;
   *                            only `password` is matched (timing-safe)
   *                            against `REVIEWER_LOGIN_CODE`.
   */
  const ReviewerBody = z
    .object({
      code: z.string().min(1).max(128).optional(),
      username: z.string().min(1).max(128).optional(),
      password: z.string().min(1).max(128).optional(),
      locale: z.string().max(16).optional(),
    })
    .refine((b) => !!b.code || !!b.password, {
      message: 'code or password required',
    });

  app.post('/v1/auth/reviewer', {
    config: {
      // Tight per-IP cap so the endpoint can't be brute-forced even if the
      // secret somehow leaks. 10 attempts/min is plenty for one reviewer.
      rateLimit: { max: 10, timeWindow: '1 minute' },
    },
  }, async (req, reply) => {
    const expected = env.REVIEWER_LOGIN_CODE;
    if (!expected) {
      return reply.code(404).send({ code: 'NOT_FOUND', message: 'Not available' });
    }
    const body = ReviewerBody.parse(req.body);
    const supplied = body.password ?? body.code ?? '';
    const got = Buffer.from(supplied);
    const want = Buffer.from(expected);
    if (got.length !== want.length || !timingSafeEqual(got, want)) {
      log.warn(
        { ip: req.ip, username: body.username, shape: body.password ? 'pwd' : 'code' },
        'reviewer login: bad credential',
      );
      return reply.code(401).send({ code: 'UNAUTHORIZED', message: 'Invalid credentials' });
    }

    // Stable synthetic `appleSub` so re-submissions reuse the same row.
    const reviewerAppleSub = 'reviewer:apple-review';
    const user = await prisma.user.upsert({
      where: { appleSub: reviewerAppleSub },
      create: {
        appleSub: reviewerAppleSub,
        email: 'reviewer@apple-review.local',
        locale: body.locale ?? 'en-US',
        isReviewer: true,
      },
      update: {
        isReviewer: true,
        locale: body.locale ?? undefined,
        deletedAt: null,
      },
    });

    const token = await issueSessionJwt({ sub: user.id, appleSub: reviewerAppleSub });

    log.info(
      { userId: user.id, ip: req.ip, username: body.username, shape: body.password ? 'pwd' : 'code' },
      'reviewer login granted',
    );
    return reply.send({
      token,
      user: { id: user.id, email: user.email, createdAt: user.createdAt.toISOString() },
    });
  });
};

export default routes;
