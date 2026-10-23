const test = require('node:test');
const assert = require('node:assert/strict');
const { generatePublicProfileId, isValidPublicProfileId, createProfileIdentityController } = require('../lib/profile_identity');

test('public identifier validation prevents unsafe or ambiguous registry document paths', () => {
  for (const id of ['VERDICT-12345678', 'VERDICT-AB12CD34EF', 'PUBLIC-1']) {
    assert.equal(isValidPublicProfileId(id), true);
  }
  for (const id of [null, undefined, 12345678, '', '/', '../profile', 'VERDICT/USER',
    'VERDICT-lowercase', ' VERDICT-USER', 'VERDICT-USER ', 'X'.repeat(65)]) {
    assert.equal(isValidPublicProfileId(id), false);
  }
});

test('new public identifiers contain eight decimal digits and use the established prefix', () => {
  for (let i = 0; i < 100; i++) {
    assert.match(generatePublicProfileId(), /^VERDICT-[1-9]\d{7}$/);
  }
});

test('invalid identity requests cannot access or create Firestore paths', async () => {
  const controller = createProfileIdentityController({
    collection: () => assert.fail('Invalid UID must be rejected before accessing Firestore'),
  });
  for (const uid of ['', '/', '../someone', '.', '..', ' user', 'user ', 'x'.repeat(129)]) {
    await assert.rejects(controller.ensure(uid), (error) => error.details?.reason === 'PROFILE_UID_INVALID');
  }
});
