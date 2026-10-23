import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { before, after, test } from 'node:test';
import { setTimeout as delay } from 'node:timers/promises';
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const projectId = 'demo-verdict-text-fixed';
let db, api, firestore, deadlineController, readDeadline;
before(() => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
  process.env.GCLOUD_PROJECT = projectId;
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId });
  firestore = require('firebase-admin/firestore');
  api = require('./lib/index');
  db = firestore.getFirestore();
  ({ createDeadlineController: deadlineController, readDeadline } = require('./lib/debate_deadlines'));
});
after(async () => require('firebase-admin/app').deleteApp(require('firebase-admin/app').getApp()));
async function scenario(name) {
  const uid = `alice-${name}`;
  const ref = db.collection('debates').doc(name);
  await db.collection('users').doc(uid).set({ name: uid });
  await ref.set({ schemaVersion: 2, status: 'active', fighter1: uid, fighter2: `bob-${name}`,
    creatorId: uid, visibilityMode: 'public', activeSpeakerId: uid, roundIndex: 1,
    totalRounds: 3, roundDurationSeconds: 60, isRoundActive: true,
    roundEndsAt: firestore.Timestamp.fromMillis(Date.now() + 60000) });
  const request = { auth: { uid, token: {} }, data: { debateId: name, text: 'Original argument', senderName: uid, clientRequestId: 'text-request-00000001', expectedRound: 1, expectedSenderId: uid } };
  await api.sendDebateMessage.run(request); // Committed response deliberately discarded by the caller.
  assert.equal((await ref.collection('messages').get()).size, 1);
  return { ref, request };
}
async function transition(ref) {
  const data = (await ref.get()).data();
  const task = readDeadline(ref.id, data);
  // Actual deadline transaction; only delivery clock and external queue are controlled.
  const controller = deadlineController(db, { enqueue: async () => {} }, () => task.endMs);
  await controller.runTask(task);
}
test('lost response + retry after timeout retains one text in the same turn', async () => {
  const { ref, request } = await scenario('same-turn');
  await delay(2100); // Response unavailable beyond server cooldown, as with a 20s client timeout.
  await delay(700); // Existing client retry backoff.
  await api.sendDebateMessage.run(request);
  const messages = (await ref.collection('messages').get()).docs.map(d => d.data());
  console.log('EVIDENCE same-turn', JSON.stringify(messages.map(m => ({text:m.text, round:m.roundIndex}))));
  assert.equal(messages.length, 1);
});
test('immediate retry acknowledges prior success', async () => {
  const { ref, request } = await scenario('quick-retry');
  await api.sendDebateMessage.run(request);
  assert.equal((await ref.collection('messages').get()).size, 1);
});
test('retry after transition to opponent acknowledges original text without adding text', async () => {
  const { ref, request } = await scenario('opponent-turn');
  await transition(ref);
  await delay(2100);
  await api.sendDebateMessage.run(request);
  assert.equal((await ref.collection('messages').get()).size, 1);
});
test('old payload retried on the next own turn acknowledges round one without writing round two', async () => {
  const { ref, request } = await scenario('later-own-turn');
  await transition(ref);
  await transition(ref);
  await delay(2100);
  await api.sendDebateMessage.run(request);
  const rounds = (await ref.collection('messages').get()).docs.map(d => d.data().roundIndex).sort();
  console.log('EVIDENCE later-own-turn', JSON.stringify(rounds));
  assert.deepEqual(rounds, [1]);
});

test('concurrent retries commit one message and return one ID', async () => {
  const { ref, request } = await scenario('parallel');
  await delay(2100);
  request.data.clientRequestId = 'text-request-concurrent';
  const results = await Promise.all(Array.from({length: 8}, () => api.sendDebateMessage.run(request)));
  assert.equal(new Set(results.map(r => r.messageId)).size, 1);
  assert.equal((await ref.collection('messages').get()).size, 2);
});
test('changed text or original round cannot reuse a request ID', async () => {
  const { request } = await scenario('conflict');
  for (const patch of [{text:'Different argument'}, {expectedRound:2}]) {
    await assert.rejects(api.sendDebateMessage.run({...request, data:{...request.data,...patch}}), e => e.code === 'already-exists');
  }
});
test('new ID permits deliberate identical text, but old round cannot migrate', async () => {
  const { ref, request } = await scenario('new-intent');
  await delay(2100);
  await api.sendDebateMessage.run({...request,data:{...request.data,clientRequestId:'text-request-00000002'}});
  assert.equal((await ref.collection('messages').get()).size, 2);
  await transition(ref); await transition(ref);
  await assert.rejects(api.sendDebateMessage.run({...request,data:{...request.data,clientRequestId:'text-request-00000003'}}), e => e.details?.reason === 'TURN_TIME_EXPIRED' && e.details.textRequestUncommitted === true);
});
test('finished/expired turns allow acknowledgements only, never new messages', async () => {
  const { ref, request } = await scenario('expired');
  for (const patch of [{roundEndsAt:firestore.Timestamp.fromMillis(1)}, {status:'finished'}]) {
    await ref.update(patch);
    await api.sendDebateMessage.run(request);
    await assert.rejects(api.sendDebateMessage.run({...request,data:{...request.data,clientRequestId:'text-request-00000002'}}));
    assert.equal((await ref.collection('messages').get()).size,1);
  }
});
test('authentication, banned users and outsiders cannot retrieve receipts', async () => {
  const { request } = await scenario('authorization');
  await assert.rejects(api.sendDebateMessage.run({data:request.data}), e => e.code === 'unauthenticated');
  await assert.rejects(api.sendDebateMessage.run({...request,auth:{uid:'outsider',token:{}}}), e => e.code === 'permission-denied');
  await db.collection('users').doc(request.auth.uid).update({isBanned:true});
  await assert.rejects(api.sendDebateMessage.run(request), e => e.code === 'permission-denied');
});
test('same client ID is isolated between debates and fighters', async () => {
  const { ref, request } = await scenario('scope');
  const other = db.collection('debates').doc('scope-other');
  await other.set((await ref.get()).data());
  await delay(2100);
  const a = await api.sendDebateMessage.run({...request,data:{...request.data,debateId:other.id}});
  await transition(ref);
  const b = await api.sendDebateMessage.run({...request,auth:{uid:'bob-scope',token:{}},data:{...request.data,expectedSenderId:'bob-scope'}});
  assert.notEqual(a.messageId,b.messageId);
  assert.equal((await ref.collection('messages').get()).size,2);
  assert.equal((await other.collection('messages').get()).size,1);
});

test('deleted message is not resurrected; deleted debate cannot acknowledge', async () => {
  const {ref,request} = await scenario('deleted');
  const first = await api.sendDebateMessage.run(request);
  await ref.collection('messages').doc(first.messageId).delete();
  assert.equal((await api.sendDebateMessage.run(request)).messageId, first.messageId);
  assert.equal((await ref.collection('messages').get()).size,0);
  await ref.delete();
  await assert.rejects(api.sendDebateMessage.run(request),e => e.code === 'not-found');
});
test('revoked participation denies exact retries', async () => {
  const {ref,request} = await scenario('revoked');
  await ref.update({fighter1:'replacement',creatorId:'replacement',visibilityMode:'private'});
  await assert.rejects(api.sendDebateMessage.run(request),e => e.code === 'permission-denied');
});
test('partial and malformed request identities fail closed', async () => {
  const { request } = await scenario('invalid-request');
  for (const patch of [{expectedSenderId:undefined}, {clientRequestId:null}, {clientRequestId:undefined},
    {clientRequestId:'short'}, {expectedRound:undefined}, {expectedRound:1.5}, {debateId:123}]) {
    await assert.rejects(api.sendDebateMessage.run({...request,data:{...request.data,...patch}}),e => e.code === 'invalid-argument');
  }
});
test('native session switch cannot submit the previous fighter intention as opponent', async () => {
  const {ref,request} = await scenario('session-switch');
  await transition(ref);
  await assert.rejects(api.sendDebateMessage.run({
    ...request, auth:{uid:'bob-session-switch',token:{}},
    data:{...request.data, expectedSenderId:request.auth.uid},
  }), e => e.code === 'permission-denied');
  assert.equal((await ref.collection('messages').get()).size,1);
});
