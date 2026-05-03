import pino from 'pino';
import { env, isProduction } from './env.js';

export const logger = pino({
  level: env.LOG_LEVEL,
  base: { service: 'lastseen-backend' },
  redact: {
    paths: [
      'req.headers.authorization',
      'req.headers.cookie',
      '*.identityToken',
      '*.signedTransactionInfo',
      '*.signedRenewalInfo',
      '*.apnsToken',
      '*.privateKey',
      '*.JWT_SECRET',
    ],
    censor: '[redacted]',
  },
  transport: isProduction
    ? undefined
    : {
        target: 'pino-pretty',
        options: {
          colorize: true,
          translateTime: 'HH:MM:ss.l',
          ignore: 'pid,hostname,service',
        },
      },
});

export type Logger = typeof logger;
