import { cert, getApps, initializeApp, type App } from 'firebase-admin/app';
import { getFirestore, type Firestore } from 'firebase-admin/firestore';
import { env } from './env.js';
import { logger } from './logger.js';

const log = logger.child({ mod: 'firebase' });

let _app: App | null = null;
let _firestore: Firestore | null = null;

function isConfigured(): boolean {
  return Boolean(
    env.FIREBASE_PROJECT_ID && env.FIREBASE_CLIENT_EMAIL && env.FIREBASE_PRIVATE_KEY,
  );
}

/**
 * Initialise the Firebase Admin SDK. Idempotent. Returns false if the env vars
 * aren't configured — callers should treat that as "sync disabled" and skip.
 */
export function initFirebase(): boolean {
  if (_app) return true;
  if (!isConfigured()) {
    log.info('firebase admin not configured (missing FIREBASE_* env vars); customer sync disabled');
    return false;
  }
  try {
    if (getApps().length > 0) {
      _app = getApps()[0]!;
    } else {
      _app = initializeApp({
        credential: cert({
          projectId: env.FIREBASE_PROJECT_ID,
          clientEmail: env.FIREBASE_CLIENT_EMAIL,
          // Railway / .env files often store the private key with literal `\n`
          // characters; convert them back to real newlines so the PEM parses.
          privateKey: env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
        }),
        projectId: env.FIREBASE_PROJECT_ID,
      });
    }
    _firestore = getFirestore(_app);
    log.info({ projectId: env.FIREBASE_PROJECT_ID }, 'firebase admin initialised');
    return true;
  } catch (err) {
    log.error({ err }, 'firebase admin init failed; customer sync disabled');
    _app = null;
    _firestore = null;
    return false;
  }
}

/**
 * Returns the Firestore instance, or null if Firebase isn't configured. Callers
 * should branch on null to skip the sync without crashing the request path.
 */
export function firestore(): Firestore | null {
  if (!_app) initFirebase();
  return _firestore;
}

export function isFirebaseEnabled(): boolean {
  return _firestore != null || isConfigured();
}
