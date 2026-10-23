import { createRequire } from 'node:module';
import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { doc, getDoc } from 'firebase/firestore';
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const { getFirestore } = require('firebase-admin/firestore');
const { getApp, deleteApp } = require('firebase-admin/app');
const { createRematchController } = require('./lib/rematches');
let db, functions, environment, request, now;
const projectId = 'demo-verdict-rules';
const source = () => db.doc('debates/rematch-source');
const original = () => ({ topic: 'Original topic', fighter1: 'rematch-alice', fighter2: 'rematch-bob',
  creatorId: 'rematch-alice', status: 'finished', durationSeconds: 60, roundDurationSeconds: 60,
  totalRounds: 3, roundIndex: 3, isRoundActive: false, languageCode: 'en', region: 'global',
  votes1: 91, votes2: 12, winner: 'fighter1', aiResult: { scoreA: 75 },
  timeBankMs: { 'rematch-alice': 9999 }, accessApprovedUserIds: ['old-viewer'] });
const offer = (uid = 'rematch-alice', key = 'rematch-request-0001', sourceDebateId = 'rematch-source') =>
  request(uid, { sourceDebateId, clientRequestId: key });
before(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST || '';
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw new Error('Only a loopback emulator is allowed');
  process.env.GCLOUD_PROJECT = projectId;
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId });
  functions = require('./lib/index');
  db = getFirestore();
  const [hostname, port] = host.split(':');
  environment = await initializeTestEnvironment({ projectId, firestore: { host: hostname, port: Number(port),
    rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
});
after(async () => { await environment.cleanup(); await deleteApp(getApp()); });
beforeEach(async () => {
  await environment.clearFirestore();
  now = 1000000;
  request = createRematchController(db, true, () => now);
  await source().set(original());
  await source().collection('messages').doc('old').set({ text: 'Original message' });
  await db.doc('users/rematch-alice').set({ name: 'Alice', rating: 50 });
  await db.doc('users/rematch-bob').set({ name: 'Bob', rating: 70 });
});
test('rematch creates a fresh private challenge while preserving the original battle', async () => {
  const before = (await source().get()).data();
  const sent = await offer();
  const fresh = (await db.doc(`debates/${sent.debateId}`).get()).data();
  assert.equal(sent.created, true);
  assert.equal(fresh.status, 'waiting');
  assert.equal(fresh.fighter1, 'rematch-alice');
  assert.equal(fresh.fighter2, 'rematch-bob');
  assert.equal(fresh.invitedUserId, 'rematch-bob');
  assert.equal(fresh.visibilityMode, 'private');
  assert.equal(fresh.creationMode, 'direct_invite');
  assert.equal(fresh.rematchOf, 'rematch-source');
  assert.equal(fresh.topic, before.topic);
  assert.equal(fresh.durationSeconds, 60); assert.equal(fresh.totalRounds, 3);
  assert.equal(fresh.votes1, 0); assert.equal(fresh.votes2, 0);
  assert.equal(fresh.roundIndex, 1);
  assert.equal(fresh.winner, undefined); assert.equal(fresh.aiResult, undefined);
  assert.equal(fresh.roundEndsAt, undefined);
  assert.equal(fresh.clockMode, 'bank_v1');
  assert.deepEqual(fresh.timeBankMs, { 'rematch-alice': 0 });
  assert.equal((await db.collection(`debates/${sent.debateId}/messages`).get()).size, 0);
  assert.deepEqual((await source().get()).data(), before);
  assert.equal((await source().collection('messages').get()).size, 1);
});
test('a spectator cannot request a rematch or impersonate one of the fighters', async () => {
  await assert.rejects(request('old-viewer', { sourceDebateId: source().id,
    clientRequestId: 'spectator-request-0001', uid: 'rematch-alice' }),
    (e) => e.details?.reason === 'REMATCH_NOT_FIGHTER');
  assert.equal((await db.collection('debates').get()).size, 1);
});
test('an unfinished battle cannot be rematched', async () => {
  await source().update({ status: 'active' });
  await assert.rejects(offer(), (e) => e.details?.reason === 'REMATCH_NOT_FINISHED');
});
test('lost-response retry returns the same challenge without duplication', async () => {
  const first = await offer();
  const retry = await offer();
  assert.equal(retry.debateId, first.debateId);
  assert.equal(retry.created, false);
  assert.equal((await db.collection('debates').get()).size, 2);
});
test('simultaneous offers from both fighters share one pending rematch', async () => {
  const results = await Promise.all([offer(), offer('rematch-bob', 'other-request-0002')]);
  assert.equal(results[0].debateId, results[1].debateId);
  assert.equal(results.filter((r) => r.created).length, 1);
  assert.equal((await db.collection('debates').get()).size, 2);
});
test('fresh IDs cannot spam receipt writes for an existing challenge, but exact retries stay immediate', async () => {
  const sent = await offer();
  await assert.rejects(offer('rematch-alice', 'spam-request-0002'), (e) => e.code === 'resource-exhausted');
  assert.equal((await offer()).debateId, sent.debateId);
  assert.equal((await db.collection('server_rematch_requests').get()).size, 1);
  now += 1000;
  assert.equal((await offer('rematch-alice', 'spam-request-0002')).debateId, sent.debateId);
  assert.equal((await db.collection('debates').get()).size, 2);
});
test('an old retry cannot resurrect a cancelled rematch; a new offer is explicit', async () => {
  const sent = await offer();
  await functions.cancelDebateChallenge.run({ auth: { uid: 'rematch-alice' }, data: { debateId: sent.debateId } });
  await assert.rejects(offer(), (e) => e.details?.reason === 'REMATCH_PREVIOUS_CANCELLED');
  assert.equal((await db.collection('debates').get()).size, 1);
  now += 6000;
  const again = await offer('rematch-alice', 'new-request-00003');
  assert.notEqual(again.debateId, sent.debateId);
});
test('reused request identity cannot target another original battle', async () => {
  await offer();
  await db.doc('debates/other-source').set(original());
  await assert.rejects(offer('rematch-alice', 'rematch-request-0001', 'other-source'), (e) => e.code === 'already-exists');
});
test('creation cooldown prevents another fresh rematch without partial documents', async () => {
  await offer();
  await db.doc('debates/other-source').set(original());
  await assert.rejects(offer('rematch-alice', 'new-request-00003', 'other-source'), (e) => e.code === 'resource-exhausted');
  assert.equal((await db.collection('debates').get()).size, 3);
  assert.equal((await db.collection('server_rematch_requests').get()).size, 1);
  now += 5000;
  assert.equal((await offer('rematch-alice', 'new-request-00003', 'other-source')).created, true);
});
test('banned participants cannot create a rematch', async () => {
  await db.doc('users/rematch-alice').update({ isBanned: true });
  await assert.rejects(offer(), (e) => e.details?.reason === 'ACCOUNT_BANNED');
  await db.doc('users/rematch-alice').update({ isBanned: false });
  await db.doc('users/rematch-bob').update({ isBanned: true });
  await assert.rejects(offer(), (e) => e.code === 'failed-precondition');
});
test('a private rematch does not inherit source viewers or expose server receipts', async () => {
  const sent = await offer();
  for (const uid of ['rematch-alice', 'rematch-bob']) {
    await assertSucceeds(getDoc(doc(environment.authenticatedContext(uid).firestore(), 'debates', sent.debateId)));
  }
  const outsider = environment.authenticatedContext('old-viewer').firestore();
  await assertFails(getDoc(doc(outsider, 'debates', sent.debateId)));
  await assertFails(getDoc(doc(outsider, 'server_rematch_slots', 'rematch-source')));
});
test('only the invited opponent can accept the fresh rematch and confirm its terms', async () => {
  const sent = await offer();
  await assert.rejects(functions.acceptDebateInvite.run({ auth: { uid: 'old-viewer' }, data: { debateId: sent.debateId } }));
  await functions.acceptDebateInvite.run({ auth: { uid: 'rematch-bob', token: {} }, data: { debateId: sent.debateId } });
  const fresh = (await db.doc(`debates/${sent.debateId}`).get()).data();
  assert.equal(fresh.status, 'active');
  assert.equal(fresh.termsResolutionStatus, 'resolved');
  assert.equal(fresh.fighter2, 'rematch-bob');
  assert.equal((await source().get()).data().votes1, 91);
});
test('the exported callable requires authentication and the normal creation schema still works', async () => {
  await assert.rejects(functions.requestRematch.run({ data: { sourceDebateId: source().id } }), (e) => e.code === 'unauthenticated');
  const created = await functions.createDebate.run({ auth: { uid: 'rematch-alice', token: {} },
    data: { topic: 'A normal challenge', durationSeconds: 60, totalRounds: 3, languageCode: 'en', region: 'global' } });
  const normal = (await db.doc(`debates/${created.debateId}`).get()).data();
  assert.equal(normal.status, 'waiting');
  assert.equal(normal.fighter1, 'rematch-alice'); assert.equal(normal.fighter2, '');
  assert.equal(normal.termsResolutionStatus, 'pending_opponent');
  assert.deepEqual(normal.accessApprovedUserIds, ['rematch-alice']);
  assert.equal(normal.rematchOf, undefined);
});
test('invalid source terms do not produce a malformed challenge', async () => {
  await source().update({ totalRounds: 999 });
  await assert.rejects(offer(), (e) => e.code === 'failed-precondition');
  assert.equal((await db.collection('debates').get()).size, 1);
});
