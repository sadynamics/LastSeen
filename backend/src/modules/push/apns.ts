import apn from 'apn';
import { env } from '../../config/env.js';
import { logger } from '../../config/logger.js';
import { prisma } from '../../config/prisma.js';

const log = logger.child({ mod: 'apns' });

const _providers: { production?: apn.Provider; development?: apn.Provider } = {};

function getProvider(environment: 'production' | 'development'): apn.Provider | null {
  if (!env.APNS_KEY_ID || !env.APNS_PRIVATE_KEY_BASE64 || !env.APNS_TEAM_ID) {
    return null;
  }
  if (!_providers[environment]) {
    _providers[environment] = new apn.Provider({
      token: {
        key: Buffer.from(env.APNS_PRIVATE_KEY_BASE64, 'base64'),
        keyId: env.APNS_KEY_ID,
        teamId: env.APNS_TEAM_ID,
      },
      production: environment === 'production',
    });
  }
  return _providers[environment]!;
}

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
  threadId?: string;
  sound?: string;
}

export async function pushToUser(userId: string, payload: PushPayload): Promise<void> {
  const devices = await prisma.device.findMany({ where: { userId } });
  if (devices.length === 0) {
    log.info({ userId, title: payload.title }, 'push skipped: no devices registered for user');
    return;
  }

  // Group by environment so each device hits the matching APNs gateway.
  // Sending a development token to the production gateway (or vice versa)
  // returns BadDeviceToken and the push silently fails.
  const byEnv = new Map<'production' | 'development', typeof devices>();
  for (const d of devices) {
    const e = (d.environment === 'development' ? 'development' : 'production') as
      | 'production'
      | 'development';
    const list = byEnv.get(e) ?? [];
    list.push(d);
    byEnv.set(e, list);
  }

  for (const [environment, group] of byEnv.entries()) {
    const provider = getProvider(environment);
    if (!provider) {
      log.warn({ userId, environment }, 'apns not configured, skipping push');
      continue;
    }

    const note = new apn.Notification();
    note.alert = { title: payload.title, body: payload.body };
    note.sound = payload.sound ?? 'default';
    note.topic = env.APNS_BUNDLE_ID;
    note.expiry = Math.floor(Date.now() / 1000) + 3600;
    note.priority = 10;
    note.contentAvailable = false;
    if (payload.threadId) note.threadId = payload.threadId;
    if (payload.data) note.payload = { ...payload.data };

    const results = await provider.send(
      note,
      group.map((d) => d.apnsToken),
    );

    log.info(
      {
        userId,
        environment,
        title: payload.title,
        sent: results.sent.length,
        failed: results.failed.length,
      },
      'apns push attempted',
    );

    if (results.failed.length > 0) {
      log.warn({ failed: results.failed }, 'apns failures');
      const dead = results.failed
        .filter((f) => {
          const reason = f.response?.reason ?? '';
          return reason === 'BadDeviceToken' || reason === 'Unregistered';
        })
        .map((f) => f.device);
      if (dead.length > 0) {
        log.info({ count: dead.length }, 'culling dead apns tokens');
        await prisma.device.deleteMany({ where: { apnsToken: { in: dead } } });
      }
    }
  }
}

export async function shutdownApns(): Promise<void> {
  _providers.production?.shutdown();
  _providers.development?.shutdown();
  delete _providers.production;
  delete _providers.development;
}
