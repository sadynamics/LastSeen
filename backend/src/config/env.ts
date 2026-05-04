import 'dotenv-flow/config';
import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),

  DATABASE_URL: z.string().url(),
  REDIS_URL: z.string().url(),

  S3_ENDPOINT: z.string().url().optional(),
  S3_REGION: z.string().default('us-east-1'),
  S3_ACCESS_KEY_ID: z.string(),
  S3_SECRET_ACCESS_KEY: z.string(),
  S3_BUCKET_BAILEYS: z.string(),
  S3_FORCE_PATH_STYLE: z
    .string()
    .optional()
    .transform((v) => v === 'true'),

  JWT_SECRET: z.string().min(32),
  JWT_ISSUER: z.string().default('lastseen.app'),
  JWT_AUDIENCE: z.string().default('lastseen-ios'),

  APPLE_BUNDLE_ID: z.string(),
  APPLE_TEAM_ID: z.string(),

  APPLE_INAPP_KEY_ID: z.string().optional().default(''),
  APPLE_INAPP_ISSUER_ID: z.string().optional().default(''),
  APPLE_INAPP_PRIVATE_KEY_BASE64: z.string().optional().default(''),
  APPLE_INAPP_ENVIRONMENT: z.enum(['Sandbox', 'Production']).default('Sandbox'),

  APNS_KEY_ID: z.string().optional().default(''),
  APNS_TEAM_ID: z.string().optional().default(''),
  APNS_PRIVATE_KEY_BASE64: z.string().optional().default(''),
  APNS_BUNDLE_ID: z.string().optional().default(''),
  APNS_ENVIRONMENT: z.enum(['development', 'production']).default('development'),

  ADMIN_BASIC_USER: z.string().default('admin'),
  ADMIN_BASIC_PASSWORD: z.string().min(8),

  SENTRY_DSN: z.string().optional().default(''),
  SENTRY_ENVIRONMENT: z.string().optional(),

  // Firebase Admin SDK (Firestore mirror). All three must be set together
  // for the sync to activate; otherwise it gracefully no-ops.
  FIREBASE_PROJECT_ID: z.string().optional().default(''),
  FIREBASE_CLIENT_EMAIL: z.string().optional().default(''),
  FIREBASE_PRIVATE_KEY: z.string().optional().default(''),
});

export type Env = z.infer<typeof schema>;

const parsed = schema.safeParse(process.env);
if (!parsed.success) {
  // eslint-disable-next-line no-console
  console.error('[config] Invalid environment:', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env: Env = parsed.data;

export const isProduction = env.NODE_ENV === 'production';
export const isTest = env.NODE_ENV === 'test';
