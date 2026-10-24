import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import { before, after, beforeEach, test } from 'node:test';
import assert from 'node:assert/strict';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, setDoc, updateDoc } from 'firebase/firestore';
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { getApp, deleteApp } = require('firebase-admin/app');
const { createPushController } = require('./lib/push_notifications');
let db, env, push, now, sent, fail;
const key = 'a'.repeat(64), otherKey = 'b'.repeat(64);
const device = { token: 'fake-device-token-'.repeat(4), installationKey: key, platform: 'android', locale: 'ru', generation: 1 };
const battle = () => ({ status: 'active', fighter1: 'alice', fighter2: 'bob', creatorId: 'alice', activeSpeakerId: 'bob', isRoundActive: true, roundEndsAt: Timestamp.fromMillis(now + 60000) });
async function queue(before = { status: 'waiting' }, after = battle()) { await db.doc('debates/notification-battle').set(after); await push.enqueue('notification-battle', before, after, now); }
const rows = async () => (await db.collection('server_notification_outbox').get()).docs;
async function prepare(uid = 'bob', input = device) { await push.configure(uid, { enabled: true }); await push.register(uid, input); }
before(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST || ''; if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw new Error('Local emulator required');
  process.env.GCLOUD_PROJECT = 'demo-verdict-rules'; process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'demo-verdict-rules' });
  require('./lib/index'); db = getFirestore(); const [hostname, port] = host.split(':');
  env = await initializeTestEnvironment({ projectId: 'demo-verdict-rules', firestore: { host: hostname, port: Number(port), rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
});
after(async () => { await env.cleanup(); await deleteApp(getApp()); });
beforeEach(async () => {
  await env.clearFirestore(); now = Date.now(); sent = []; fail = false;
  push = createPushController(db, async messages => {
    sent.push(...messages); if (fail === 'transport') throw new Error('network');
    const responses = messages.map((_, i) => fail && i === messages.length - 1 ? { success: false, error: { code: fail } } : { success: true, messageId: 'fake' });
    return { responses, successCount: responses.filter(r => r.success).length, failureCount: responses.filter(r => !r.success).length };
  }, () => now);
});
test('default opt-out creates no inbox and replay stays suppressed after opt-in', async () => {
  await queue(); assert.equal((await rows()).length, 2); assert.equal((await db.collection('users/bob/notifications').get()).size, 0);
  await prepare(); await queue(); for (const row of await rows()) await push.deliver(row.id); assert.equal(sent.length, 0);
});
test('concurrent event replay creates one inbox entry and one generic delivery', async () => {
  await prepare(); const after = battle(); await db.doc('debates/notification-battle').set(after);
  await Promise.all([push.enqueue('notification-battle', { status: 'waiting' }, after, now), push.enqueue('notification-battle', { status: 'waiting' }, after, now)]);
  assert.equal((await db.collection('users/bob/notifications').get()).size, 1);
  const row = (await rows()).find(row => row.data().uid === 'bob'); await push.deliver(row.id); await push.deliver(row.id);
  assert.equal(sent.length, 1); assert.equal(sent[0].data.uid, 'bob'); assert.equal(sent[0].notification.body, 'Ваш ход'); assert.equal(JSON.stringify(sent).includes('topic'), false);
});
test('stale turns, lost membership, expiry, bans and opt-out suppress queued delivery', async () => {
  for (const change of [{ activeSpeakerId: 'alice' }, { fighter2: 'other' }, { status: 'finished' }]) {
    await env.clearFirestore(); await prepare(); await queue(); await db.doc('debates/notification-battle').update(change);
    for (const row of await rows()) await push.deliver(row.id);
  }
  assert.equal(sent.length, 0);
  for (const mode of ['expired', 'disabled', 'banned']) {
    await env.clearFirestore(); await prepare(); await queue();
    if (mode === 'expired') now += 61000;
    if (mode === 'disabled') await push.configure('bob', { enabled: false });
    if (mode === 'banned') await db.doc('users/bob').set({ isBanned: true });
    for (const row of await rows()) await push.deliver(row.id);
  }
  assert.equal(sent.length, 0);
});
test('same installation may switch accounts but token possession alone cannot steal its binding', async () => {
  await prepare(); await push.configure('alice', { enabled: true });
  await assert.rejects(push.register('alice', { ...device, installationKey: otherKey }), e => e.code === 'permission-denied');
  await push.register('alice', { ...device, generation: 2 }); await queue(); for (const row of await rows()) await push.deliver(row.id);
  assert.equal(sent.length, 1); assert.equal(sent[0].data.uid, 'alice');
  await push.unregister('alice', { installationKey: key, generation: 3 }); assert.equal((await db.collection('server_push_devices').get()).size, 0);
});
test('rotation retires old tokens and an unrelated installation cannot unregister them', async () => {
  await prepare(); now += 1100; await push.register('bob', { ...device, token: 'rotated-token-'.repeat(4), generation: 2 });
  assert.equal((await db.collection('server_push_devices').get()).size, 1);
  await push.unregister('other', { installationKey: otherKey, generation: 2 }); assert.equal((await db.collection('server_push_devices').get()).size, 1);
});
test('partial failures retry only failed devices and invalid tokens are retired', async () => {
  await prepare(); now += 1100; await push.register('bob', { ...device, token: 'second-token-'.repeat(4), installationKey: otherKey });
  await queue(); const row = (await rows()).find(row => row.data().uid === 'bob');
  fail = 'messaging/server-unavailable'; await assert.rejects(push.deliver(row.id)); fail = false; await push.deliver(row.id); assert.equal(sent.length, 3);
  assert.equal((await row.ref.get()).data().status, 'sent');
  await env.clearFirestore(); sent = []; await prepare(); await queue(); fail = 'messaging/registration-token-not-registered';
  await push.deliver((await rows()).find(row => row.data().uid === 'bob').id); assert.equal((await db.collection('server_push_devices').get()).size, 0);
});
test('transport failure is retryable and no-device delivery completes safely', async () => {
  await prepare(); await queue(); const row = (await rows()).find(row => row.data().uid === 'bob');
  fail = 'transport'; await assert.rejects(push.deliver(row.id)); assert.equal((await row.ref.get()).data().status, 'pending');
  fail = false; await push.deliver(row.id); await env.clearFirestore(); await push.configure('bob', { enabled: true }); await queue();
  await push.deliver((await rows()).find(row => row.data().uid === 'bob').id);
});
test('settings, tokens and inboxes are private and clients cannot forge locators or deliveries', async () => {
  await prepare(); await queue(); const own = env.authenticatedContext('bob').firestore(), other = env.authenticatedContext('other').firestore();
  const row = (await db.collection('users/bob/notifications').get()).docs[0];
  await assertSucceeds(getDocs(collection(own, 'users/bob/notifications'))); await assertSucceeds(updateDoc(doc(own, row.ref.path), { read: true }));
  await assertFails(updateDoc(doc(own, row.ref.path), { uid: 'other' })); await assertFails(getDocs(collection(other, 'users/bob/notifications')));
  await assertSucceeds(getDoc(doc(own, 'users/bob/private_settings/notifications'))); await assertFails(getDoc(doc(other, 'users/bob/private_settings/notifications')));
  await assertFails(setDoc(doc(own, 'users/bob/private_settings/notifications'), { enabled: true }));
  for (const path of ['server_push_devices', 'server_push_installs', 'server_notification_outbox']) await assertFails(getDocs(collection(own, path)));
});
test('invalid registrations and banned users cannot bypass opt-in', async () => {
  await assert.rejects(push.register('bob', device), e => e.code === 'permission-denied');
  await assert.rejects(push.configure('bob', { enabled: 'true' }), e => e.code === 'invalid-argument'); await push.configure('bob', { enabled: true });
  await assert.rejects(push.register('bob', { ...device, platform: 'web' }), e => e.code === 'invalid-argument');
  for (const locale of ['__proto__', 'constructor', 'unknown']) await assert.rejects(push.register('bob', { ...device, locale }), e => e.code === 'invalid-argument'); await db.doc('users/bob').set({ isBanned: true });
  await assert.rejects(push.register('bob', device), e => e.code === 'permission-denied'); await push.configure('bob', { enabled: false });
});

test('a registration arriving after logout cannot recreate the retired device binding', async () => {
  await prepare();
  await push.unregister('bob', { installationKey: key, generation: 2 });
  await assert.rejects(push.register('bob', device), e => e.code === 'aborted');
  assert.equal((await db.collection('server_push_devices').get()).size, 0);
  now += 1100;
  await push.register('bob', { ...device, generation: 3 });
  await assert.rejects(push.unregister('bob', { installationKey: key, generation: 2 }), e => e.code === 'aborted');
  assert.equal((await db.collection('server_push_devices').get()).size, 1);
});
test('logout fences also reject a first registration that had not committed yet', async () => {
  await push.configure('bob', { enabled: true });
  await push.unregister('bob', { installationKey: key, generation: 2 });
  await assert.rejects(push.register('bob', device), e => e.code === 'aborted');
  assert.equal((await db.collection('server_push_devices').get()).size, 0);
});
test('exported registration and preference endpoints require authenticated callers', async () => {
  const functions = require('./lib/index');
  for (const name of ['configurePushNotifications', 'registerPushDevice', 'unregisterPushDevice']) {
    await assert.rejects(functions[name].run({ data: {} }), e => e.code === 'unauthenticated');
  }
});
