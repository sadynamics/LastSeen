import * as Sentry from '@sentry/node';
import { env } from './env.js';

let initialized = false;

export function initSentry(): void {
  if (initialized || !env.SENTRY_DSN) return;
  Sentry.init({
    dsn: env.SENTRY_DSN,
    environment: env.SENTRY_ENVIRONMENT ?? env.NODE_ENV,
    tracesSampleRate: 0.1,
    profilesSampleRate: 0.0,
    sendDefaultPii: false,
    integrations: [],
  });
  initialized = true;
}

export const sentry = Sentry;
