const test = require('node:test');
const assert = require('node:assert/strict');
const { countStoredVotes } = require('../lib/domain/debate/votes');

test('final votes preserve one vote per round plus one debate vote', () => {
  assert.deepEqual(countStoredVotes([
    { uid: 'a', round_1: 1, round_2: 2, round_3: 1, debate: 2 },
    { uid: 'b', round_1: 2, debate: 2 },
  ], 3), { votes1: 2, votes2: 4 });
});

test('numeric metadata, nonexistent rounds and unsupported side values cannot change a winner', () => {
  assert.deepEqual(countStoredVotes([
    { uid: 2, updatedAt: 2, round_1: 1, round_2: 2, round_99: 2, arbitrary: 2, debate: '2' },
    { round_1: null, debate: 0 }, { round_1: true, debate: NaN },
  ], 1), { votes1: 1, votes2: 0 });
  assert.deepEqual(countStoredVotes([], 5), { votes1: 0, votes2: 0 });
});

test('invalid aggregation settings fail rather than silently count the wrong rounds', () => {
  for (const rounds of [0, -1, 6, 1.5, NaN, '3']) {
    assert.throws(() => countStoredVotes([], rounds), /total rounds/);
  }
});
