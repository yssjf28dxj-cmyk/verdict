import { createHash } from 'node:crypto';
import * as firestore from 'firebase-admin/firestore';
import { getStorage } from 'firebase-admin/storage';
import { HttpsError } from 'firebase-functions/v2/https';
import { assertCanSendMessage } from './domain/debate/guards';
import { assertAccountMayWrite, consumeRateLimit, requestDocumentId } from './request_control';

type Data = Record<string, any>;
export function decodeMedia(input: Data): { bytes: Buffer; contentType: string; extension: string } {
  const extensions: Record<string, string> = { 'image/png': 'png', 'image/jpeg': 'jpg', 'audio/m4a': 'm4a', 'audio/mp4': 'm4a' };
  const contentType = input.contentType;
  const base64 = input.base64;
  if (typeof contentType !== 'string' || !Object.prototype.hasOwnProperty.call(extensions, contentType) || typeof base64 !== 'string' || !base64 || base64.length > 8 * 1024 * 1024
    || base64.length % 4 || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
    throw new HttpsError('invalid-argument', 'Неверный тип или размер медиа.', { reason: 'MESSAGE_INVALID_MEDIA_FILE' });
  }
  const bytes = Buffer.from(base64, 'base64');
  if (!bytes.length || bytes.length > 6 * 1024 * 1024 || bytes.toString('base64') !== base64) throw new HttpsError('invalid-argument', 'Неверные данные медиа.');
  return { bytes, contentType, extension: extensions[contentType] };
}
function assertMediaTurn(uid: string, debate: Data, expectedRound: unknown): number {
  const status = debate.status === 'live' ? 'active' : debate.status;
  const { roundIndex } = assertCanSendMessage({ uid, debate, status, hasReadAccess: true, isPlayableStatus: status === 'active' });
  if (!Number.isInteger(expectedRound) || expectedRound !== roundIndex) throw new HttpsError('failed-precondition', 'Раунд сменился.', { reason: 'MESSAGE_ROUND_CHANGED' });
  return roundIndex;
}

export function createLiveMediaController(db: firestore.Firestore, storage: ReturnType<typeof getStorage>) {
  return async (uid: string, input: Data) => {
    await assertAccountMayWrite(db, uid);
    const debateId = input.debateId;
    if (typeof debateId !== 'string' || !debateId || debateId.includes('/')) throw new HttpsError('invalid-argument', 'Некорректный дебат.');
    const id = requestDocumentId(uid, input.clientRequestId);
    if (!id) throw new HttpsError('invalid-argument', 'Требуется идентификатор сообщения.');
    const { bytes, contentType, extension } = decodeMedia(input);
    const duration = Number.isFinite(input.mediaDuration) ? Math.max(0, Math.min(300, Math.trunc(input.mediaDuration))) : 0;
    const fingerprint = createHash('sha256').update(bytes).update(JSON.stringify([contentType, duration, input.expectedRoundIndex])).digest('hex');
    const parent = db.collection('debates').doc(debateId);
    const message = parent.collection('messages').doc(id);
    const duplicate = (data: Data) => {
      if (data.senderId !== uid || data.requestFingerprint !== fingerprint) throw new HttpsError('already-exists', 'Идентификатор сообщения уже использован.', { reason: 'MESSAGE_REQUEST_REUSED' });
      return { ok: true, messageId: id, mediaPath: data.mediaPath };
    };
    const existing = await message.get();
    if (existing.exists) return duplicate(existing.data()!);
    const preflight = await parent.get();
    if (!preflight.exists) throw new HttpsError('not-found', 'Дебат не найден.');
    assertMediaTurn(uid, preflight.data()!, input.expectedRoundIndex);
    await consumeRateLimit(db, uid, 'sendLiveMedia', 250);
    const profile = await db.collection('users').doc(uid).get();
    const path = `debates/${debateId}/secured/${id}.${extension}`;
    const file = storage.bucket().file(path);
    try {
      await file.save(bytes, { resumable: false, preconditionOpts: { ifGenerationMatch: 0 },
        metadata: { contentType, cacheControl: 'private, no-store', metadata: { requestFingerprint: fingerprint } } });
    } catch (error) {
      if (![409, 412].includes(Number((error as { code?: unknown }).code))) throw error;
      const [metadata] = await file.getMetadata();
      if (metadata.metadata?.requestFingerprint !== fingerprint) throw new HttpsError('already-exists', 'Идентификатор уже использован.', { reason: 'MESSAGE_REQUEST_REUSED' });
    }
    // A crash between Storage and Firestore may leave a protected orphan; never
    // delete a file that another retry may already have committed to a message.
    return db.runTransaction(async (tx) => {
      const [fresh, saved] = await Promise.all([tx.get(parent), tx.get(message)]);
      if (saved.exists) return duplicate(saved.data()!);
      if (!fresh.exists) throw new HttpsError('not-found', 'Дебат не найден.');
      const roundIndex = assertMediaTurn(uid, fresh.data()!, input.expectedRoundIndex);
      tx.create(message, { text: '', senderId: uid, senderName: profile.data()?.name || uid,
        messageType: contentType.startsWith('audio/') ? 'voice' : 'image', mediaPath: path, clientRequestId: input.clientRequestId,
        mediaDuration: duration, roundIndex, requestFingerprint: fingerprint,
        createdAt: firestore.FieldValue.serverTimestamp() });
      return { ok: true, messageId: id, mediaPath: path };
    });
  };
}

// Expiring per-user leases: a killed app disappears within 45s. Only aggregate
// counts leave the server; presence rows remain unreadable to clients.
export function createPresenceController(db: firestore.Firestore, canRead: (uid: string, debate: Data) => boolean, clock = Date.now) {
  return async (uid: string, input: Data) => {
    const id = input.debateId;
    if (typeof id !== 'string' || !id || id.includes('/')) throw new HttpsError('invalid-argument', 'Некорректный дебат.');
    const ref = db.collection('debates').doc(id);
    const parent = await ref.get();
    if (!parent.exists || !canRead(uid, parent.data()!)) throw new HttpsError('permission-denied', 'Нет доступа.');
    const data = parent.data()!;
    const viewers = ref.collection('presence');
    const row = viewers.doc(createHash('sha256').update(uid).digest('hex'));
    const fighter = [data.fighter1, data.fighter2, data.creatorId].includes(uid);
    if (input.present === false || fighter || data.status === 'finished') await row.delete();
    else {
      await consumeRateLimit(db, uid, `presence:${id}`, 5000);
      await row.set({ expiresAt: firestore.Timestamp.fromMillis(clock() + 45000) });
    }
    const count = await viewers.where('expiresAt', '>', firestore.Timestamp.fromMillis(clock())).count().get();
    return { viewers: count.data().count, leaseSeconds: 45 };
  };
}
