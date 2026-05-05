import apn from 'apn';
import { env } from '../../config/env.js';
import { logger } from '../../config/logger.js';
import { prisma } from '../../config/prisma.js';

const log = logger.child({ mod: 'apns' });

let _provider: apn.Provider | null = null;

function getProvider(): apn.Provider | null {
  if (!env.APNS_KEY_ID || !env.APNS_PRIVATE_KEY_BASE64 || !env.APNS_TEAM_ID) {
    return null;
  }
  if (!_provider) {
    _provider = new apn.Provider({
      token: {
        key: Buffer.from(env.APNS_PRIVATE_KEY_BASE64, 'base64'),
        keyId: env.APNS_KEY_ID,
        teamId: env.APNS_TEAM_ID,
      },
      production: env.APNS_ENVIRONMENT === 'production',
    });
  }
  return _provider;
}

export interface PushPayload {
  title: string;
  body: string;
  data?: Record<string, string>;
  threadId?: string;
  sound?: string;
}

export async function pushToUser(userId: string, payload: PushPayload): Promise<void> {
  const provider = getProvider();
  if (!provider) {
    log.warn({ userId }, 'apns not configured, skipping push');
    return;
  }

  const devices = await prisma.device.findMany({ where: { userId } });
  if (devices.length === 0) {
    log.info({ userId, title: payload.title }, 'push skipped: no devices registered for user');
    return;
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
    devices.map((d) => d.apnsToken),
  );

  log.info(
    {
      userId,
      title: payload.title,
      sent: results.sent.length,
      failed: results.failed.length,
    },
    'apns push attempted',
  );

  if (results.failed.length > 0) {
    log.warn({ failed: results.failed }, 'apns failures');
    // Cull permanent failures (BadDeviceToken, Unregistered).
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

export async function shutdownApns(): Promise<void> {
  _provider?.shutdown();
  _provider = null;
}
