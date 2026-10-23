import * as firestore from 'firebase-admin/firestore';
import { createHash } from 'node:crypto';
import { HttpsError } from 'firebase-functions/v2/https';
import { assertCanSendMessage } from './domain/debate/guards';
import { assertRateLimit, rateLimitRef, requestDocumentId } from './request_control';

export function createTextMessageController(db: firestore.Firestore,
  canRead: (uid: string, data: Record<string, any>) => boolean,
  senderName: (uid: string, profile: Record<string, any>) => string) {
  return async (uid: string, input: Record<string, any>, text: string) => {
    if (typeof input.debateId !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(input.debateId)) throw new HttpsError('invalid-argument', 'Invalid debate ID');
    if (typeof input.expectedSenderId !== 'string' || !input.expectedSenderId) throw new HttpsError('invalid-argument', 'Original sender required');
    if (input.expectedSenderId !== uid) throw new HttpsError('permission-denied', 'Sender session changed');
    const id = requestDocumentId(uid, input.clientRequestId);
    if (!id || !Number.isSafeInteger(input.expectedRound) || input.expectedRound < 1) throw new HttpsError('invalid-argument', 'Request ID and original round required');
    const debate = db.collection('debates').doc(input.debateId);
    const receipt = debate.collection('server_text_requests').doc(id);
    const message = debate.collection('messages').doc();
    const rate = rateLimitRef(db, uid, 'sendDebateMessage');
    const hash = createHash('sha256').update(text).digest('hex');
    return db.runTransaction(async tx => {
      const [battle, saved, profile, limited] = await Promise.all([
        tx.get(debate), tx.get(receipt), tx.get(db.collection('users').doc(uid)), tx.get(rate),
      ]);
      const data = battle.data();
      if (!data) throw new HttpsError('not-found', 'Debate unavailable');
      if (profile.data()?.isBanned === true || !canRead(uid, data)
          || ![data.fighter1, data.fighter2].includes(uid)) throw new HttpsError('permission-denied', 'Message access denied');
      if (saved.exists) {
        if (saved.data()!.textHash !== hash || saved.data()!.roundIndex !== input.expectedRound) {
          throw new HttpsError('already-exists', 'Request ID already used with different content');
        }
        return { ok: true, messageId: saved.data()!.messageId };
      }
      if (data.roundIndex !== input.expectedRound) throw new HttpsError('failed-precondition', 'Original turn ended', { reason: 'TURN_TIME_EXPIRED', textRequestUncommitted: true });
      let guard;
      try {
        guard = assertCanSendMessage({ uid, debate: data, hasReadAccess: true,
        status: data.status, isPlayableStatus: ['active', 'live'].includes(data.status), uploadGraceMs: 0 });
      } catch (error) {
        if (error instanceof HttpsError && error.code === 'failed-precondition') {
          throw new HttpsError(error.code, error.message, { ...(error.details as object || {}), textRequestUncommitted: true });
        }
        throw error;
      }
      assertRateLimit(limited.data(), Date.now(), 2000);
      tx.create(message, { text, messageType: 'text', senderId: uid,
        senderName: senderName(uid, profile.data() || {}), roundIndex: guard.roundIndex,
        createdAt: firestore.FieldValue.serverTimestamp() });
      tx.create(receipt, { messageId: message.id, textHash: hash, roundIndex: guard.roundIndex,
        createdAt: firestore.FieldValue.serverTimestamp() });
      tx.set(rate, { lastAtMs: Date.now() });
      return { ok: true, messageId: message.id };
    });
  };
}
