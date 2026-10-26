import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { before, after, beforeEach, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertFails } from '@firebase/rules-unit-testing';
import { doc, getDoc, setDoc } from 'firebase/firestore';
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
let db, api, environment;
const projectId = 'demo-verdict-rules';
const terms = { topic: 'A useful debate', durationSeconds: 60, totalRounds: 3,
  creationMode: 'public_feed', visibilityMode: 'public', languageCode: 'en', region: 'global', invitedUserId: '' };
const request = (patch = {}, uid = 'create-alice') => ({ auth: { uid, token: {} },
  data: { ...terms, clientRequestId: 'create-request-00000001', ...patch } });
before(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST || '';
  assert.match(host, /^(127\.0\.0\.1|localhost):\d+$/);
  process.env.GCLOUD_PROJECT = projectId;
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId });
  api = require('./lib/index');
  db = require('firebase-admin/firestore').getFirestore();
  const [hostname, port] = host.split(':');
  environment = await initializeTestEnvironment({ projectId, firestore: { host: hostname, port: Number(port),
    rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
});
after(async () => { await environment.cleanup(); await require('firebase-admin/app').deleteApp(require('firebase-admin/app').getApp()); });
beforeEach(async () => {
  await environment.clearFirestore();
  await db.doc('users/create-alice').set({ name: 'Alice' });
  await db.doc('users/create-bob').set({ name: 'Bob' });
});
test('lost response and immediate retries return one original challenge without cooldown errors', async () => {
  const first = await api.createDebate.run(request());
  const results = await Promise.all(Array.from({ length: 8 }, () => api.createDebate.run(request())));
  assert.deepEqual(new Set(results.map(r => r.debateId)), new Set([first.debateId]));
  assert.equal((await db.collection('debates').get()).size, 1);
  assert.equal((await db.collection('server_create_requests').get()).size, 1);
});
test('simultaneous first submissions create one challenge and receipt atomically', async () => {
  const results = await Promise.all(Array.from({ length: 6 }, () => api.createDebate.run(request())));
  assert.equal(new Set(results.map(r => r.debateId)).size, 1);
  assert.equal((await db.collection('debates').get()).size, 1);
});
test('same ID cannot change valid conditions, topic, visibility or opponent', async () => {
  await api.createDebate.run(request());
  for (const patch of [{ topic: 'Another useful topic' }, { totalRounds: 5 }, { durationSeconds: 120 },
    { languageCode: 'ru' }, { region: 'cis' }, { visibilityMode: 'request_only' },
    { creationMode: 'direct_invite', visibilityMode: 'private', invitedUserId: 'create-bob' }]) {
    await assert.rejects(api.createDebate.run(request(patch)), e => e.details?.reason === 'CREATE_REQUEST_REUSED');
  }
  assert.equal((await db.collection('debates').get()).size, 1);
});
test('new intention cannot evade create cooldown; another profile has an independent ID namespace', async () => {
  const first = await api.createDebate.run(request());
  await assert.rejects(api.createDebate.run(request({ clientRequestId: 'another-request-00002' })), e => e.code === 'resource-exhausted');
  const second = await api.createDebate.run(request({}, 'create-bob'));
  assert.notEqual(first.debateId, second.debateId);
  assert.equal((await db.collection('debates').get()).size, 2);
});
test('deleted challenge is never resurrected; cancelled challenge retains its original identity', async () => {
  const first = await api.createDebate.run(request());
  const ref = db.doc(`debates/${first.debateId}`);
  await ref.update({ status: 'cancelled' });
  assert.equal((await api.createDebate.run(request())).debateId, first.debateId);
  await ref.delete();
  await assert.rejects(api.createDebate.run(request()), e => e.details?.reason === 'CREATE_PREVIOUS_DELETED');
  assert.equal((await db.collection('debates').get()).size, 0);
});
test('ban and authentication checks apply even to exact successful retries', async () => {
  await api.createDebate.run(request());
  await db.doc('users/create-alice').update({ isBanned: true });
  await assert.rejects(api.createDebate.run(request()), e => e.code === 'permission-denied');
  await assert.rejects(api.createDebate.run({ data: request().data }), e => e.code === 'unauthenticated');
});
test('old client without request ID still creates a normal waiting challenge', async () => {
  const old = request(); delete old.data.clientRequestId;
  const result = await api.createDebate.run(old);
  const data = (await db.doc(`debates/${result.debateId}`).get()).data();
  assert.equal(data.creatorId, 'create-alice');
  assert.equal(data.status, 'waiting');
  assert.equal((await db.collection('server_create_requests').get()).size, 0);
});
test('invalid request identity or terms cannot create challenges or receipts', async () => {
  for (const patch of [{ clientRequestId: 'short' }, { clientRequestId: {} }, { totalRounds: 7 }]) {
    await assert.rejects(api.createDebate.run(request(patch)), e => e.code === 'invalid-argument');
  }
  assert.equal((await db.collection('debates').get()).size, 0);
  assert.equal((await db.collection('server_create_requests').get()).size, 0);
});
test('receipts are inaccessible to owner, outsider and unauthenticated clients', async () => {
  await api.createDebate.run(request());
  const receipt = (await db.collection('server_create_requests').get()).docs[0];
  for (const context of [environment.authenticatedContext('create-alice'), environment.authenticatedContext('create-bob'), environment.unauthenticatedContext()]) {
    const ref = doc(context.firestore(), receipt.ref.path);
    await assertFails(getDoc(ref));
    await assertFails(setDoc(ref, { debateId: 'forged' }));
  }
});
