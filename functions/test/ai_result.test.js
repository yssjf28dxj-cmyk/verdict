const test = require('node:test');
const assert = require('node:assert/strict');
const { validateAiResult } = require('../lib/domain/debate/ai_result');

const result = (patch = {}) => ({
  winnerId: 'alice', winnerKey: 'fighter1', scoreA: 80, scoreB: 20,
  reasoning: 'A clear argument supported by evidence.', ...patch,
});

test('AI verdict accepts either fighter and an explicit draw, preserving zero scores', () => {
  assert.equal(validateAiResult(result({ scoreB: 0 }), 'alice', 'bob').scoreB, 0);
  assert.equal(validateAiResult(result({ winnerId: 'bob', winnerKey: 'fighter2' }), 'alice', 'bob').winnerId, 'bob');
  assert.equal(validateAiResult(result({ winnerId: 'draw', winnerKey: 'draw' }), 'alice', 'bob').winnerKey, 'draw');
});

test('AI verdict cannot select an unrelated profile or contradict its winner key', () => {
  for (const patch of [
    { winnerId: 'admin' }, { winnerId: 'fighter1' }, { winnerId: '' },
    { winnerKey: 'fighter2' }, { winnerKey: 'draw' }, { winnerKey: undefined },
    { winnerId: 'draw', winnerKey: 'fighter1' },
  ]) assert.throws(() => validateAiResult(result(patch), 'alice', 'bob'), /winner/);
});

test('AI scores must be finite numbers in the supported range', () => {
  for (const score of [NaN, Infinity, -Infinity, -1, 101, '80', null, undefined]) {
    assert.throws(() => validateAiResult(result({ scoreA: score }), 'alice', 'bob'), /scores/);
    assert.throws(() => validateAiResult(result({ scoreB: score }), 'alice', 'bob'), /scores/);
  }
});

test('AI reasoning is a non-empty bounded string and unknown fields are discarded', () => {
  for (const reasoning of ['', '  ', 'x'.repeat(2001), null, [], 123]) {
    assert.throws(() => validateAiResult(result({ reasoning }), 'alice', 'bob'), /reasoning/);
  }
  const validated = validateAiResult(result({ reasoning: '  Valid reason.  ', profileWins: 1000 }), 'alice', 'bob');
  assert.equal(validated.reasoning, 'Valid reason.');
  assert.equal(validated.profileWins, undefined);
  assert.equal(validateAiResult(result({ reasoning: 'x'.repeat(2000) }), 'alice', 'bob').reasoning.length, 2000);
});

test('AI validation rejects malformed objects and invalid fighter identities', () => {
  for (const raw of [null, undefined, 'json', [], 1]) {
    assert.throws(() => validateAiResult(raw, 'alice', 'bob'));
  }
  for (const fighters of [['', 'bob'], ['alice', ''], ['alice', 'alice'], ['draw', 'bob']]) {
    assert.throws(() => validateAiResult(result(), ...fighters), /fighters/);
  }
});
