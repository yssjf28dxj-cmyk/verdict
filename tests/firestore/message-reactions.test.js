import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc, getDocs, collection, setDoc } from 'firebase/firestore';
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const { createMessageReactionController } = require('./lib/message_reactions');
const { getFirestore } = require('firebase-admin/firestore');
const { getApp, deleteApp } = require('firebase-admin/app');
let env, db, functions, reaction, now;
const message = () => db.doc('debates/reaction-battle/messages/argument');
const tally = async (kind = 'strong') => (await message().collection('reaction_tallies').get()).docs.reduce((sum, doc) => sum + (doc.data()[kind] || 0), 0);
const request = (uid = 'viewer', overrides = {}) => reaction(uid, { debateId: 'reaction-battle', messageId: 'argument', kind: 'strong', active: true,
  expectedRevision: 0, clientRequestId: 'reaction-request-0001', ...overrides });
before(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST || '';
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw new Error('Local emulator required');
  process.env.GCLOUD_PROJECT = 'demo-verdict-rules';
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'demo-verdict-rules' });
  functions = require('./lib/index'); db = getFirestore();
  const [hostname, port] = host.split(':');
  env = await initializeTestEnvironment({ projectId: 'demo-verdict-rules', firestore: { host: hostname, port: Number(port),
    rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
});
after(async () => { await env.cleanup(); await deleteApp(getApp()); });
beforeEach(async () => {
  await env.clearFirestore(); now = 1000000;
  // The exported callable below separately exercises the production access helper.
  reaction = createMessageReactionController(db, (uid, data) => data.visibilityMode === 'public'
    || data.accessApprovedUserIds?.includes(uid) || [data.fighter1, data.fighter2].includes(uid), () => now);
  await db.doc('debates/reaction-battle').set({ status: 'active', visibilityMode: 'public', creationMode: 'public_feed',
    fighter1: 'alice', fighter2: 'bob', creatorId: 'alice', votes1: 2, votes2: 3, accessApprovedUserIds: [] });
  await message().set({ senderId: 'alice', text: 'An argument' });
});
test('spectator can add and remove each reaction independently without changing votes or text', async () => {
  assert.deepEqual(await request(), { active: true, revision: 1 });
  now += 1000;
  await request('viewer', { kind: 'source', clientRequestId: 'source-request-0002' });
  assert.equal(await tally(), 1); assert.equal(await tally('source'), 1);
  now += 1000;
  await request('viewer', { active: false, expectedRevision: 1, clientRequestId: 'remove-request-0003' });
  assert.equal(await tally(), 0); assert.equal(await tally('source'), 1);
  assert.equal((await message().get()).data().text, 'An argument');
  const battle = (await db.doc('debates/reaction-battle').get()).data();
  assert.equal(battle.votes1, 2); assert.equal(battle.votes2, 3);
});
test('parallel exact retries count once and acknowledge a lost response immediately', async () => {
  const responses = await Promise.all([request(), request()]);
  assert.deepEqual(responses[0], responses[1]); assert.equal(await tally(), 1);
  assert.deepEqual(await request(), { active: true, revision: 1 });
});
test('different requests using one old revision cannot both change state', async () => {
  const results = await Promise.allSettled([request(), request('viewer', { clientRequestId: 'different-request-0002' })]);
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(results.filter(r => r.status === 'rejected' && r.reason.code === 'aborted').length, 1);
  assert.equal(await tally(), 1);
});
test('an old retry cannot re-add a reaction after a later removal', async () => {
  await request(); now += 1000;
  await request('viewer', { active: false, expectedRevision: 1, clientRequestId: 'remove-request-0003' });
  await assert.rejects(request(), e => e.code === 'aborted'); assert.equal(await tally(), 0);
});
test('different spectators count independently across bounded shards', async () => {
  await Promise.all(Array.from({ length: 20 }, (_, i) => request(`viewer-${i}`)));
  assert.equal(await tally(), 20);
  assert.ok((await message().collection('reaction_tallies').get()).size <= 16);
});
test('server cooldown rolls back a second type without partial state', async () => {
  await request();
  await assert.rejects(request('viewer', { kind: 'source', clientRequestId: 'source-request-0002' }), e => e.code === 'resource-exhausted');
  assert.equal(await tally('source'), 0);
  assert.equal((await message().collection('reactions').doc('viewer').get()).data().source, undefined);
});
test('fighters and banned viewers cannot react or spoof a spectator identity', async () => {
  for (const uid of ['alice', 'bob']) await assert.rejects(request(uid, { uid: 'viewer' }), e => e.details?.reason === 'REACTION_NOT_SPECTATOR');
  await db.doc('users/viewer').set({ isBanned: true });
  await assert.rejects(request(), e => e.code === 'permission-denied'); assert.equal(await tally(), 0);
});
test('finished battles reject new changes but still acknowledge an already committed request', async () => {
  await request(); await db.doc('debates/reaction-battle').update({ status: 'finished' });
  assert.deepEqual(await request(), { active: true, revision: 1 });
  await assert.rejects(request('new-viewer'), e => e.code === 'failed-precondition');
});
test('missing messages and nonfighter system messages cannot receive reactions', async () => {
  await message().update({ senderId: 'system' });
  await assert.rejects(request(), e => e.code === 'not-found');
  await message().delete(); await assert.rejects(request(), e => e.code === 'not-found');
});
test('invalid locators, types, revisions and reused identity are rejected', async () => {
  for (const invalid of [{ debateId: '../secret' }, { messageId: '' }, { kind: 'vote' }, { active: 1 }, { expectedRevision: -1 }, { clientRequestId: 'short' }]) {
    await assert.rejects(request('viewer', invalid), e => e.code === 'invalid-argument');
  }
  await request(); await assert.rejects(request('viewer', { active: false }), e => e.code === 'already-exists');
});
test('the exported callable checks auth and real request-only transcript permissions', async () => {
  await assert.rejects(functions.setMessageReaction.run({ data: {} }), e => e.code === 'unauthenticated');
  await db.doc('debates/reaction-battle').update({ visibilityMode: 'request_only' });
  const data = { debateId: 'reaction-battle', messageId: 'argument', kind: 'strong', active: true, expectedRevision: 0, clientRequestId: 'actual-request-0001' };
  await assert.rejects(functions.setMessageReaction.run({ auth: { uid: 'viewer' }, data }), e => e.code === 'permission-denied');
  await db.doc('debates/reaction-battle').update({ accessApprovedUserIds: ['viewer'] });
  assert.equal((await functions.setMessageReaction.run({ auth: { uid: 'viewer' }, data })).active, true);
  await db.doc('debates/reaction-battle').update({ accessApprovedUserIds: [] });
  await assert.rejects(functions.setMessageReaction.run({ auth: { uid: 'viewer' }, data }), e => e.code === 'permission-denied');
});
test('counts follow transcript permissions and individual choices stay private and server-only', async () => {
  await request();
  const own = env.authenticatedContext('viewer').firestore();
  const other = env.authenticatedContext('outsider').firestore();
  const row = 'debates/reaction-battle/messages/argument/reactions/viewer';
  const shards = 'debates/reaction-battle/messages/argument/reaction_tallies';
  await assertSucceeds(getDoc(doc(own, row)));
  await assertFails(getDoc(doc(other, row)));
  await assertSucceeds(getDocs(collection(other, shards)));
  await assertFails(setDoc(doc(own, row), { strong: { active: false } }));
  await assertFails(setDoc(doc(own, `${shards}/0`), { strong: 999 }));
  await db.doc('debates/reaction-battle').update({ visibilityMode: 'request_only' });
  await assertFails(getDocs(collection(other, shards)));
  await assertFails(getDoc(doc(own, row)));
  await db.doc('debates/reaction-battle').update({ accessApprovedUserIds: ['viewer'] });
  await assertSucceeds(getDoc(doc(own, row)));
  await message().delete();
  await assertFails(getDoc(doc(own, row)));
  await assertFails(getDocs(collection(own, shards)));
});
