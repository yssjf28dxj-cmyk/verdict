import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { before, after, beforeEach, test } from 'node:test';

const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const firestore = require('firebase-admin/firestore');
const { initializeApp, getApp, deleteApp } = require('firebase-admin/app');
const { createProfileIdentityController } = require('./lib/profile_identity');
const projectId = 'demo-verdict-rules';
let db;
let sequence;
const profile = (uid) => db.collection('users').doc(uid);
const claim = (id) => db.collection('public_profile_ids').doc(id);
const controller = (generate = () => `VERDICT-${sequence++}`) => createProfileIdentityController(db, generate);

before(() => {
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '')) {
    throw new Error('Profile identity tests require a loopback Firestore emulator');
  }
  initializeApp({ projectId });
  db = firestore.getFirestore();
});
after(async () => deleteApp(getApp()));
beforeEach(async () => {
  await db.recursiveDelete(db.collection('users'));
  await db.recursiveDelete(db.collection('public_profile_ids'));
  sequence = 10000000;
});

test('concurrent requests for one profile return the same persisted identifier', async () => {
  await profile('alice').set({ name: 'Alice' });
  const identities = controller();
  const results = await Promise.all(Array.from({ length: 5 }, () => identities.ensure('alice')));
  const id = results[0].publicId;
  assert(results.every((result) => result.status === 'ready' && result.publicId === id));
  assert.equal((await profile('alice').get()).get('publicId'), id);
  assert.equal((await claim(id).get()).get('uid'), 'alice');
  assert.equal((await db.collection('public_profile_ids').get()).size, 1);
});

test('different profiles receive distinct claims when candidate allocation collides', async () => {
  await Promise.all(['alice', 'bob', 'carol'].map((uid) => profile(uid).set({ name: uid })));
  let calls = 0;
  const identities = controller(() => calls++ < 3 ? 'VERDICT-11111111' : `VERDICT-${sequence++}`);
  const results = await Promise.all(['alice', 'bob', 'carol'].map((uid) => identities.ensure(uid)));
  assert.equal(new Set(results.map((result) => result.publicId)).size, 3);
  for (const uid of ['alice', 'bob', 'carol']) {
    const id = (await profile(uid).get()).get('publicId');
    assert.equal((await claim(id).get()).get('uid'), uid);
  }
});

test('an absent or deleted profile does not create an identity or a ghost profile', async () => {
  assert.deepEqual(await controller().ensure('missing'), { status: 'profile_missing' });
  assert.equal((await profile('missing').get()).exists, false);
  assert.equal((await db.collection('public_profile_ids').get()).size, 0);
});

test('an existing legacy UID-prefix identifier is preserved and claimed idempotently', async () => {
  const id = 'VERDICT-AB12CD34EF';
  await profile('alice').set({ publicId: id, name: 'Alice' });
  const identities = controller();
  assert.deepEqual(await identities.ensure('alice'), { status: 'ready', publicId: id });
  assert.deepEqual(await identities.ensure('alice'), { status: 'ready', publicId: id });
  assert.equal((await profile('alice').get()).get('publicId'), id);
  assert.equal((await claim(id).get()).get('uid'), 'alice');
  assert.equal((await db.collection('public_profile_ids').get()).size, 1);
});

test('legacy registry conflicts are reported without changing or taking either identity', async () => {
  const id = 'VERDICT-AB12CD34EF';
  await profile('alice').set({ publicId: id });
  await claim(id).set({ uid: 'bob' });
  assert.deepEqual(await controller().ensure('alice'), { status: 'legacy_conflict', publicId: id });
  assert.equal((await profile('alice').get()).get('publicId'), id);
  assert.equal((await claim(id).get()).get('uid'), 'bob');
});

test('duplicate unregistered legacy identifiers are detected before claiming one of them', async () => {
  const id = 'VERDICT-AB12CD34EF';
  await Promise.all(['alice', 'bob'].map((uid) => profile(uid).set({ publicId: id })));
  assert.deepEqual(await controller().ensure('alice'), { status: 'legacy_conflict', publicId: id });
  assert.equal((await claim(id).get()).exists, false);
  assert.equal((await profile('alice').get()).get('publicId'), id);
  assert.equal((await profile('bob').get()).get('publicId'), id);
});

test('invalid stored identifiers are reported without silently replacing previously shared values', async () => {
  await profile('alice').set({ publicId: 'VERDICT/USER' });
  assert.deepEqual(await controller().ensure('alice'), { status: 'invalid_legacy_id' });
  assert.equal((await profile('alice').get()).get('publicId'), 'VERDICT/USER');
  assert.equal((await db.collection('public_profile_ids').get()).size, 0);
});

test('allocation cannot steal an unregistered legacy identifier and fails after bounded collisions', async () => {
  const id = 'VERDICT-12345678';
  await profile('alice').set({ publicId: id });
  await profile('bob').set({ name: 'Bob' });
  let attempts = 0;
  await assert.rejects(controller(() => { attempts++; return id; }).ensure('bob'),
    (error) => error.details?.reason === 'PROFILE_PUBLIC_ID_EXHAUSTED');
  assert.equal(attempts, 8);
  assert.equal((await profile('bob').get()).get('publicId'), undefined);
  assert.equal((await profile('alice').get()).get('publicId'), id);
  assert.equal((await claim(id).get()).exists, false);
});
