import { createHash } from 'node:crypto';
import * as firestore from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { assertRateLimit, rateLimitRef, requestDocumentId } from './request_control';

type Data = Record<string, any>;
const validId = (id: unknown): id is string => typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id);
export function createMessageReactionController(db: firestore.Firestore,
  canRead: (uid: string, debate: Data) => boolean, clock = Date.now) {
  return async (uid: string, input: Data) => {
    const { debateId, messageId, kind, active, expectedRevision } = input;
    if (!validId(debateId) || !validId(messageId) || !['strong', 'source'].includes(kind)
      || typeof active !== 'boolean' || !Number.isSafeInteger(expectedRevision) || expectedRevision < 0 || expectedRevision > 1e9) {
      throw new HttpsError('invalid-argument', 'Invalid reaction.');
    }
    const requestId = requestDocumentId(uid, input.clientRequestId);
    if (!requestId) throw new HttpsError('invalid-argument', 'Request identity required.');
    const parent = db.collection('debates').doc(debateId);
    const message = parent.collection('messages').doc(messageId);
    const own = message.collection('reactions').doc(uid);
    const shard = createHash('sha256').update(uid).digest()[0] % 16;
    const tally = message.collection('reaction_tallies').doc(String(shard));
    const rate = rateLimitRef(db, uid, 'messageReaction');
    return db.runTransaction(async (tx) => {
      const [debateSnapshot, messageSnapshot, profile, state, limited] = await Promise.all([
        tx.get(parent), tx.get(message), tx.get(db.collection('users').doc(uid)), tx.get(own), tx.get(rate),
      ]);
      const debate = debateSnapshot.data();
      if (!debate || !canRead(uid, debate)) throw new HttpsError('permission-denied', 'No transcript access.');
      if (profile.data()?.isBanned === true) throw new HttpsError('permission-denied', 'Account banned.');
      if ([debate.fighter1, debate.fighter2, debate.creatorId, debate.invitedUserId, debate.opponentId].includes(uid)
        || (Array.isArray(debate.invitedUserIds) && debate.invitedUserIds.includes(uid))) {
        throw new HttpsError('permission-denied', 'Only spectators may react.', { reason: 'REACTION_NOT_SPECTATOR' });
      }
      const sender = messageSnapshot.data()?.senderId;
      if (!messageSnapshot.exists || !sender || ![debate.fighter1, debate.fighter2].includes(sender)) {
        throw new HttpsError('not-found', 'Message unavailable.');
      }
      const previous = state.data()?.[kind];
      if (previous?.requestId === requestId) {
        if (previous.active !== active) throw new HttpsError('already-exists', 'Request identity reused.');
        return { active: previous.active, revision: previous.revision };
      }
      if (!['active', 'live'].includes(debate.status)) throw new HttpsError('failed-precondition', 'Battle is not live.');
      const revision = typeof previous?.revision === 'number' ? previous.revision : 0;
      if (expectedRevision !== revision) throw new HttpsError('aborted', 'Reaction changed. Refresh before retrying.', { reason: 'REACTION_CHANGED' });
      assertRateLimit(limited.data(), clock(), 1000);
      const delta = Number(active) - Number(previous?.active === true);
      tx.set(own, { [kind]: { active, revision: revision + 1, requestId }, updatedAt: firestore.FieldValue.serverTimestamp() }, { merge: true });
      if (delta) tx.set(tally, { [kind]: firestore.FieldValue.increment(delta) }, { merge: true });
      tx.set(rate, { lastAtMs: clock() });
      return { active, revision: revision + 1 };
    });
  };
}
