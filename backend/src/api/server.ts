import Fastify, {
  type FastifyBaseLogger,
  type FastifyError,
  type FastifyRequest,
} from 'fastify';
import sensible from '@fastify/sensible';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { ZodError } from 'zod';
import { env, isProduction } from '../config/env.js';
import { logger } from '../config/logger.js';
import { initSentry, sentry } from '../config/sentry.js';
import authPlugin from './plugins/auth.js';
import authRoutes from './routes/auth.js';
import devicesRoutes from './routes/devices.js';
import trackedNumbersRoutes from './routes/trackedNumbers.js';
import billingRoutes from './routes/billing.js';
import meRoutes from './routes/me.js';
import adminRoutes from './routes/admin.js';
import { AppError } from '../lib/errors.js';

export async function buildApp() {
  const app = Fastify({
    logger: logger as unknown as FastifyBaseLogger,
    requestIdHeader: 'x-request-id',
    requestIdLogLabel: 'reqId',
    disableRequestLogging: false,
    trustProxy: isProduction,
    bodyLimit: 1024 * 1024 * 2,
  });

  await app.register(sensible);
  await app.register(helmet, {
    contentSecurityPolicy: false,
    crossOriginResourcePolicy: { policy: 'cross-origin' },
  });
  await app.register(cors, {
    origin: true,
    credentials: false,
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  });
  await app.register(rateLimit, {
    max: 600,
    timeWindow: '1 minute',
    keyGenerator: (req: FastifyRequest) => {
      const auth = req.headers.authorization;
      return auth ? `t:${auth.slice(-16)}` : (req.ip ?? 'anon');
    },
  });

  await app.register(authPlugin);

  app.get('/health', async () => ({
    ok: true,
    service: 'lastseen-backend',
    ts: new Date().toISOString(),
  }));

  await app.register(authRoutes);
  await app.register(devicesRoutes);
  await app.register(trackedNumbersRoutes);
  await app.register(billingRoutes);
  await app.register(meRoutes);
  await app.register(adminRoutes);

  app.setErrorHandler((err, req, reply) => {
    if (err instanceof ZodError) {
      return reply.code(400).send({
        code: 'VALIDATION_ERROR',
        message: 'Invalid request body',
        errors: err.flatten().fieldErrors,
      });
    }
    if (err instanceof AppError) {
      return reply.code(err.statusCode).send({
        code: err.code,
        message: err.message,
        details: err.details,
      });
    }
    req.log.error({ err }, 'unhandled error');
    if (env.SENTRY_DSN) {
      sentry.captureException(err);
    }
    return reply.code((err as FastifyError).statusCode ?? 500).send({
      code: 'INTERNAL_ERROR',
      message: isProduction ? 'Internal server error' : err.message,
    });
  });

  return app;
}

async function main(): Promise<void> {
  initSentry();
  const app = await buildApp();
  try {
    await app.listen({ host: '0.0.0.0', port: env.PORT });
    logger.info({ port: env.PORT }, 'api started');
  } catch (err) {
    logger.error({ err }, 'failed to start api');
    process.exit(1);
  }

  for (const sig of ['SIGINT', 'SIGTERM'] as const) {
    process.on(sig, async () => {
      logger.info({ sig }, 'shutting down api');
      await app.close();
      process.exit(0);
    });
  }
}

if (import.meta.url === `file://${process.argv[1]}`) {
  void main();
}
