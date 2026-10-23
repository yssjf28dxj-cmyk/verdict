import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { before, after, beforeEach, test } from 'node:test';
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const { getFirestore } = require('firebase-admin/firestore');
const { getApp, deleteApp } = require('firebase-admin/app');
let db, functions;
const id = 'invitation-locator-test';
const ref = () => db.collection('debates').doc(id);
const accept = (uid) => functions.acceptDebateInvite.run({ auth: { uid, token: {} }, data: { debateId: id } });
before(() => {
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '')) {
    throw new Error('Only a loopback Firestore emulator is allowed');
  }
  process.env.GCLOUD_PROJECT = 'demo-verdict-rules';
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: 'demo-verdict-rules' });
  functions = require('./lib/index');
  db = getFirestore();
});
after(async () => deleteApp(getApp()));
beforeEach(async () => {
  await db.recursiveDelete(ref());
  await ref().set({ creatorId: 'invite-owner', fighter1: 'invite-owner', fighter2: '',
    topic: 'Invitation', status: 'waiting', creationMode: 'public_feed', visibilityMode: 'public',
    durationSeconds: 60, roundDurationSeconds: 60, totalRounds: 3 });
  for (const uid of ['invite-owner', 'invite-friend', 'invite-other']) {
    await db.doc(`users/${uid}`).set({ name: uid, isBanned: false });
  }
});
test('knowing a private locator does not authorize accepting its challenge', async () => {
  await ref().update({ creationMode: 'direct_invite', visibilityMode: 'private', invitedUserId: 'invite-friend' });
  await assert.rejects(accept('invite-other'), (e) => e.details?.reason === 'ACCEPT_NOT_INVITED_USER');
  assert.equal((await ref().get()).data().status, 'waiting');
  await accept('invite-friend');
  assert.equal((await ref().get()).data().fighter2, 'invite-friend');
});
test('a creator cannot accept their own public invitation', async () => {
  await assert.rejects(accept('invite-owner'), (e) => e.details?.reason === 'ACCEPT_SELF_CHALLENGE');
  assert.equal((await ref().get()).data().status, 'waiting');
});
test('a signed-out link cannot accept a challenge', async () => {
  await assert.rejects(functions.acceptDebateInvite.run({ data: { debateId: id } }),
    (e) => e.code === 'unauthenticated');
  assert.equal((await ref().get()).data().status, 'waiting');
});
test('two people opening the same public link cannot both become the opponent', async () => {
  const results = await Promise.allSettled([accept('invite-friend'), accept('invite-other')]);
  assert.equal(results.filter((r) => r.status === 'fulfilled').length, 1);
  const saved = (await ref().get()).data();
  assert.equal(saved.status, 'active');
  assert.ok(['invite-friend', 'invite-other'].includes(saved.fighter2));
});
test('reopening and accepting again cannot restart a running battle or replace a fighter', async () => {
  await accept('invite-friend');
  const first = (await ref().get()).data();
  await accept('invite-friend');
  await assert.rejects(accept('invite-other'));
  const after = (await ref().get()).data();
  assert.equal(after.fighter2, first.fighter2);
  assert.equal(after.roundEndsAt.toMillis(), first.roundEndsAt.toMillis());
});
test('a cancelled invitation cannot be recreated by opening its old link', async () => {
  await functions.cancelDebateChallenge.run({ auth: { uid: 'invite-owner' }, data: { debateId: id } });
  await assert.rejects(accept('invite-friend'), (e) => e.code === 'not-found');
  assert.equal((await ref().get()).exists, false);
});
test('an invited but banned account cannot accept through a link', async () => {
  await ref().update({ creationMode: 'direct_invite', visibilityMode: 'private', invitedUserId: 'invite-friend' });
  await db.doc('users/invite-friend').update({ isBanned: true });
  await assert.rejects(accept('invite-friend'), (e) => e.details?.reason === 'ACCOUNT_BANNED');
  assert.equal((await ref().get()).data().status, 'waiting');
});
