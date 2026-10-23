const test = require('node:test');
const assert = require('node:assert/strict');
const { requestDocumentId, assertRateLimit } = require('../lib/request_control');

test('legacy requests omit the id while modern ids are bounded and namespace by user', () => {
  assert.equal(requestDocumentId('alice', undefined), null);
  assert.equal(requestDocumentId('alice', null), null);
  const id = 'a'.repeat(40);
  const first = requestDocumentId('alice', id);
  assert.match(first, /^[0-9a-f]{64}$/);
  assert.equal(requestDocumentId('alice', id), first);
  assert.notEqual(requestDocumentId('bob', id), first);
  for (const invalid of ['', 'short', 'a'.repeat(129), 'a'.repeat(16) + '/', {}, 5]) {
    assert.throws(() => requestDocumentId('alice', invalid), (error) => error.details?.reason === 'REQUEST_ID_INVALID');
  }
});

test('rate limit rejects requests inside the interval and allows the exact boundary', () => {
  assert.doesNotThrow(() => assertRateLimit(undefined, 100, 3000));
  assert.throws(() => assertRateLimit({ lastAtMs: 1000 }, 3999, 3000), (error) =>
    error.details?.reason === 'RATE_LIMIT_EXCEEDED' && error.details.retryAfterMs === 1);
  assert.doesNotThrow(() => assertRateLimit({ lastAtMs: 1000 }, 4000, 3000));
});
