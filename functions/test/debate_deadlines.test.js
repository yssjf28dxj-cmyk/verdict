const test = require('node:test');
const assert = require('node:assert/strict');
const firestore = require('firebase-admin/firestore');
const { readDeadline, sameDeadline, deadlineTaskId, planExpiredTurns } = require('../lib/debate_deadlines');
const state = (patch = {}) => ({
  status: 'active', isRoundActive: true, fighter1: 'alice', fighter2: 'bob',
  activeSpeakerId: 'alice', roundIndex: 1, totalRounds: 3,
  roundDurationSeconds: 60, roundEndsAt: firestore.Timestamp.fromMillis(100000), ...patch,
});
test('switches exactly at expiry without a media grace period', () => {
  assert.equal(planExpiredTurns('d', state(), 99999), null);
  const next = planExpiredTurns('d', state(), 100000);
  assert.equal(next.activeSpeakerId, 'bob');
  assert.equal(next.roundIndex, 1);
  assert.equal(next.roundEndsAt.toMillis(), 160000);
});
test('late delivery does not restart or extend the next timer', () => {
  assert.equal(planExpiredTurns('d', state(), 115000).roundEndsAt.toMillis(), 160000);
});
test('catches up multiple elapsed turns while every app was closed', () => {
  const next = planExpiredTurns('d', state(), 225000);
  assert.equal(next.activeSpeakerId, 'bob');
  assert.equal(next.roundIndex, 2);
  assert.equal(next.roundEndsAt.toMillis(), 280000);
});
test('finishes if all turns have elapsed, including five-round debates', () => {
  assert.equal(planExpiredTurns('d', state({ totalRounds: 1 }), 160000).status, 'finished');
  assert.equal(planExpiredTurns('d', state({ totalRounds: 5 }), 1000000).status, 'finished');
});
test('penalties apply once and retain the five-second minimum', () => {
  const next = planExpiredTurns('d', state({ pendingPenalty: { bob: 100, alice: 10 } }), 106000);
  assert.equal(next.activeSpeakerId, 'alice');
  assert.equal(next.roundIndex, 2);
  assert.equal(next.roundEndsAt.toMillis(), 155000);
  assert.deepEqual(next.pendingPenalty, { bob: 0, alice: 0 });
});
test('waiting, finished, paused and missing-opponent debates never start themselves', () => {
  for (const patch of [{ status: 'waiting' }, { status: 'finished' }, { isRoundActive: false },
    { fighter2: '' }, { fighter2: 'Оппонент' }, { fighter2: 'alice' }]) {
    assert.equal(readDeadline('d', state(patch)), null);
  }
});
test('deadline token changes for a new speaker, round or deadline', () => {
  const original = readDeadline('d', state());
  assert(sameDeadline(original, readDeadline('d', state())));
  for (const patch of [{ activeSpeakerId: 'bob' }, { roundIndex: 2 },
    { roundEndsAt: firestore.Timestamp.fromMillis(99900) }]) {
    const next = readDeadline('d', state(patch));
    assert(!sameDeadline(original, next));
    assert.notEqual(deadlineTaskId(original), deadlineTaskId(next));
  }
});
test('invalid timer settings fail rather than silently extend the debate', () => {
  assert.throws(() => planExpiredTurns('d', state({ totalRounds: -1 }), 100000));
});
test('server rejects outgoing messages at an expired turn with zero grace', () => {
  const { assertCanSendMessage } = require('../lib/domain/debate/guards');
  assert.throws(() => assertCanSendMessage({
    uid: 'alice', debate: state({ roundEndsAt: firestore.Timestamp.fromMillis(Date.now() - 1) }),
    status: 'active', hasReadAccess: true, isPlayableStatus: true, uploadGraceMs: 0,
  }), /Время хода истекло/);
});
test('yielded turn gives the next fighter full duration without subtracting legacy grace', () => {
  const now = 500000;
  const next = planExpiredTurns('d', state({ roundEndsAt: firestore.Timestamp.fromMillis(now) }), now);
  assert.equal(next.activeSpeakerId, 'bob');
  assert.equal(next.roundEndsAt.toMillis(), now + 60000);
});

const { planHandOff } = require('../lib/debate_deadlines');
test('bank handoff saves remaining time for its owner and consumes the next speaker bank once', () => {
  const data = { ...state(), clockMode: 'bank_v1', timeBankMs: { alice: 0, bob: 30000 } };
  const next = planHandOff('d', data, 'alice', 70000);
  assert.equal(next.activeSpeakerId, 'bob');
  assert.equal(next.timeBankMs.alice, 30000);
  assert.equal(next.timeBankMs.bob, 0);
  assert.equal(next.roundEndsAt.toMillis(), 160000);
  const second = planHandOff('d', { ...data, ...next }, 'bob', 100000);
  assert.equal(second.activeSpeakerId, 'alice');
  assert.equal(second.roundIndex, 2);
  assert.equal(second.roundEndsAt.toMillis(), 190000);
  assert.equal(second.timeBankMs.alice, 0);
  assert.equal(second.timeBankMs.bob, 60000);
});
test('bank automatic expiry does not mint unused time during delayed delivery', () => {
  const next = planExpiredTurns('d', { ...state(), clockMode: 'bank_v1', timeBankMs: { alice: 0, bob: 30000 } }, 220000);
  assert.equal(next.activeSpeakerId, 'alice');
  assert.equal(next.roundIndex, 2);
  assert.equal(next.roundEndsAt.toMillis(), 250000);
  assert.deepEqual(next.timeBankMs, { alice: 0, bob: 0 });
});
test('handoff rejects the other fighter and legacy clocks do not gain a bank', () => {
  assert.throws(() => planHandOff('d', state(), 'bob', 90000));
  const next = planHandOff('d', state(), 'alice', 90000);
  assert.equal(next.timeBankMs, undefined);
  assert.equal(next.roundEndsAt.toMillis(), 150000);
});
test('final handoff ends the debate and expired handoff saves no extra time', () => {
  const final = { ...state(), clockMode: 'bank_v1', activeSpeakerId: 'bob', totalRounds: 1 };
  assert.equal(planHandOff('d', final, 'bob', 90000).status, 'finished');
  const next = planHandOff('d', { ...state(), clockMode: 'bank_v1' }, 'alice', 110000);
  assert.equal(next.roundEndsAt.toMillis(), 160000);
  assert.equal(next.timeBankMs.alice || 0, 0);
});
