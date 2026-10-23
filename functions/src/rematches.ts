import * as firestore from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import { ALLOWED_DURATIONS, ALLOWED_ROUNDS, buildWaitingDebate } from './domain/debate/waiting';
import { assertRateLimit, rateLimitRef, requestDocumentId } from './request_control';

type Data = Record<string, any>;
const idIsValid = (id: unknown): id is string => typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id);
const placeholders = new Set(['opponent', 'invited', 'fighter', 'оппонент', 'приглашен', 'приглашён']);

export function createRematchController(db: firestore.Firestore, preciseDeadlines: boolean, clock = Date.now) {
  return async (uid: string, input: Data, strictTransitions = false) => {
    if (!idIsValid(input.sourceDebateId)) throw new HttpsError('invalid-argument', 'Некорректный исходный бой.');
    const requestId = requestDocumentId(uid, input.clientRequestId);
    if (!requestId) throw new HttpsError('invalid-argument', 'Требуется идентификатор запроса.');
    const source = db.collection('debates').doc(input.sourceDebateId);
    const slot = db.collection('server_rematch_slots').doc(source.id);
    const receipt = db.collection('server_rematch_requests').doc(requestId);
    const rate = rateLimitRef(db, uid, 'createDebate');
    const requestRate = rateLimitRef(db, uid, 'requestRematch');
    const next = db.collection('debates').doc();
    return db.runTransaction(async (tx) => {
      const [original, saved, current, profile, limited, requestsLimited] = await Promise.all([
        tx.get(source), tx.get(receipt), tx.get(slot), tx.get(db.collection('users').doc(uid)), tx.get(rate),
        tx.get(requestRate),
      ]);
      const old = original.data();
      if (!old) throw new HttpsError('not-found', 'Исходный бой недоступен.');
      const fighters = [old.fighter1, old.fighter2];
      if (!fighters.includes(uid)) throw new HttpsError('permission-denied', 'Реванш доступен только участникам.', { reason: 'REMATCH_NOT_FIGHTER' });
      if (profile.data()?.isBanned === true) throw new HttpsError('permission-denied', 'Аккаунт заблокирован.', { reason: 'ACCOUNT_BANNED' });
      if (old.status !== 'finished') throw new HttpsError('failed-precondition', 'Бой ещё не завершён.', { reason: 'REMATCH_NOT_FINISHED' });
      const opponent = fighters.find((fighter) => fighter !== uid);
      if (typeof opponent !== 'string' || !opponent.trim() || opponent.includes('/') || placeholders.has(opponent.trim().toLowerCase())) {
        throw new HttpsError('failed-precondition', 'Оппонент недоступен.');
      }
      const target = await tx.get(db.collection('users').doc(opponent));
      if (target.data()?.isBanned === true) throw new HttpsError('failed-precondition', 'Оппонент недоступен.');

      // A lost response must return exactly its original challenge, even after
      // another one was proposed. A deleted challenge is never resurrected.
      if (saved.exists) {
        if (saved.data()!.sourceDebateId !== source.id) throw new HttpsError('already-exists', 'Идентификатор уже использован.');
        const prior = await tx.get(db.collection('debates').doc(saved.data()!.debateId));
        if (!prior.exists || ['cancelled', 'deleted'].includes(prior.data()!.status)) {
          throw new HttpsError('failed-precondition', 'Предыдущий вызов отменён.', { reason: 'REMATCH_PREVIOUS_CANCELLED' });
        }
        return { debateId: prior.id, created: false };
      }
      // Bound new receipt writes even when a caller keeps opening an already
      // pending rematch with fresh IDs. Exact retries above remain immediate.
      assertRateLimit(requestsLimited.data(), clock(), 1000);
      if (current.exists) {
        const existing = await tx.get(db.collection('debates').doc(current.data()!.debateId));
        if (existing.exists && ['waiting', 'active', 'live'].includes(existing.data()!.status)) {
          tx.create(receipt, { sourceDebateId: source.id, debateId: existing.id, createdAt: firestore.FieldValue.serverTimestamp() });
          tx.set(requestRate, { lastAtMs: clock() });
          return { debateId: existing.id, created: false };
        }
      }
      const duration = old.roundDurationSeconds ?? old.durationSeconds;
      const rounds = old.totalRounds;
      const topic = typeof old.topic === 'string' ? old.topic.trim() : '';
      if (!(ALLOWED_DURATIONS as readonly unknown[]).includes(duration)
        || !(ALLOWED_ROUNDS as readonly unknown[]).includes(rounds) || topic.length < 3 || topic.length > 2000) {
        throw new HttpsError('failed-precondition', 'Условия исходного боя недоступны.');
      }
      assertRateLimit(limited.data(), clock(), 5000);
      const user = profile.data() ?? {};
      const name = typeof user.name === 'string' && user.name.trim() ? user.name.trim().slice(0, 50) : 'Боец';
      const rating = Number.isFinite(user.rating) ? user.rating : 0;
      const document = buildWaitingDebate({ uid, name, rating, topic,
        durationSeconds: duration, totalRounds: rounds, invitedUserId: opponent,
        creationMode: 'direct_invite', visibilityMode: 'private',
        languageCode: ['ru', 'en', 'ar'].includes(old.languageCode) ? old.languageCode : 'ru',
        region: ['global', 'cis', 'mena', 'europe_africa'].includes(old.region) ? old.region : 'global',
        preciseDeadlines, strictTransitions,
      });
      tx.create(next, { ...document, rematchOf: source.id });
      tx.create(receipt, { sourceDebateId: source.id, debateId: next.id, createdAt: firestore.FieldValue.serverTimestamp() });
      tx.set(slot, { debateId: next.id, updatedAt: firestore.FieldValue.serverTimestamp() });
      tx.set(rate, { lastAtMs: clock() });
      tx.set(requestRate, { lastAtMs: clock() });
      return { debateId: next.id, created: true };
    });
  };
}
