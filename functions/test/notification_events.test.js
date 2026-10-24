const test = require('node:test');
const assert = require('node:assert/strict');
const { planDebateNotifications: plan } = require('../lib/domain/debate/notification_events');
const time = n => ({ toMillis: () => n });
const active = () => ({ status: 'active', fighter1: 'alice', fighter2: 'bob', creatorId: 'alice',
  activeSpeakerId: 'bob', isRoundActive: true, roundEndsAt: time(1000) });
test('acceptance informs creator and first active speaker without private content', () => {
  const events = plan({ status: 'waiting' }, { ...active(), topic: 'private', text: 'secret' });
  assert.deepEqual(events.map(e => e.kind), ['accepted', 'turn']);
  assert.equal(JSON.stringify(events).includes('private'), false);
});
test('equivalent timestamp instances and unrelated writes do not repeat a turn', () => {
  assert.deepEqual(plan(active(), { ...active(), viewerCount: 2 }), []);
});
test('deadline or speaker changes get distinct deterministic turn identities', () => {
  const next = { ...active(), activeSpeakerId: 'alice', roundEndsAt: time(2000) };
  assert.deepEqual(plan(active(), next), plan(active(), next));
  assert.equal(plan(active(), next)[0].uid, 'alice');
});
test('finish informs both fighters once while duplicate finish is ignored', () => {
  const finished = { ...active(), status: 'finished' };
  assert.equal(plan(active(), finished).length, 2);
  assert.deepEqual(plan(finished, finished), []);
});
test('creation deletion cancellation and malformed fighters cannot notify', () => {
  assert.deepEqual(plan(undefined, active()), []);
  assert.deepEqual(plan(active(), undefined), []);
  assert.deepEqual(plan(active(), { ...active(), status: 'cancelled' }), []);
  assert.deepEqual(plan({ status: 'waiting' }, { ...active(), fighter2: 'alice' }), []);
});
