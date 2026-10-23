import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { before, after, beforeEach, test } from 'node:test';
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const firestore = require('firebase-admin/firestore');
const { initializeApp, getApp, deleteApp } = require('firebase-admin/app');
const { createDeadlineController, readDeadline } = require('./lib/debate_deadlines');
const projectId = 'demo-verdict-rules';
let db, controller, now, tasks, enqueueFailure;
const timestamp = (ms) => firestore.Timestamp.fromMillis(ms);
const seed = (patch = {}) => ({
  status: 'active', fighter1: 'alice', fighter2: 'bob', activeSpeakerId: 'alice',
  roundIndex: 1, totalRounds: 3, roundDurationSeconds: 60, isRoundActive: true,
  roundEndsAt: timestamp(100000), ...patch,
});
const ref = () => db.collection('debates').doc('deadline-test');
before(() => {
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '')) {
    throw new Error('Only a loopback Firestore emulator is allowed');
  }
  initializeApp({ projectId });
  db = firestore.getFirestore();
});
after(async () => deleteApp(getApp()));
beforeEach(async () => {
  await db.recursiveDelete(ref());
  now = 100000;
  tasks = [];
  enqueueFailure = null;
  controller = createDeadlineController(db, { enqueue: async (data, options) => {
    if (enqueueFailure) throw enqueueFailure;
    tasks.push({ data, options });
  } }, () => now);
});
test('server schedules a turn with no connected client', async () => {
  const data = seed();
  await ref().set(data);
  await controller.onWrite(ref().id, undefined, data);
  assert.equal(tasks.length, 1);
  assert.equal(tasks[0].options.scheduleTime.getTime(), 100000);
  await controller.runTask(tasks[0].data);
  const next = (await ref().get()).data();
  assert.equal(next.activeSpeakerId, 'bob');
  assert.equal(next.roundEndsAt.toMillis(), 160000);
  assert.equal(tasks.at(-1).data.speaker, 'bob');
});
test('concurrent duplicate delivery advances only once', async () => {
  const data = seed();
  await ref().set(data);
  const task = readDeadline(ref().id, data);
  await Promise.all([controller.runTask(task), controller.runTask(task)]);
  const next = (await ref().get()).data();
  assert.equal(next.activeSpeakerId, 'bob');
  assert.equal(next.roundIndex, 1);
});
test('old task after penalty or manual deadline change cannot advance the new turn', async () => {
  const data = seed();
  const task = readDeadline(ref().id, data);
  await ref().set(seed({ roundEndsAt: timestamp(130000) }));
  await controller.runTask(task);
  assert.equal((await ref().get()).data().activeSpeakerId, 'alice');
});
test('waiting and finished debates ignore obsolete tasks', async () => {
  const task = readDeadline(ref().id, seed());
  for (const status of ['waiting', 'finished']) {
    await ref().set(seed({ status }));
    await controller.runTask(task);
    assert.equal((await ref().get()).data().status, status);
  }
});
test('late task catches up and finishes with existing vote schema', async () => {
  const data = seed({ totalRounds: 1 });
  await ref().set(data);
  await ref().collection('votes').doc('viewer').set({ uid: 'viewer', round_1: 2, debate: 2 });
  now = 300000;
  await controller.runTask(readDeadline(ref().id, data));
  const result = (await ref().get()).data();
  assert.equal(result.status, 'finished');
  assert.equal(result.winner, 'fighter2');
  assert.equal(result.votes2, 2);
  assert.equal(tasks.length, 0);
});
test('unrelated metadata changes do not enqueue another task', async () => {
  const data = seed();
  await ref().set(data);
  await controller.onWrite(ref().id, data, { ...data, viewerCount: 10 });
  assert.equal(tasks.length, 0);
});
test('out-of-order Firestore event schedules latest state instead of old deadline', async () => {
  const older = seed();
  await ref().set(seed({ activeSpeakerId: 'bob', roundEndsAt: timestamp(160000) }));
  await controller.onWrite(ref().id, undefined, older);
  assert.equal(tasks[0].data.speaker, 'bob');
  assert.equal(tasks[0].data.endMs, 160000);
});
test('failed enqueue is retried after the transition already committed', async () => {
  const data = seed();
  await ref().set(data);
  const task = readDeadline(ref().id, data);
  enqueueFailure = new Error('unavailable');
  await assert.rejects(controller.runTask(task));
  assert.equal((await ref().get()).data().activeSpeakerId, 'bob');
  enqueueFailure = null;
  await controller.runTask(task);
  assert.equal((await ref().get()).data().roundIndex, 1);
  assert.equal(tasks[0].data.speaker, 'bob');
});
test('only duplicate-task errors are swallowed', async () => {
  await ref().set(seed());
  enqueueFailure = { code: 'functions/task-already-exists' };
  await controller.schedule(ref().id);
  enqueueFailure = { code: 'functions/permission-denied' };
  await assert.rejects(controller.schedule(ref().id));
});
test('early task requests retry and does not grant the next speaker time', async () => {
  const data = seed();
  await ref().set(data);
  now = 99999;
  await assert.rejects(controller.runTask(readDeadline(ref().id, data)), /not arrived/);
  assert.equal((await ref().get()).data().activeSpeakerId, 'alice');
});
test('client advance remains restricted to participants', async () => {
  await ref().set(seed());
  await assert.rejects(controller.advance(ref().id, undefined, 'viewer'), /участники/);
  assert.equal((await ref().get()).data().activeSpeakerId, 'alice');
});
test('deleted debate and malformed payload do not recreate documents', async () => {
  const task = readDeadline(ref().id, seed());
  await controller.runTask(task);
  await assert.rejects(controller.runTask({ debateId: '../users' }));
  assert.equal((await ref().get()).exists, false);
});
