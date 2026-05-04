import {
  Browsers,
  DisconnectReason,
  fetchLatestBaileysVersion,
  initAuthCreds,
  proto,
  type AuthenticationCreds,
  type AuthenticationState,
  type SignalDataTypeMap,
  type WASocket,
} from '@whiskeysockets/baileys';
import makeWASocket from '@whiskeysockets/baileys';
import { Boom } from '@hapi/boom';
import { EventEmitter } from 'node:events';
import pino from 'pino';
import { env } from '../../config/env.js';
import { logger as appLogger } from '../../config/logger.js';
import { s3GetText, s3PutText, s3Delete, s3ListUnder } from '../../config/s3.js';

/**
 * BaileysSession
 * --------------
 * Wraps a single WhatsApp account. Persists multi-file auth state to S3 so the
 * pairing survives restarts. Subscribes to presence updates for tracked JIDs
 * and emits typed events.
 *
 * Lifecycle:
 *   const s = new BaileysSession({ scraperId, authStateKey });
 *   await s.connect();
 *   const { qr } = await s.waitForQrIfNeeded();   // for unpaired sessions
 *   s.on('presence', ev => ...);
 *   await s.subscribe(jid);
 *   ...
 *   await s.disconnect();
 */

export type SessionStatus =
  | 'idle'
  | 'connecting'
  | 'awaiting_qr'
  | 'open'
  | 'closed'
  | 'banned'
  | 'logged_out';

export type SessionPresence = 'available' | 'unavailable' | 'composing' | 'recording' | 'paused';

export interface PresenceEventPayload {
  scraperId: string;
  jid: string;
  status: SessionPresence;
  ts: Date;
  lastKnownPresence?: number;
}

export interface BaileysSessionEvents {
  status: (s: SessionStatus) => void;
  qr: (qr: string) => void;
  presence: (ev: PresenceEventPayload) => void;
  paired: () => void;
  banned: (reason: string) => void;
  /** Fired when the session was closed and won't auto-reconnect. */
  terminated: (reason: string) => void;
}

export interface BaileysSessionOptions {
  scraperId: string;
  authStateKey: string;
  bucket: string;
  /** Optional pino-compatible logger override. */
  logger?: pino.Logger;
}

export class BaileysSession extends EventEmitter {
  public readonly scraperId: string;
  public status: SessionStatus = 'idle';
  public lastQr: string | null = null;

  private readonly authStateKey: string;
  private readonly bucket: string;
  private readonly log: pino.Logger;

  private sock: WASocket | null = null;
  private subscribed = new Set<string>();
  private reconnectAttempts = 0;
  private resolveQr: ((qr: string) => void) | null = null;
  private presenceKeepalive: NodeJS.Timeout | null = null;

  constructor(opts: BaileysSessionOptions) {
    super();
    this.scraperId = opts.scraperId;
    this.authStateKey = opts.authStateKey;
    this.bucket = opts.bucket;
    this.log = (opts.logger ?? appLogger).child({ scraperId: opts.scraperId, mod: 'baileys' });
  }

  override on<K extends keyof BaileysSessionEvents>(event: K, listener: BaileysSessionEvents[K]): this {
    return super.on(event, listener as (...args: unknown[]) => void);
  }

  override emit<K extends keyof BaileysSessionEvents>(
    event: K,
    ...args: Parameters<BaileysSessionEvents[K]>
  ): boolean {
    return super.emit(event, ...args);
  }

  async connect(): Promise<void> {
    if (this.status === 'connecting' || this.status === 'open') return;
    this.setStatus('connecting');

    const { state, saveCreds } = await this.useS3AuthState();
    const { version } = await fetchLatestBaileysVersion();

    this.sock = makeWASocket({
      version,
      auth: state,
      printQRInTerminal: false,
      browser: Browsers.macOS('Desktop'),
      logger: this.log.child({ baileys: true }) as unknown as pino.Logger,
      syncFullHistory: false,
      // CRITICAL: must be `true` for WhatsApp to push presence.update events.
      // When the scraper appears offline, WA's server stops fanning out
      // presence to "inactive" clients and presenceSubscribe is a no-op.
      markOnlineOnConnect: true,
      generateHighQualityLinkPreview: false,
      shouldIgnoreJid: (jid) => {
        // Ignore broadcast / status / newsletter to keep the socket quiet.
        return (
          jid?.endsWith('@broadcast') ||
          jid?.includes('status@') ||
          jid?.endsWith('@newsletter') ||
          false
        );
      },
    });

    this.sock.ev.on('creds.update', saveCreds);
    this.sock.ev.on('connection.update', (u) => this.handleConnectionUpdate(u));
    this.sock.ev.on('presence.update', (u) => this.handlePresenceUpdate(u));
  }

  async disconnect(): Promise<void> {
    this.stopPresenceKeepalive();
    try {
      await this.sock?.logout().catch(() => undefined);
    } finally {
      this.sock?.end(undefined);
      this.sock = null;
      this.setStatus('closed');
    }
  }

  async logoutAndWipe(): Promise<void> {
    await this.disconnect();
    const objects = await s3ListUnder(this.bucket, this.authStateKey + '/');
    for (const obj of objects) {
      if (obj.Key) {
        await s3Delete(this.bucket, obj.Key);
      }
    }
    this.setStatus('logged_out');
  }

  isOpen(): boolean {
    return this.status === 'open' && this.sock !== null;
  }

  /**
   * Resolves with the next QR code. If the session is already paired, resolves
   * immediately with `null`.
   */
  async waitForQr(timeoutMs = 60_000): Promise<string | null> {
    if (this.status === 'open') return null;
    if (this.lastQr) return this.lastQr;
    return await new Promise<string | null>((resolve, reject) => {
      const timer = setTimeout(() => {
        this.resolveQr = null;
        reject(new Error('QR wait timed out'));
      }, timeoutMs);
      this.resolveQr = (qr) => {
        clearTimeout(timer);
        this.resolveQr = null;
        resolve(qr);
      };
    });
  }

  /** Resolve a phone number to its WhatsApp JID, or null if not on WhatsApp. */
  async lookupJid(phoneE164: string): Promise<string | null> {
    const looked = await this.lookupJidWithLid(phoneE164);
    return looked?.jid ?? null;
  }

  /**
   * Resolve a phone number to BOTH its phone-form JID and its LID-form JID.
   * WhatsApp publishes presence updates keyed by the LID for many contacts,
   * so we need both to correctly attribute presence events to a tracked
   * number.
   */
  async lookupJidWithLid(phoneE164: string): Promise<{ jid: string; lid: string | null } | null> {
    if (!this.sock) throw new Error('Session not connected');
    const cleaned = phoneE164.replace(/^\+/, '');
    const res = await this.sock.onWhatsApp(cleaned);
    const first = res?.[0];
    if (!first?.exists) return null;
    const lid = typeof first.lid === 'string' && first.lid.length > 0 ? first.lid : null;
    return { jid: first.jid, lid };
  }

  /** Subscribe to presence updates for a JID. Idempotent. */
  async subscribe(jid: string): Promise<void> {
    if (!this.sock) throw new Error('Session not connected');
    if (this.subscribed.has(jid)) return;

    // Skip the scraper's own number — WhatsApp never broadcasts presence
    // for yourself, so subscribing is a guaranteed dead end.
    const ownJid = this.sock.user?.id;
    if (ownJid && normalizeJid(jid) === normalizeJid(ownJid)) {
      this.log.warn({ jid }, 'skipping subscribe to scraper own jid');
      return;
    }

    await this.sock.presenceSubscribe(jid);
    this.subscribed.add(jid);
    this.log.info({ jid }, 'presence subscribed');
  }

  /** Unsubscribe locally; Baileys has no explicit unsubscribe over the wire. */
  unsubscribe(jid: string): void {
    this.subscribed.delete(jid);
  }

  subscribedJids(): string[] {
    return [...this.subscribed];
  }

  // ---------------- internals ----------------

  private setStatus(s: SessionStatus): void {
    if (this.status === s) return;
    this.status = s;
    this.emit('status', s);
  }

  private handleConnectionUpdate(u: {
    connection?: 'open' | 'connecting' | 'close';
    qr?: string;
    lastDisconnect?: { error?: Error | Boom };
  }): void {
    const { connection, qr, lastDisconnect } = u;

    if (qr) {
      this.lastQr = qr;
      this.setStatus('awaiting_qr');
      this.emit('qr', qr);
      this.resolveQr?.(qr);
    }

    if (connection === 'open') {
      this.lastQr = null;
      this.reconnectAttempts = 0;
      this.setStatus('open');
      this.emit('paired');
      void this.startPresenceKeepalive();
      void this.resubscribeAll();
    }

    if (connection === 'close') {
      this.stopPresenceKeepalive();
      const boom = lastDisconnect?.error as Boom | undefined;
      const statusCode = boom?.output?.statusCode;
      // DisconnectReason is a numeric enum; reverse lookup gives the name.
      const reasonName: string =
        statusCode != null ? (DisconnectReason[statusCode as number] ?? 'unknown') : 'unknown';

      this.log.warn({ statusCode, reason: reasonName }, 'connection closed');

      if (statusCode === DisconnectReason.loggedOut) {
        // The account was logged out from another device or banned.
        this.setStatus('banned');
        this.emit('banned', reasonName);
        this.emit('terminated', reasonName);
        return;
      }

      // Backoff reconnect.
      this.reconnectAttempts += 1;
      const backoffMs = Math.min(60_000, 2_000 * 2 ** Math.min(this.reconnectAttempts, 5));
      setTimeout(() => {
        void this.connect().catch((err) => {
          this.log.error({ err }, 'reconnect failed');
        });
      }, backoffMs);
    }
  }

  private handlePresenceUpdate(u: {
    id: string;
    presences: { [jid: string]: { lastKnownPresence?: SessionPresence; lastSeen?: number } };
  }): void {
    for (const [jid, p] of Object.entries(u.presences)) {
      const status = p.lastKnownPresence;
      if (!status) {
        this.log.info({ jid, raw: p }, 'presence update without status');
        continue;
      }
      this.log.info({ jid, status, lastSeen: p.lastSeen }, 'presence event received');
      this.emit('presence', {
        scraperId: this.scraperId,
        jid,
        status,
        ts: new Date(),
        lastKnownPresence: p.lastSeen,
      });
    }
  }

  private async resubscribeAll(): Promise<void> {
    if (!this.sock) return;
    for (const jid of this.subscribed) {
      try {
        await this.sock.presenceSubscribe(jid);
      } catch (err) {
        this.log.warn({ err, jid }, 'resubscribe failed');
      }
    }
  }

  /**
   * Keep this scraper marked as "available" on WhatsApp's server. WA throttles
   * (and eventually drops) presence.update fan-out to clients that look idle,
   * so we re-assert availability + re-subscribe every 10 minutes.
   *
   * This is the standard pattern used by every WhatsApp tracker built on top
   * of Baileys / WhatsApp Web.
   */
  private async startPresenceKeepalive(): Promise<void> {
    if (this.presenceKeepalive) clearInterval(this.presenceKeepalive);
    const tick = async (): Promise<void> => {
      if (!this.sock || this.status !== 'open') return;
      try {
        await this.sock.sendPresenceUpdate('available');
        for (const jid of this.subscribed) {
          await this.sock.presenceSubscribe(jid).catch(() => undefined);
        }
      } catch (err) {
        this.log.warn({ err }, 'presence keepalive tick failed');
      }
    };
    await tick();
    this.presenceKeepalive = setInterval(() => void tick(), 10 * 60 * 1000);
  }

  private stopPresenceKeepalive(): void {
    if (this.presenceKeepalive) {
      clearInterval(this.presenceKeepalive);
      this.presenceKeepalive = null;
    }
  }

  /**
   * Custom Baileys auth-state backed by S3. Mirrors the `useMultiFileAuthState`
   * helper but reads/writes to object storage so the pool can be horizontally
   * scaled later.
   */
  private async useS3AuthState(): Promise<{
    state: AuthenticationState;
    saveCreds: () => Promise<void>;
  }> {
    const credsKey = `${this.authStateKey}/creds.json`;
    const credsRaw = await s3GetText(this.bucket, credsKey);
    const creds: AuthenticationCreds = credsRaw
      ? (JSON.parse(credsRaw, BufferReviver) as AuthenticationCreds)
      : initAuthCreds();

    const state: AuthenticationState = {
      creds,
      keys: {
        get: async <T extends keyof SignalDataTypeMap>(type: T, ids: string[]) => {
          const out: { [id: string]: SignalDataTypeMap[T] } = {};
          await Promise.all(
            ids.map(async (id) => {
              const key = `${this.authStateKey}/${type}-${id}.json`;
              const raw = await s3GetText(this.bucket, key);
              if (!raw) return;
              let value = JSON.parse(raw, BufferReviver) as SignalDataTypeMap[T];
              if (type === 'app-state-sync-key' && value) {
                value = proto.Message.AppStateSyncKeyData.fromObject(
                  value as unknown as object,
                ) as unknown as SignalDataTypeMap[T];
              }
              out[id] = value;
            }),
          );
          return out;
        },
        set: async (data) => {
          const tasks: Array<Promise<void>> = [];
          for (const category of Object.keys(data) as Array<keyof SignalDataTypeMap>) {
            const items = data[category];
            if (!items) continue;
            for (const id of Object.keys(items)) {
              const value = items[id];
              const key = `${this.authStateKey}/${category}-${id}.json`;
              if (value) {
                tasks.push(s3PutText(this.bucket, key, JSON.stringify(value, BufferReplacer)));
              } else {
                tasks.push(s3Delete(this.bucket, key));
              }
            }
          }
          await Promise.all(tasks);
        },
      },
    };

    const saveCreds = async (): Promise<void> => {
      await s3PutText(this.bucket, credsKey, JSON.stringify(creds, BufferReplacer));
    };

    return { state, saveCreds };
  }
}

/** Strip the device suffix (`:<n>`) WhatsApp adds to multi-device JIDs. */
function normalizeJid(jid: string): string {
  const [user, server] = jid.split('@');
  if (!user || !server) return jid;
  return `${user.split(':')[0]}@${server}`;
}

// JSON serialization helpers for Buffers (Baileys auth state contains many).
function BufferReplacer(_key: string, value: unknown): unknown {
  if (Buffer.isBuffer(value)) {
    return { type: 'Buffer', data: value.toString('base64') };
  }
  if (
    value &&
    typeof value === 'object' &&
    (value as { type?: string }).type === 'Buffer' &&
    Array.isArray((value as { data?: unknown }).data)
  ) {
    const data = (value as { data: number[] }).data;
    return { type: 'Buffer', data: Buffer.from(data).toString('base64') };
  }
  return value;
}

function BufferReviver(_key: string, value: unknown): unknown {
  if (
    value &&
    typeof value === 'object' &&
    (value as { type?: string }).type === 'Buffer' &&
    typeof (value as { data?: unknown }).data === 'string'
  ) {
    return Buffer.from((value as { data: string }).data, 'base64');
  }
  return value;
}

export const BAILEYS_BUCKET = env.S3_BUCKET_BAILEYS;
