import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { before, after, beforeEach, test } from 'node:test';

const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const firestore = require('firebase-admin/firestore');
const { getApp, deleteApp } = require('firebase-admin/app');
const projectId = 'demo-verdict-rules';
const alice = 'foundation-alice';
const bob = 'foundation-bob';
const viewer = 'foundation-viewer';
const debateId = 'foundation-ai-debate';
let db, functions, createAiJudgeController, consumeRateLimit, rateLimitRef, requestDocumentId;
const ref = () => db.collection('debates').doc(debateId);
const privateRef = () => ref().collection('private_state').doc('judgement');
const validResult = (patch = {}) => ({
  winnerId: alice, winnerKey: 'fighter1', scoreA: 80, scoreB: 20,
  reasoning: 'The first fighter supported the argument with evidence.', ...patch,
});
const deferred = () => {
  let resolve;
  const promise = new Promise((done) => { resolve = done; });
  return { promise, resolve };
};
const seed = async ({ text = 'An argument backed by evidence.', ...patch } = {}) => {
  await ref().set({
    status: 'finished', fighter1: alice, fighter2: bob, topic: 'A test debate',
    winner: 'fighter2', votes1: 2, votes2: 3, profileStatsApplied: true, ...patch,
  });
  if (text) await ref().collection('messages').doc('argument').set({
    senderId: alice, messageType: 'text', text, createdAt: firestore.Timestamp.fromMillis(1),
  });
};

before(() => {
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '')) {
    throw new Error('Foundation tests require a loopback Firestore emulator');
  }
  process.env.GCLOUD_PROJECT = projectId;
  process.env.FIREBASE_CONFIG = JSON.stringify({ projectId });
  functions = require('./lib/index');

  db = firestore.getFirestore();
  ({ createAiJudgeController } = require('./lib/ai_judgement'));
  ({ consumeRateLimit, rateLimitRef, requestDocumentId } = require('./lib/request_control'));
});
after(async () => deleteApp(getApp()));
beforeEach(async () => {
  await db.recursiveDelete(ref());
  await db.collection('admin_runtime').doc('migration_access').delete();
  for (const uid of [alice, bob, viewer]) {
    await db.collection('users').doc(uid).set({ name: uid, wins: 7, rating: 100 });
    for (const action of ['sendWorldMessage', 'foundation-test']) await rateLimitRef(db, uid, action).delete();
    const messages = await db.collection('world_messages').where('senderId', '==', uid).get();
    await Promise.all(messages.docs.map((message) => message.ref.delete()));
  }
});

test('AI claims one lease across concurrent participant calls and caches the private result', async () => {
  await seed();
  const entered = deferred();
  const provider = deferred();
  let calls = 0;
  const judge = createAiJudgeController(db, async (input) => {
    calls++;
    assert.equal(input.fighter1, alice);
    assert.match(input.transcript, /^\[A\]: An argument/);
    entered.resolve();
    return provider.promise;
  });
  const first = judge(debateId, alice);
  await entered.promise;
  await assert.rejects(judge(debateId, bob), (error) => error.details?.reason === 'FINALIZE_IN_PROGRESS');
  provider.resolve(validResult());
  const result = await first;
  assert.equal(result.ok, true);
  assert.equal(Object.hasOwn(result.aiResult, 'judgedAt'), false, 'Fresh callable result must not contain a server sentinel or undefined');
  assert.equal(calls, 1);
  assert.equal((await privateRef().get()).data().aiResult.status, 'ready');
  const root = (await ref().get()).data();
  assert.equal(root.aiResult, undefined);
  assert.equal(root.aiJudgeLease, undefined);
  assert.equal(root.winner, 'fighter2', 'Advisory AI must not overwrite the audience winner');
  assert.equal((await db.collection('users').doc(alice).get()).data().wins, 7);
  assert.equal((await judge(debateId, bob)).aiResult.winnerId, alice);
  assert.equal(calls, 1);
});

test('empty transcripts and missing model configuration are explicit states, never synthetic draws', async () => {
  for (const [text, status, reason] of [
    ['', 'insufficient_content', 'no_content'],
    ['A substantive argument', 'unavailable', 'not_configured'],
  ]) {
    await db.recursiveDelete(ref());
    await seed({ text });
    const result = await createAiJudgeController(db)(debateId, alice);
    assert.equal(result.ok, false);
    assert.equal(result.aiResult.status, status);
    assert.equal(result.aiResult.reason, reason);
    for (const key of ['winnerId', 'winnerKey', 'scoreA', 'scoreB']) assert.equal(result.aiResult[key], undefined);
  }
});

test('untrusted model output cannot award an unrelated account or modify profile statistics', async () => {
  await seed();
  const judge = createAiJudgeController(db, async () => validResult({ winnerId: viewer }));
  const result = await judge(debateId, alice);
  assert.equal(result.aiResult.status, 'error');
  assert.equal(result.aiResult.reason, 'unavailable');
  assert.equal(result.aiResult.winnerId, undefined);
  assert.equal((await db.collection('users').doc(viewer).get()).data().wins, 7);
  assert.equal((await ref().get()).data().winner, 'fighter2');
});

test('only participants in finished debates can request AI analysis', async () => {
  await seed();
  const judge = createAiJudgeController(db, async () => validResult());
  await assert.rejects(judge(debateId, viewer), (error) => error.details?.reason === 'FINALIZE_NOT_PARTICIPANT');
  await ref().update({ status: 'active' });
  await assert.rejects(judge(debateId, alice), (error) => error.details?.reason === 'FINALIZE_NOT_FINISHED');
  assert.equal((await privateRef().get()).exists, false);
});

test('legacy public verdict moves to the protected document when requested again', async () => {
  await seed({ aiResult: validResult() });
  let calls = 0;
  const result = await createAiJudgeController(db, async () => { calls++; return validResult(); })(debateId, alice);
  assert.equal(calls, 0);
  assert.equal(result.aiResult.status, 'ready');
  assert.equal((await ref().get()).data().aiResult, undefined);
  assert.equal((await privateRef().get()).data().aiResult.winnerId, alice);
});

test('a stale lease holder cannot overwrite a newer judgement or report its own uncommitted result', async () => {
  await seed();
  let now = 1000;
  const entered = deferred();
  const provider = deferred();
  const oldJudge = createAiJudgeController(db, async () => { entered.resolve(); return provider.promise; }, () => now);
  const first = oldJudge(debateId, alice);
  await entered.promise;
  now += 120001;
  const nextResult = validResult({ winnerId: bob, winnerKey: 'fighter2', scoreA: 20, scoreB: 80 });
  await createAiJudgeController(db, async () => nextResult, () => now)(debateId, bob);
  provider.resolve(validResult());
  assert.equal((await first).aiResult.winnerId, bob);
  assert.equal((await privateRef().get()).data().aiResult.winnerId, bob);
});

test('deleted debates cannot be recreated by a pending judge', async () => {
  await seed();
  const entered = deferred();
  const provider = deferred();
  const judge = createAiJudgeController(db, async () => { entered.resolve(); return provider.promise; });
  const pending = judge(debateId, alice);
  await entered.promise;
  await ref().delete();
  provider.resolve(validResult());
  await assert.rejects(pending, (error) => error.details?.reason === 'FINALIZE_NOT_FOUND');
  assert.equal((await privateRef().get()).exists, false);
});

test('transactional rate limits admit one concurrent request and remain effective across controllers', async () => {
  const attempts = await Promise.allSettled(Array.from({ length: 8 }, () => consumeRateLimit(db, alice, 'foundation-test', 60000)));
  assert.equal(attempts.filter((result) => result.status === 'fulfilled').length, 1);
  for (const rejected of attempts.filter((result) => result.status === 'rejected')) {
    assert.equal(rejected.reason.details?.reason, 'RATE_LIMIT_EXCEEDED');
  }
  await assert.rejects(consumeRateLimit(db, alice, 'foundation-test', 60000), (error) => error.details?.reason === 'RATE_LIMIT_EXCEEDED');
  await consumeRateLimit(db, bob, 'foundation-test', 60000);
});

const send = (uid, text, clientRequestId) => functions.sendWorldMessage.run({ auth: { uid, token: {} }, data: { text, clientRequestId } });

test('World Chat retry with the same request id creates one message and bypasses only its already-committed rate limit', async () => {
  const id = 'chat-request-'.padEnd(40, 'a');
  const results = await Promise.all([send(alice, 'Hello world', id), send(alice, 'Hello world', id)]);
  assert.ok(results.every((result) => result.ok));
  assert.equal((await db.collection('world_messages').where('senderId', '==', alice).get()).size, 1);
  const stored = await db.collection('world_messages').doc(requestDocumentId(alice, id)).get();
  assert.equal(stored.data().text, 'Hello world');
  await assert.rejects(send(alice, 'Changed text', id), (error) => error.details?.reason === 'WORLD_REQUEST_REUSED');
  // Emulator transaction retries can themselves exceed the three-second
  // interval. Start a fresh interval before testing a different request.
  await rateLimitRef(db, alice, 'sendWorldMessage').set({ lastAtMs: Date.now() });
  await assert.rejects(send(alice, 'Another request', 'b'.repeat(40)), (error) => error.details?.reason === 'RATE_LIMIT_EXCEEDED');
  await send(bob, 'A different account', id);
  assert.equal((await db.collection('world_messages').where('senderId', '==', bob).get()).size, 1);
});

test('banned users cannot post or use duplicate retries to bypass their ban', async () => {
  const id = 'banned-request-'.padEnd(40, 'a');
  await send(alice, 'Before the ban', id);
  await db.collection('users').doc(alice).update({ isBanned: true });
  await assert.rejects(send(alice, 'Before the ban', id), (error) =>
    ['ACCOUNT_BANNED', 'WORLD_USER_BANNED'].includes(error.details?.reason));
  await assert.rejects(send(alice, 'After the ban', 'c'.repeat(40)), (error) =>
    ['ACCOUNT_BANNED', 'WORLD_USER_BANNED'].includes(error.details?.reason));
});

test('delayed create events preserve accepted turns and never initialize waiting or finished debates', async () => {
  await seed({ text: '', status: 'waiting', fighter2: '' });
  const oldSnapshot = await ref().get();
  const activeEnd = firestore.Timestamp.fromMillis(Date.now() + 60000);
  await ref().update({
    status: 'active', fighter2: bob, activeSpeakerId: bob, roundIndex: 2,
    roundEndsAt: activeEnd, isRoundActive: true,
  });
  await functions.initDebateOnCreate.run({ data: oldSnapshot });
  let fresh = (await ref().get()).data();
  assert.equal(fresh.activeSpeakerId, bob);
  assert.equal(fresh.roundIndex, 2);
  assert.equal(fresh.roundEndsAt.toMillis(), activeEnd.toMillis());
  await ref().set({ status: 'finished', fighter1: alice, fighter2: bob });
  await functions.initDebateOnCreate.run({ data: oldSnapshot });
  fresh = (await ref().get()).data();
  assert.equal(fresh.status, 'finished');
  assert.equal(fresh.roundEndsAt, undefined);
  await ref().set({ status: 'waiting', fighter1: alice, fighter2: '' });
  await functions.initDebateOnCreate.run({ data: oldSnapshot });
  fresh = (await ref().get()).data();
  assert.equal(fresh.status, 'waiting');
  assert.equal(fresh.roundEndsAt, undefined);
  await ref().delete();
  await functions.initDebateOnCreate.run({ data: oldSnapshot });
  assert.equal((await ref().get()).exists, false);
});

test('replayed result events apply audience profile statistics exactly once', async () => {
  await seed({ text: '', profileStatsApplied: false });
  const after = await ref().get();
  const event = { data: { before: { data: () => ({ status: 'active' }) }, after } };
  await Promise.all([
    functions.applyDebateResultToProfiles.run(event),
    functions.applyDebateResultToProfiles.run(event),
  ]);
  const winner = (await db.collection('users').doc(bob).get()).data();
  const loser = (await db.collection('users').doc(alice).get()).data();
  assert.equal(winner.wins, 8);
  assert.equal(winner.totalDebates, 1);
  assert.equal(loser.wins, 7);
  assert.equal(loser.losses, 1);
  await functions.applyDebateResultToProfiles.run(event);
  assert.equal((await db.collection('users').doc(bob).get()).data().totalDebates, 1);
});

const vote = (uid, data = {}) => functions.castVote.run({
  auth: { uid, token: {} }, data: { debateId, side: 1, scope: 'round', expectedRoundIndex: 1, ...data },
});
const seedLiveVote = (patch = {}) => seed({
  text: '', status: 'active', voteTallyVersion: 1, schemaVersion: 2,
  roundIndex: 1, totalRounds: 3, isRoundActive: true,
  activeSpeakerId: alice, roundEndsAt: firestore.Timestamp.fromMillis(Date.now() + 60000), ...patch,
});

test('concurrent duplicate votes commit one private vote and one aggregate increment', async () => {
  await seedLiveVote();
  const attempts = await Promise.allSettled(Array.from({ length: 4 }, () => vote(viewer)));
  assert.equal(attempts.filter((result) => result.status === 'fulfilled').length, 1);
  for (const rejected of attempts.filter((result) => result.status === 'rejected')) {
    assert.equal(rejected.reason.details?.reason, 'VOTE_ALREADY_CAST');
  }
  assert.equal((await ref().collection('votes').doc(viewer).get()).data().round_1, 1);
  const tallies = await ref().collection('vote_tallies').get();
  assert.equal(tallies.docs.reduce((sum, shard) => sum + shard.data().votes1, 0), 1);
  assert.equal(tallies.docs.reduce((sum, shard) => sum + shard.data().votes2, 0), 0);
  assert.ok(tallies.docs.every((shard) => !Object.hasOwn(shard.data(), 'uid')));
});

test('a delayed round vote cannot silently count toward the next round', async () => {
  await seedLiveVote({ roundIndex: 2 });
  await assert.rejects(vote(viewer), (error) => error.details?.reason === 'VOTE_ROUND_CHANGED');
  assert.equal((await ref().collection('votes').doc(viewer).get()).exists, false);
  assert.equal((await ref().collection('vote_tallies').get()).size, 0);
});

test('expired and invalid canonical deadlines reject votes even if the status still says active', async () => {
  await seedLiveVote({ roundEndsAt: firestore.Timestamp.fromMillis(Date.now() - 1) });
  await assert.rejects(vote(viewer), (error) => error.details?.reason === 'VOTE_TIME_EXPIRED');
  await ref().update({ roundEndsAt: firestore.FieldValue.delete() });
  await assert.rejects(vote(viewer), (error) => error.details?.reason === 'VOTE_DEADLINE_INVALID');
  assert.equal((await ref().collection('votes').doc(viewer).get()).exists, false);
});

const administrativeAccess = (uid, token = {}) => functions.getAdministrativeAccess.run({
  auth: uid ? { uid, token } : undefined, data: {},
});
const denyAdministrativeActions = async (uid, token = {}) => {
  await seed({ text: '' });
  const chatRef = db.collection('world_messages').doc('foundation-admin-chat');
  await chatRef.set({ text: 'Keep this message', senderId: alice });
  const auth = { uid, token };
  for (const [action, data] of [
    [functions.adminBanUser, { userId: bob }],
    [functions.adminDeleteDebate, { debateId }],
    [functions.adminClearWorldChat, {}],
  ]) await assert.rejects(action.run({ auth, data }), (error) => error.code === 'permission-denied');
  assert.equal((await db.collection('users').doc(bob).get()).data().isBanned, undefined);
  assert.equal((await ref().get()).exists, true);
  assert.equal((await chatRef.get()).exists, true);
};

test('a GRANDMASTER rank grants no administrative privileges or destructive access', async () => {
  await db.collection('users').doc(alice).update({ rank: 'GRANDMASTER' });
  assert.deepEqual(await administrativeAccess(alice), { admin: false, migration: false });
  await denyAdministrativeActions(alice);
});

test('temporary migration access never grants bans, debate deletion or global chat deletion', async () => {
  await db.collection('admin_runtime').doc('migration_access').set({
    enabled: true, allowedUids: [alice], reason: 'An isolated migration test',
    expiresAt: firestore.Timestamp.fromMillis(Date.now() + 3600000),
  });
  assert.deepEqual(await administrativeAccess(alice), { admin: false, migration: true });
  assert.deepEqual(await administrativeAccess(viewer), { admin: false, migration: false });
  await denyAdministrativeActions(alice);
});

test('expired, disabled and unbounded migration policies grant no access', async () => {
  for (const patch of [
    { expiresAt: firestore.Timestamp.fromMillis(Date.now() - 1) },
    { expiresAt: firestore.Timestamp.fromMillis(Date.now() + 25 * 3600000) },
    { enabled: false },
  ]) {
    await db.collection('admin_runtime').doc('migration_access').set({
      enabled: true, allowedUids: [alice],
      expiresAt: firestore.Timestamp.fromMillis(Date.now() + 3600000), ...patch,
    });
    assert.deepEqual(await administrativeAccess(alice), { admin: false, migration: false });
  }
});

test('only a boolean administrative custom claim authorizes administrative actions', async () => {
  assert.deepEqual(await administrativeAccess(alice, { admin: 'true' }), { admin: false, migration: false });
  assert.deepEqual(await administrativeAccess(alice, { admin: true }), { admin: true, migration: true });
  await functions.adminBanUser.run({ auth: { uid: alice, token: { admin: true } }, data: { userId: bob } });
  assert.equal((await db.collection('users').doc(bob).get()).data().isBanned, true);
});

test('administrative access discovery requires authentication', async () => {
  await assert.rejects(administrativeAccess(undefined), (error) => error.code === 'unauthenticated');
});

test('authorized debate deletion removes all descendant documents while preserving other debates', async () => {
  await seed();
  const descendants = [
    ref().collection('messages').doc('argument'),
    ref().collection('votes').doc(viewer),
    ref().collection('private_state').doc('judgement'),
    ref().collection('vote_tallies').doc('0'),
    ref().collection('messages').doc('argument').collection('metadata').doc('nested'),
  ];
  for (const document of descendants.slice(1)) await document.set({ keepUntilDeletion: true });
  const unrelated = db.collection('debates').doc('foundation-unrelated-debate');
  const unrelatedMessage = unrelated.collection('messages').doc('keep');
  await unrelated.set({ status: 'waiting', creatorId: bob });
  await unrelatedMessage.set({ text: 'Do not remove another debate' });
  try {
    const result = await functions.adminDeleteDebate.run({
      auth: { uid: alice, token: { admin: true } }, data: { debateId },
    });
    assert.equal(result.ok, true);
    assert.equal(result.alreadyAbsent, false);
    assert.equal((await ref().get()).exists, false);
    for (const document of descendants) assert.equal((await document.get()).exists, false, document.path);
    assert.equal((await unrelated.get()).exists, true);
    assert.equal((await unrelatedMessage.get()).exists, true);
  } finally {
    await db.recursiveDelete(unrelated);
  }
});

test('administrative deletion cleans orphan descendants and repeated deletion is safe', async () => {
  const orphanVote = ref().collection('votes').doc(viewer);
  const orphanJudgement = ref().collection('private_state').doc('judgement');
  await orphanVote.set({ round_1: 2 });
  await orphanJudgement.set({ aiResult: validResult() });
  assert.equal((await ref().get()).exists, false);
  const request = { auth: { uid: alice, token: { admin: true } }, data: { debateId } };
  for (let attempt = 0; attempt < 2; attempt++) {
    const result = await functions.adminDeleteDebate.run(request);
    assert.deepEqual(result, { ok: true, alreadyAbsent: true });
    assert.equal((await orphanVote.get()).exists, false);
    assert.equal((await orphanJudgement.get()).exists, false);
  }
});

test('administrative deletion rejects paths and invalid document identifiers', async () => {
  await seed({ text: '' });
  for (const invalid of ['', '.', '..', '../users', `${debateId}/messages/argument`, 'x'.repeat(1501)]) {
    await assert.rejects(functions.adminDeleteDebate.run({
      auth: { uid: alice, token: { admin: true } }, data: { debateId: invalid },
    }), (error) => error.details?.reason === 'ADMIN_DELETE_DEBATE_ID_INVALID');
  }
  assert.equal((await ref().get()).exists, true);
});
