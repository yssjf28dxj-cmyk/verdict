import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { before, after, beforeEach, test } from 'node:test';
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const firestore = require('firebase-admin/firestore');
const { getApp, deleteApp } = require('firebase-admin/app');
let db, functions;
const projectId = 'demo-verdict-rules';
const debateId = 'cancel-button-test';
before(() => {
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '')) {
    throw new Error('Cancellation tests require a loopback emulator');
  }
  process.env.GCLOUD_PROJECT = projectId;
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId });
  functions = require('./lib/index');

  db = firestore.getFirestore();
});
after(async () => deleteApp(getApp()));
beforeEach(async () => {
  await db.collection('debates').doc(debateId).set({
    creatorId: 'owner', fighter1: 'owner', fighter2: '', status: 'waiting',
  });
});
const cancel = (uid) => functions.cancelDebateChallenge.run({ auth: { uid }, data: { debateId } });
test('creator can cancel a waiting challenge', async () => {
  await cancel('owner');
  assert.equal((await db.collection('debates').doc(debateId).get()).exists, false);
});
test('another guest cannot cancel the original guest challenge', async () => {
  await assert.rejects(cancel('new-guest'), (e) => e.details?.reason === 'CANCEL_NOT_CREATOR');
  assert.equal((await db.collection('debates').doc(debateId).get()).exists, true);
});
test('creator cannot cancel once an opponent has started the debate', async () => {
  await db.collection('debates').doc(debateId).update({ fighter2: 'opponent', status: 'active' });
  await assert.rejects(cancel('owner'), (e) => e.details?.reason === 'CANCEL_STATUS_INVALID');
  assert.equal((await db.collection('debates').doc(debateId).get()).data().status, 'active');
});
