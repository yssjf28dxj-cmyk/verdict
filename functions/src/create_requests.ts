import * as firestore from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { assertRateLimit, rateLimitRef, requestDocumentId } from './request_control';

/** Called only after the public create handler has validated and normalized terms. */
export function createChallengeRequestController(db: firestore.Firestore, clock = Date.now) {
  return async (uid: string, clientRequestId: unknown, fingerprint: string,
    document: Record<string, unknown>) => {
    const id = requestDocumentId(uid, clientRequestId);
    if (!id) throw new HttpsError('invalid-argument', 'Required request identifier.');
    const receipt = db.collection('server_create_requests').doc(id);
    const rate = rateLimitRef(db, uid, 'createDebate');
    const next = db.collection('debates').doc();
    return db.runTransaction(async tx => {
      const [saved, profile, limited] = await Promise.all([
        tx.get(receipt), tx.get(db.collection('users').doc(uid)), tx.get(rate),
      ]);
      if (profile.data()?.isBanned === true) throw new HttpsError('permission-denied', 'Account banned.');
      if (saved.exists) {
        const prior = saved.data()!;
        if (prior.uid !== uid || prior.fingerprint !== fingerprint) {
          throw new HttpsError('already-exists', 'Request identifier already used.', { reason: 'CREATE_REQUEST_REUSED' });
        }
        const debate = await tx.get(db.collection('debates').doc(prior.debateId));
        if (!debate.exists) throw new HttpsError('failed-precondition', 'Original challenge deleted.', { reason: 'CREATE_PREVIOUS_DELETED' });
        if (debate.data()!.creatorId !== uid) throw new HttpsError('permission-denied', 'Original challenge unavailable.');
        return { debateId: debate.id, created: false };
      }
      assertRateLimit(limited.data(), clock(), 5000);
      tx.create(next, document);
      tx.create(receipt, { uid, fingerprint, debateId: next.id, createdAt: firestore.FieldValue.serverTimestamp() });
      tx.set(rate, { lastAtMs: clock() });
      return { debateId: next.id, created: true };
    });
  };
}
