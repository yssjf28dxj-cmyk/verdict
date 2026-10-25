import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { before, after, test } from 'node:test';

// Request shapes pinned from APK 4004 source da4669c, not today's Flutter client.
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
let db, api, firestore, rateLimitRef, createDeadlineController;
before(() => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
  const projectId = 'demo-verdict-apk4004';
  process.env.GCLOUD_PROJECT = projectId;
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId });
  firestore = require('firebase-admin/firestore');
  api = require('./lib/index');
  db = firestore.getFirestore();
  ({ rateLimitRef } = require('./lib/request_control'));
  ({ createDeadlineController } = require('./lib/debate_deadlines'));
});
after(async () => require('firebase-admin/app').deleteApp(require('firebase-admin/app').getApp()));
async function scenario(name, patch = {}) {
  const uid = `old-${name}`;
  const ref = db.collection('debates').doc(name);
  await db.collection('users').doc(uid).set({ name: 'Preserved profile', rating: 10 });
  await rateLimitRef(db, uid, 'sendDebateMessage').delete();
  await db.recursiveDelete(ref);
  await ref.set({ schemaVersion: 2, status: 'active', fighter1: uid, creatorId: uid,
    fighter2: `opponent-${name}`, visibilityMode: 'public', activeSpeakerId: uid,
    roundIndex: 1, totalRounds: 3, roundDurationSeconds: 60, isRoundActive: true,
    roundEndsAt: firestore.Timestamp.fromMillis(Date.now() + 60000), ...patch });
  return { uid, ref, request: { auth: { uid, token: {} },
    data: { debateId: name, text: 'Argument from APK 4004', senderName: 'Untrusted client name' } } };
}
test('APK 4004 debate text needs no new identity fields and keeps the readable message schema', async () => {
  const { uid, ref, request } = await scenario('legacy-text');
  const result = await api.sendDebateMessage.run(request);
  assert.equal(result.ok, true);
  const saved = (await ref.collection('messages').doc(result.messageId).get()).data();
  assert.equal(saved.text, request.data.text);
  assert.equal(saved.senderId, uid);
  assert.equal(saved.senderName, 'Preserved profile');
  assert.equal(saved.messageType, 'text');
  assert.equal(saved.roundIndex, 1);
  assert.ok(saved.createdAt.toMillis() > 0);
});
test('legacy request cannot bypass participant, finished or expired-turn restrictions', async () => {
  for (const [name, patch, reason] of [
    ['legacy-spectator', { fighter1: 'another', creatorId: 'another' }, 'TURN_NOT_FIGHTER'],
    ['legacy-finished', { status: 'finished' }, 'MESSAGE_DEBATE_FINISHED'],
    ['legacy-expired', { roundEndsAt: firestore.Timestamp.fromMillis(1) }, 'TURN_TIME_EXPIRED'],
  ]) {
    const { ref, request } = await scenario(name, patch);
    await assert.rejects(api.sendDebateMessage.run(request), error => error.details?.reason === reason);
    assert.equal((await ref.collection('messages').get()).size, 0);
  }
});
test('legacy request still rejects unauthenticated and banned senders', async () => {
  const { uid, request } = await scenario('legacy-account');
  await assert.rejects(api.sendDebateMessage.run({ data: request.data }), error => error.code === 'unauthenticated');
  await db.collection('users').doc(uid).update({ isBanned: true });
  await assert.rejects(api.sendDebateMessage.run(request), error => error.code === 'permission-denied');
});
test('APK 4004 World Chat request retries acknowledge the same message', async () => {
  const { uid } = await scenario('legacy-world');
  const request = { auth: { uid, token: {} }, data: {
    text: 'World Chat from APK 4004', clientRequestId: 'apk4004-world-message-0001',
  } };
  await rateLimitRef(db, uid, 'sendWorldMessage').delete();
  const first = await api.sendWorldMessage.run(request);
  const retry = await api.sendWorldMessage.run(request);
  assert.equal(first.ok, true);
  assert.equal(first.messageId, retry.messageId);
  const messages = await db.collection('world_messages').where('senderId', '==', uid).get();
  assert.equal(messages.size, 1);
  assert.equal(messages.docs[0].data().text, request.data.text);
});
test('older World Chat without an ID remains accepted', async () => {
  const { uid } = await scenario('older-world');
  await rateLimitRef(db, uid, 'sendWorldMessage').delete();
  const result = await api.sendWorldMessage.run({ auth: { uid, token: {} }, data: { text: 'Older text' } });
  assert.equal(result.ok, true);
  assert.equal((await db.collection('world_messages').doc(result.messageId).get()).data().text, 'Older text');
});
test('precise handoff accepts an old client without expectedTurn and transfers control once', async () => {
  const { uid, ref } = await scenario('legacy-handoff');
  const now = Date.now();
  const tasks = [];
  // Only external Cloud Tasks dispatch and wall clock are replaced; transaction is real.
  const controller = createDeadlineController(db, { enqueue: async data => tasks.push(data) }, () => now);
  assert.equal((await controller.handoff(ref.id, uid)).changed, true);
  const next = (await ref.get()).data();
  assert.equal(next.activeSpeakerId, 'opponent-legacy-handoff');
  assert.equal(next.roundIndex, 1);
  assert.ok(next.roundEndsAt.toMillis() > now);
  assert.equal(tasks.length, 1);
  await assert.rejects(controller.handoff(ref.id, uid));
  assert.equal((await ref.get()).data().activeSpeakerId, next.activeSpeakerId);
});
