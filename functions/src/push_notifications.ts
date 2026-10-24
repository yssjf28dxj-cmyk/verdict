import { createHash, randomUUID } from 'node:crypto';
import * as firestore from 'firebase-admin/firestore';
import { HttpsError } from 'firebase-functions/v2/https';
import type { Message, BatchResponse } from 'firebase-admin/messaging';
import { planDebateNotifications } from './domain/debate/notification_events';
import { assertRateLimit, rateLimitRef } from './request_control';
type Data = Record<string, any>;
const hash = (value: string) => createHash('sha256').update(value).digest('hex');
const idOK = (id: unknown): id is string => typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id);
const ms = (value: any) => typeof value?.toMillis === 'function' ? value.toMillis() : 0;
const preference = (db: firestore.Firestore, uid: string) => db.doc(`users/${uid}/private_settings/notifications`);
const participant = (uid: string, battle: Data) => [battle.fighter1, battle.fighter2].includes(uid);
function stillRelevant(row: Data, battle: Data | undefined, now: number): boolean {
  if (!battle || !participant(row.uid, battle) || ms(row.expiresAt) <= now) return false;
  if (row.kind === 'finished') return battle.status === 'finished';
  if (!['active', 'live'].includes(battle.status)) return false;
  return row.kind === 'accepted' || (row.kind === 'turn' && battle.isRoundActive === true
    && battle.activeSpeakerId === row.uid && ms(battle.roundEndsAt) === row.deadlineMs);
}
const genericText: Record<string, Record<string, string>> = {
  ru: { accepted: 'Вызов принят', turn: 'Ваш ход', finished: 'Бой завершён' },
  en: { accepted: 'Challenge accepted', turn: 'Your turn', finished: 'Battle finished' },
  ar: { accepted: 'تم قبول التحدي', turn: 'دورك الآن', finished: 'انتهت المناظرة' },
  es: { accepted: 'Desafío aceptado', turn: 'Tu turno', finished: 'Debate terminado' },
  fr: { accepted: 'Défi accepté', turn: 'À vous de jouer', finished: 'Débat terminé' },
  hi: { accepted: 'चुनौती स्वीकार की गई', turn: 'आपकी बारी', finished: 'बहस समाप्त' },
  zh: { accepted: '挑战已接受', turn: '轮到你了', finished: '辩论已结束' },
};
export function createPushController(db: firestore.Firestore, send: (messages: Message[]) => Promise<BatchResponse>, clock = Date.now) {
  const installs = db.collection('server_push_installs');
  const devices = db.collection('server_push_devices');
  const outbox = db.collection('server_notification_outbox');
  async function configure(uid: string, input: Data) {
    if (typeof input.enabled !== 'boolean') throw new HttpsError('invalid-argument', 'Boolean preference required.');
    await db.runTransaction(async tx => {
      const profile = await tx.get(db.doc(`users/${uid}`));
      if (input.enabled && profile.data()?.isBanned === true) throw new HttpsError('permission-denied', 'Account banned.');
      tx.set(preference(db, uid), { enabled: input.enabled, updatedAt: firestore.FieldValue.serverTimestamp() });
    });
    return { enabled: input.enabled };
  }
  async function register(uid: string, input: Data) {
    const { token, installationKey, platform, locale, generation } = input;
    if (typeof token !== 'string' || token.length < 20 || token.length > 4096 || /\s/.test(token)
      || typeof installationKey !== 'string' || !/^[a-f0-9]{64}$/.test(installationKey)
      || !Number.isSafeInteger(generation) || generation < 1
      || !['android', 'ios'].includes(platform) || typeof locale !== 'string' || !Object.prototype.hasOwnProperty.call(genericText, locale)) {
      throw new HttpsError('invalid-argument', 'Invalid device registration.');
    }
    const installHash = hash(installationKey), tokenId = hash(token);
    const install = installs.doc(installHash), device = devices.doc(tokenId), rate = rateLimitRef(db, uid, 'pushRegister');
    await db.runTransaction(async tx => {
      const [binding, target, profile, settings, limited, owned] = await Promise.all([
        tx.get(install), tx.get(device), tx.get(db.doc(`users/${uid}`)), tx.get(preference(db, uid)), tx.get(rate),
        tx.get(devices.where('uid', '==', uid).limit(100)),
      ]);
      if (profile.data()?.isBanned === true || settings.data()?.enabled !== true) throw new HttpsError('permission-denied', 'Notifications disabled.');
      if (target.exists && target.data()!.installHash !== installHash) throw new HttpsError('permission-denied', 'Device already bound.');
      const priorGeneration = binding.data()?.generation || 0;
      if (generation < priorGeneration) throw new HttpsError('aborted', 'Stale installation generation.', { nextGeneration: priorGeneration + 1 });
      if (generation === priorGeneration) {
        if (binding.data()?.uid === uid && binding.data()?.tokenId === tokenId) return;
        throw new HttpsError('aborted', 'Installation generation already consumed.', { nextGeneration: priorGeneration + 1 });
      }
      assertRateLimit(limited.data(), clock(), 1000);
      const oldId = binding.data()?.tokenId;
      const old = typeof oldId === 'string' && oldId !== tokenId ? await tx.get(devices.doc(oldId)) : null;
      const expired = owned.docs.filter(doc => clock() - ms(doc.data().updatedAt) > 30 * 86400000);
      const active = owned.docs.filter(doc => !expired.some(stale => stale.id === doc.id) && doc.id !== oldId && doc.id !== tokenId);
      if (active.length >= 20) throw new HttpsError('resource-exhausted', 'Device limit reached.');
      for (const stale of expired) tx.delete(stale.ref);
      if (old?.exists && old.data()!.installHash === installHash) tx.delete(old.ref);
      tx.set(device, { uid, token, installHash, platform, locale, updatedAt: firestore.FieldValue.serverTimestamp() });
      tx.set(install, { uid, tokenId, generation, updatedAt: firestore.FieldValue.serverTimestamp() });
      tx.set(rate, { lastAtMs: clock() });
    });
    return { ok: true };
  }
  async function unregister(_uid: string, input: Data) {
    const key = input.installationKey;
    const generation = input.generation;
    if (typeof key !== 'string' || !/^[a-f0-9]{64}$/.test(key) || !Number.isSafeInteger(generation) || generation < 1) throw new HttpsError('invalid-argument', 'Invalid installation.');
    const installHash = hash(key), install = installs.doc(installHash);
    // Possession of this random installation secret permits retiring its old
    // binding after account switching; it never reveals or changes other devices.
    await db.runTransaction(async tx => {
      const binding = await tx.get(install);
      const prior = binding.data()?.generation || 0;
      if (generation < prior || (generation === prior && binding.data()?.tokenId)) {
        throw new HttpsError('aborted', 'Stale installation generation.', { nextGeneration: prior + 1 });
      }
      if (generation === prior) return;
      const tokenId = binding.data()?.tokenId;
      const device = typeof tokenId === 'string' ? await tx.get(devices.doc(tokenId)) : null;
      if (device?.data()?.installHash === installHash) tx.delete(device.ref);
      // Retain a fence: a registration whose HTTP response was lost cannot
      // commit after logout and silently recreate the old account binding.
      tx.set(install, { uid: _uid, tokenId: null, generation, updatedAt: firestore.FieldValue.serverTimestamp() });
    });
    return { ok: true };
  }
  async function enqueue(debateId: string, before: Data | undefined, after: Data | undefined, eventMs: number) {
    if (!idOK(debateId) || !Number.isFinite(eventMs)) return;
    const planned = planDebateNotifications(before, after);
    for (const event of planned) {
      const notificationId = hash(`${debateId}\0${event.uid}\0${event.key}`);
      const ref = outbox.doc(notificationId);
      const deadlineMs = event.kind === 'turn' ? ms(after?.roundEndsAt) : 0;
      const row: Data = { uid: event.uid, debateId, kind: event.kind, deadlineMs,
        createdAt: firestore.Timestamp.fromMillis(eventMs),
        expiresAt: firestore.Timestamp.fromMillis(event.kind === 'turn' ? Math.min(deadlineMs, eventMs + 300000) : eventMs + (event.kind === 'finished' ? 86400000 : 300000)) };
      await db.runTransaction(async tx => {
        const [existing, current, profile, settings] = await Promise.all([tx.get(ref), tx.get(db.doc(`debates/${debateId}`)),
          tx.get(db.doc(`users/${event.uid}`)), tx.get(preference(db, event.uid))]);
        if (existing.exists) return;
        const enabled = settings.data()?.enabled === true && profile.data()?.isBanned !== true && stillRelevant(row, current.data(), clock());
        tx.create(ref, { ...row, status: enabled ? 'pending' : 'suppressed', sentDevices: [] });
        if (enabled) tx.create(db.doc(`users/${event.uid}/notifications/${notificationId}`), { ...row, read: false });
      });
    }
  }
  async function deliver(notificationId: string) {
    if (!/^[a-f0-9]{64}$/.test(notificationId)) return;
    const ref = outbox.doc(notificationId), lease = randomUUID();
    const row = await db.runTransaction(async tx => {
      const snapshot = await tx.get(ref), data = snapshot.data();
      if (!data || ['sent', 'suppressed'].includes(data.status)) return null;
      if (data.status === 'sending' && data.leaseUntilMs > clock()) throw new Error('Delivery lease busy');
      const [current, profile, settings] = await Promise.all([tx.get(db.doc(`debates/${data.debateId}`)),
        tx.get(db.doc(`users/${data.uid}`)), tx.get(preference(db, data.uid))]);
      if (!stillRelevant(data, current.data(), clock()) || settings.data()?.enabled !== true || profile.data()?.isBanned === true) {
        tx.update(ref, { status: 'suppressed' }); return null;
      }
      tx.update(ref, { status: 'sending', lease, leaseUntilMs: clock() + 60000 });
      return data;
    });
    if (!row) return;
    try {
      const snapshots = await devices.where('uid', '==', row.uid).limit(20).get();
      const targets = snapshots.docs.filter(doc => !row.sentDevices.includes(doc.id) && clock() - ms(doc.data().updatedAt) <= 30 * 86400000);
      const messages: Message[] = targets.map(doc => {
        const device = doc.data(), ttl = Math.max(0, ms(row.expiresAt) - clock());
        return { token: device.token, notification: { title: 'VERDICT', body: (Object.prototype.hasOwnProperty.call(genericText, device.locale) ? genericText[device.locale] : genericText.en)[row.kind] },
          data: { notificationId, uid: row.uid, debateId: row.debateId, kind: row.kind, expiresAtMs: String(ms(row.expiresAt)) },
          android: { collapseKey: notificationId, ttl, notification: { tag: notificationId } },
          apns: { headers: { 'apns-collapse-id': notificationId, 'apns-expiration': String(Math.floor(ms(row.expiresAt) / 1000)) } } };
      });
      const response = messages.length ? await send(messages) : { responses: [], successCount: 0, failureCount: 0 };
      const delivered = targets.filter((_, i) => response.responses[i]?.success).map(doc => doc.id);
      let transient = false;
      for (let i = 0; i < targets.length; i++) {
        const code = response.responses[i]?.error?.code;
        if (response.responses[i]?.success) continue;
        if (['messaging/registration-token-not-registered', 'messaging/invalid-registration-token'].includes(code || '')) {
          const target = targets[i];
          await db.runTransaction(async tx => {
            const fresh = await tx.get(target.ref);
            if (fresh.data()?.uid === row.uid && fresh.data()?.installHash === target.data().installHash) tx.delete(target.ref);
          });
        } else transient = true;
      }
      await db.runTransaction(async tx => {
        const snapshot = await tx.get(ref);
        if (snapshot.data()?.lease !== lease) return;
        tx.update(ref, { status: transient ? 'pending' : 'sent', leaseUntilMs: 0,
          sentDevices: [...new Set([...row.sentDevices, ...delivered])], updatedAt: firestore.FieldValue.serverTimestamp() });
      });
      if (transient) throw new Error('Transient push failure');
    } catch (error) {
      await db.runTransaction(async tx => {
        const snapshot = await tx.get(ref);
        if (snapshot.data()?.lease === lease && snapshot.data()?.status === 'sending') tx.update(ref, { status: 'pending', leaseUntilMs: 0 });
      });
      throw error;
    }
  }
  return { configure, register, unregister, enqueue, deliver };
}
