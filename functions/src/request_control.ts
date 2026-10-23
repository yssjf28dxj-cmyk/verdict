import { createHash } from 'node:crypto';
import * as firestore from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';

export function requestDocumentId(uid: string, requestId: unknown): string | null {
  if (requestId === undefined || requestId === null) return null;
  if (typeof requestId !== 'string' || !/^[A-Za-z0-9_-]{16,128}$/.test(requestId)) {
    throw new HttpsError('invalid-argument', 'Invalid request identifier.', { reason: 'REQUEST_ID_INVALID' });
  }
  return createHash('sha256').update(`${uid}\0${requestId}`).digest('hex');
}
export function rateLimitRef(db: firestore.Firestore, uid: string, action: string): firestore.DocumentReference {
  return db.collection('server_rate_limits').doc(createHash('sha256').update(`${uid}\0${action}`).digest('hex'));
}
export function assertRateLimit(last: firestore.DocumentData | undefined, now: number, cooldownMs: number): void {
  const elapsed = now - (typeof last?.lastAtMs === 'number' ? last.lastAtMs : -Infinity);
  if (elapsed < cooldownMs) throw new HttpsError('resource-exhausted', 'Слишком частые запросы. Подождите.', {
    reason: 'RATE_LIMIT_EXCEEDED', retryAfterMs: cooldownMs - elapsed,
  });
}
export async function consumeRateLimit(db: firestore.Firestore, uid: string, action: string, cooldownMs: number): Promise<void> {
  const ref = rateLimitRef(db, uid, action);
  await db.runTransaction(async (tx) => {
    const snapshot = await tx.get(ref);
    const now = Date.now();
    assertRateLimit(snapshot.data(), now, cooldownMs);
    tx.set(ref, { lastAtMs: now });
  });
}
export async function assertAccountMayWrite(db: firestore.Firestore, uid: string): Promise<void> {
  const profile = await db.collection('users').doc(uid).get();
  if (profile.data()?.isBanned === true) throw new HttpsError('permission-denied', 'Аккаунт заблокирован.', {
    reason: 'ACCOUNT_BANNED',
  });
}
