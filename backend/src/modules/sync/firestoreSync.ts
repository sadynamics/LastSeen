import { FieldValue } from 'firebase-admin/firestore';
import { firestore } from '../../config/firebase.js';
import { logger } from '../../config/logger.js';

const log = logger.child({ mod: 'firestoreSync' });

/**
 * Mirrors customer-relevant data from Postgres → Firestore.
 *
 * Schema:
 *   users/{userId}
 *     appleSub, email, locale, createdAt, lastSignInAt, deletedAt,
 *     trackedCount, subscription: { ... }, lifetimeRevenueCents
 *
 *   users/{userId}/purchases/{originalTransactionId}
 *     productId, status, purchaseDate, expiresAt, environment,
 *     autoRenewEnabled, cancellationDate, cancellationReason, updatedAt
 *
 * Every public function is fire-and-forget by default — we never let a Firebase
 * outage block the API response. The caller should `void` the returned promise
 * unless it explicitly cares about completion (e.g. tests).
 */

export interface UpsertUserFields {
  appleSub?: string | null;
  email?: string | null;
  locale?: string | null;
  createdAt?: Date;
  lastSignInAt?: Date;
}

export async function upsertUser(userId: string, fields: UpsertUserFields): Promise<void> {
  const fs = firestore();
  if (!fs) return;
  try {
    const doc = fs.collection('users').doc(userId);
    await doc.set(
      {
        ...stripUndefined({
          appleSub: fields.appleSub ?? undefined,
          email: fields.email ?? undefined,
          locale: fields.locale ?? undefined,
          createdAt: fields.createdAt ?? undefined,
          lastSignInAt: fields.lastSignInAt ?? FieldValue.serverTimestamp(),
        }),
        deletedAt: null,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (err) {
    log.warn({ err, userId }, 'firestore upsertUser failed');
  }
}

export async function markUserDeleted(userId: string): Promise<void> {
  const fs = firestore();
  if (!fs) return;
  try {
    await fs.collection('users').doc(userId).set(
      {
        email: null,
        deletedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (err) {
    log.warn({ err, userId }, 'firestore markUserDeleted failed');
  }
}

export interface SubscriptionUpdate {
  originalTransactionId: string;
  latestTransactionId?: string | null;
  productId: string;
  status: string;
  environment: string;
  purchaseDate?: Date | null;
  expiresAt: Date;
  autoRenewEnabled?: boolean;
  cancellationDate?: Date | null;
  cancellationReason?: string | null;
}

/**
 * Upserts both the user's "current subscription" snapshot AND a per-transaction
 * row in `users/{userId}/purchases`. Idempotent.
 */
export async function updateSubscription(userId: string, update: SubscriptionUpdate): Promise<void> {
  const fs = firestore();
  if (!fs) return;
  try {
    const userRef = fs.collection('users').doc(userId);
    const purchaseRef = userRef.collection('purchases').doc(update.originalTransactionId);

    const purchaseData = stripUndefined({
      productId: update.productId,
      originalTransactionId: update.originalTransactionId,
      latestTransactionId: update.latestTransactionId ?? undefined,
      status: update.status,
      environment: update.environment,
      purchaseDate: update.purchaseDate ?? undefined,
      expiresAt: update.expiresAt,
      autoRenewEnabled: update.autoRenewEnabled ?? undefined,
      cancellationDate: update.cancellationDate ?? null,
      cancellationReason: update.cancellationReason ?? null,
      updatedAt: FieldValue.serverTimestamp(),
    });

    const snapshotData = stripUndefined({
      productId: update.productId,
      status: update.status,
      environment: update.environment,
      expiresAt: update.expiresAt,
      autoRenewEnabled: update.autoRenewEnabled ?? undefined,
      latestTransactionId: update.latestTransactionId ?? update.originalTransactionId,
      isActive: isActiveStatus(update.status) && update.expiresAt.getTime() > Date.now(),
    });

    const batch = fs.batch();
    batch.set(purchaseRef, purchaseData, { merge: true });
    batch.set(
      userRef,
      {
        subscription: snapshotData,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    await batch.commit();
  } catch (err) {
    log.warn({ err, userId, originalTransactionId: update.originalTransactionId }, 'firestore updateSubscription failed');
  }
}

/**
 * Set the absolute count (preferred when you already have it from a query).
 * Use this rather than incrementing so the counter is always accurate even if
 * Firestore writes are temporarily lost.
 */
export async function setTrackedCount(userId: string, count: number): Promise<void> {
  const fs = firestore();
  if (!fs) return;
  try {
    await fs.collection('users').doc(userId).set(
      {
        trackedCount: count,
        updatedAt: FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
  } catch (err) {
    log.warn({ err, userId, count }, 'firestore setTrackedCount failed');
  }
}

// MARK: - Helpers

function isActiveStatus(status: string): boolean {
  return status === 'ACTIVE' || status === 'IN_GRACE_PERIOD';
}

function stripUndefined<T extends Record<string, unknown>>(input: T): Partial<T> {
  const out: Partial<T> = {};
  for (const [k, v] of Object.entries(input)) {
    if (v !== undefined) {
      (out as Record<string, unknown>)[k] = v;
    }
  }
  return out;
}
