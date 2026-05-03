import appleSignin from 'apple-signin-auth';
import { SignJWT, jwtVerify } from 'jose';
import { env } from '../../config/env.js';
import { logger } from '../../config/logger.js';
import { UnauthorizedError } from '../../lib/errors.js';

const encoder = new TextEncoder();
const secret = encoder.encode(env.JWT_SECRET);

export interface AppleVerified {
  sub: string;
  email: string | null;
  emailVerified: boolean;
}

/**
 * Verify the identity token returned by `ASAuthorizationAppleIDCredential.identityToken`.
 * Throws UnauthorizedError if verification fails.
 */
export async function verifyAppleIdentityToken(identityToken: string): Promise<AppleVerified> {
  try {
    const payload = await appleSignin.verifyIdToken(identityToken, {
      audience: env.APPLE_BUNDLE_ID,
      ignoreExpiration: false,
    });
    if (!payload.sub) {
      throw new UnauthorizedError('Apple token missing sub');
    }
    return {
      sub: payload.sub,
      email: typeof payload.email === 'string' ? payload.email : null,
      emailVerified: payload.email_verified === 'true' || payload.email_verified === true,
    };
  } catch (err) {
    logger.warn({ err }, 'apple identity token verify failed');
    throw new UnauthorizedError('Invalid Apple identity token');
  }
}

export interface SessionClaims {
  sub: string; // our User.id
  appleSub: string;
}

const SESSION_TTL = '30d';

export async function issueSessionJwt(claims: SessionClaims): Promise<string> {
  return await new SignJWT({ ...claims })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuer(env.JWT_ISSUER)
    .setAudience(env.JWT_AUDIENCE)
    .setSubject(claims.sub)
    .setIssuedAt()
    .setExpirationTime(SESSION_TTL)
    .sign(secret);
}

export async function verifySessionJwt(token: string): Promise<SessionClaims> {
  try {
    const { payload } = await jwtVerify(token, secret, {
      issuer: env.JWT_ISSUER,
      audience: env.JWT_AUDIENCE,
    });
    if (typeof payload.sub !== 'string' || typeof payload.appleSub !== 'string') {
      throw new UnauthorizedError();
    }
    return { sub: payload.sub, appleSub: payload.appleSub };
  } catch {
    throw new UnauthorizedError('Invalid session token');
  }
}
