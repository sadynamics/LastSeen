import { PrismaClient } from '@prisma/client';
import { env, isProduction } from './env.js';
import { logger } from './logger.js';

declare global {
  // eslint-disable-next-line no-var
  var __prisma: PrismaClient | undefined;
}

export const prisma: PrismaClient =
  globalThis.__prisma ??
  new PrismaClient({
    log: isProduction
      ? [{ emit: 'event', level: 'error' }]
      : [
          { emit: 'event', level: 'error' },
          { emit: 'event', level: 'warn' },
        ],
    datasources: { db: { url: env.DATABASE_URL } },
  });

// @ts-expect-error - Prisma's typed event emitter is awkward across versions.
prisma.$on('error', (e: { message: string }) => logger.error({ err: e.message }, 'prisma error'));

if (!isProduction) {
  globalThis.__prisma = prisma;
}
