import {
  AppStoreServerAPIClient,
  Environment,
  ReceiptUtility,
  SignedDataVerifier,
  type JWSTransactionDecodedPayload,
  type JWSRenewalInfoDecodedPayload,
  type ResponseBodyV2DecodedPayload,
} from '@apple/app-store-server-library';
import { Prisma, type SubscriptionStatus, type AppleEnvironment } from '@prisma/client';
import { env } from '../../config/env.js';
import { logger } from '../../config/logger.js';
import { prisma } from '../../config/prisma.js';

const log = logger.child({ mod: 'appstore' });

let _verifier: SignedDataVerifier | null = null;
let _client: AppStoreServerAPIClient | null = null;

function appleEnv(): Environment {
  return env.APPLE_INAPP_ENVIRONMENT === 'Production' ? Environment.PRODUCTION : Environment.SANDBOX;
}

function getVerifier(): SignedDataVerifier {
  if (!_verifier) {
    // Apple's root CA cert is bundled with the library; we just need bundleId + env.
    _verifier = new SignedDataVerifier(
      [],
      false, // disable online OCSP for dev; enable in production
      appleEnv(),
      env.APPLE_BUNDLE_ID,
      undefined,
    );
  }
  return _verifier;
}

function getClient(): AppStoreServerAPIClient | null {
  if (!env.APPLE_INAPP_KEY_ID || !env.APPLE_INAPP_PRIVATE_KEY_BASE64 || !env.APPLE_INAPP_ISSUER_ID) {
    return null;
  }
  if (!_client) {
    _client = new AppStoreServerAPIClient(
      Buffer.from(env.APPLE_INAPP_PRIVATE_KEY_BASE64, 'base64').toString('utf8'),
      env.APPLE_INAPP_KEY_ID,
      env.APPLE_INAPP_ISSUER_ID,
      env.APPLE_BUNDLE_ID,
      appleEnv(),
    );
  }
  return _client;
}

export interface VerifyResult {
  productId: string;
  originalTransactionId: string;
  expiresAt: Date;
  purchaseDate: Date;
  environment: AppleEnvironment;
}

/**
 * Verify a JWS-signed transaction the iOS app received from StoreKit 2.
 * Persists/updates the Subscription row.
 */
export async function verifyTransaction(userId: string, signedTransaction: string): Promise<VerifyResult> {
  const verifier = getVerifier();
  const decoded: JWSTransactionDecodedPayload = await verifier.verifyAndDecodeTransaction(signedTransaction);

  if (!decoded.originalTransactionId || !decoded.productId || !decoded.purchaseDate || !decoded.expiresDate) {
    throw new Error('Invalid transaction payload');
  }

  const expiresAt = new Date(decoded.expiresDate);
  const purchaseDate = new Date(decoded.purchaseDate);
  const environment: AppleEnvironment = decoded.environment === 'Production' ? 'Production' : 'Sandbox';
  const status: SubscriptionStatus = expiresAt.getTime() > Date.now() ? 'ACTIVE' : 'EXPIRED';

  await prisma.subscription.upsert({
    where: { originalTransactionId: decoded.originalTransactionId },
    create: {
      userId,
      productId: decoded.productId,
      originalTransactionId: decoded.originalTransactionId,
      latestTransactionId: decoded.transactionId ?? decoded.originalTransactionId,
      webOrderLineItemId: decoded.webOrderLineItemId ?? null,
      status,
      environment,
      purchaseDate,
      expiresAt,
      autoRenewEnabled: true,
      rawJws: signedTransaction,
    },
    update: {
      userId,
      productId: decoded.productId,
      latestTransactionId: decoded.transactionId ?? decoded.originalTransactionId,
      status,
      expiresAt,
      rawJws: signedTransaction,
    },
  });

  return {
    productId: decoded.productId,
    originalTransactionId: decoded.originalTransactionId,
    expiresAt,
    purchaseDate,
    environment,
  };
}

/**
 * Process an Apple Server-to-Server v2 notification. Apple sends these for
 * renewals, refunds, billing issues, etc.
 */
export async function processAppleNotification(signedPayload: string): Promise<void> {
  const verifier = getVerifier();
  const payload: ResponseBodyV2DecodedPayload = await verifier.verifyAndDecodeNotification(signedPayload);

  const notificationId = payload.notificationUUID ?? `${Date.now()}-${Math.random()}`;
  const existing = await prisma.appleNotification.findUnique({ where: { notificationId } });
  if (existing?.processedAt) {
    log.debug({ notificationId }, 'apple notification already processed');
    return;
  }

  const payloadJson = JSON.parse(JSON.stringify(payload)) as Prisma.InputJsonValue;
  const stored = await prisma.appleNotification.upsert({
    where: { notificationId },
    create: {
      notificationId,
      notificationType: payload.notificationType ?? 'UNKNOWN',
      subtype: payload.subtype ?? null,
      payload: payloadJson,
    },
    update: {
      notificationType: payload.notificationType ?? 'UNKNOWN',
      subtype: payload.subtype ?? null,
      payload: payloadJson,
    },
  });

  try {
    const txInfo = payload.data?.signedTransactionInfo
      ? await verifier.verifyAndDecodeTransaction(payload.data.signedTransactionInfo)
      : null;
    const renewalInfo: JWSRenewalInfoDecodedPayload | null = payload.data?.signedRenewalInfo
      ? await verifier.verifyAndDecodeRenewalInfo(payload.data.signedRenewalInfo)
      : null;

    if (txInfo?.originalTransactionId) {
      await applyTxToSubscription(txInfo, renewalInfo, payload.notificationType ?? '', payload.subtype ?? null);
    }

    await prisma.appleNotification.update({
      where: { id: stored.id },
      data: { processedAt: new Date() },
    });
  } catch (err) {
    log.error({ err, notificationId }, 'failed to process apple notification');
    await prisma.appleNotification.update({
      where: { id: stored.id },
      data: { error: err instanceof Error ? err.message : String(err) },
    });
    throw err;
  }
}

async function applyTxToSubscription(
  tx: JWSTransactionDecodedPayload,
  renewal: JWSRenewalInfoDecodedPayload | null,
  notificationType: string,
  subtype: string | null,
): Promise<void> {
  if (!tx.originalTransactionId || !tx.productId || !tx.expiresDate || !tx.purchaseDate) return;

  const status = mapStatus(notificationType, subtype, new Date(tx.expiresDate));
  const env: AppleEnvironment = tx.environment === 'Production' ? 'Production' : 'Sandbox';

  // Find the subscription. Apple notifications can arrive before the iOS-initiated
  // /verify call, so create a "pending" row with no userId if we've never seen it.
  const existing = await prisma.subscription.findUnique({
    where: { originalTransactionId: tx.originalTransactionId },
  });

  if (!existing) {
    log.warn(
      { originalTransactionId: tx.originalTransactionId },
      'apple notification for unknown subscription; storing for later reconciliation',
    );
    return;
  }

  await prisma.subscription.update({
    where: { originalTransactionId: tx.originalTransactionId },
    data: {
      productId: tx.productId,
      latestTransactionId: tx.transactionId ?? tx.originalTransactionId,
      status,
      expiresAt: new Date(tx.expiresDate),
      autoRenewEnabled: renewal?.autoRenewStatus === 1,
      autoRenewProductId: renewal?.autoRenewProductId ?? null,
      cancellationDate: tx.revocationDate ? new Date(tx.revocationDate) : null,
      cancellationReason: tx.revocationReason != null ? String(tx.revocationReason) : null,
      environment: env,
    },
  });
}

function mapStatus(notificationType: string, _subtype: string | null, expiresAt: Date): SubscriptionStatus {
  switch (notificationType) {
    case 'SUBSCRIBED':
    case 'DID_RENEW':
    case 'DID_CHANGE_RENEWAL_STATUS':
    case 'DID_CHANGE_RENEWAL_PREF':
      return expiresAt.getTime() > Date.now() ? 'ACTIVE' : 'EXPIRED';
    case 'EXPIRED':
      return 'EXPIRED';
    case 'GRACE_PERIOD_EXPIRED':
      return 'EXPIRED';
    case 'DID_FAIL_TO_RENEW':
      return 'IN_BILLING_RETRY';
    case 'OFFER_REDEEMED':
      return 'ACTIVE';
    case 'REFUND':
    case 'REVOKE':
      return 'REVOKED';
    case 'REFUND_DECLINED':
      return 'ACTIVE';
    default:
      return expiresAt.getTime() > Date.now() ? 'ACTIVE' : 'EXPIRED';
  }
}

export async function userHasActiveSubscription(userId: string): Promise<boolean> {
  const sub = await prisma.subscription.findFirst({
    where: { userId, status: { in: ['ACTIVE', 'IN_GRACE_PERIOD'] }, expiresAt: { gt: new Date() } },
  });
  return Boolean(sub);
}

/** Lookup an entitlement by originalTransactionId via the App Store Server API. */
export async function refreshFromAppStore(originalTransactionId: string): Promise<void> {
  const client = getClient();
  if (!client) {
    log.warn('app store server api not configured');
    return;
  }
  try {
    const tx = await client.getTransactionInfo(originalTransactionId);
    if (tx.signedTransactionInfo) {
      const sub = await prisma.subscription.findUnique({ where: { originalTransactionId } });
      if (sub) {
        await verifyTransaction(sub.userId, tx.signedTransactionInfo);
      }
    }
  } catch (err) {
    log.warn({ err }, 'refresh from app store failed');
  }
}

export const ReceiptUtilityRef = ReceiptUtility;
