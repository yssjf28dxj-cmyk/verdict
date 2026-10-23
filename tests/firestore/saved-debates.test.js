import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
import { before, after, beforeEach, test } from 'node:test';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, deleteDoc, doc, getDoc, getDocs, serverTimestamp, setDoc, Timestamp } from 'firebase/firestore';
let env;
before(async () => {
  const host = process.env.FIRESTORE_EMULATOR_HOST || '';
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(host)) throw new Error('Local emulator required');
  const [hostname, port] = host.split(':');
  env = await initializeTestEnvironment({ projectId: 'demo-verdict-rules', firestore: { host: hostname, port: Number(port),
    rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') } });
});
after(async () => env.cleanup());
beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    for (const visibilityMode of ['public', 'private', 'request_only']) {
      await setDoc(doc(ctx.firestore(), 'debates', visibilityMode), { status: 'finished', visibilityMode,
        fighter1: 'alice', fighter2: 'bob', creatorId: 'alice', topic: 'Protected topic' });
    }
  });
});
const db = (uid) => uid ? env.authenticatedContext(uid).firestore() : env.unauthenticatedContext().firestore();
const ref = (client, uid = 'alice', id = 'public') => doc(client, 'users', uid, 'saved_debates', id);
test('owner can save, list and remove a reference without changing the battle', async () => {
  const client = db('alice');
  await assertSucceeds(setDoc(ref(client), { savedAt: serverTimestamp() }));
  const snapshot = await assertSucceeds(getDocs(collection(client, 'users/alice/saved_debates')));
  assert.equal(snapshot.size, 1);
  assert.deepEqual(Object.keys(snapshot.docs[0].data()), ['savedAt']);
  await assertSucceeds(deleteDoc(ref(client)));
  assert.equal((await getDoc(doc(client, 'debates/public'))).data().status, 'finished');
});
test('another identity and signed-out callers cannot read or modify saved lists', async () => {
  await setDoc(ref(db('alice')), { savedAt: serverTimestamp() });
  for (const uid of ['bob', null]) {
    const client = db(uid);
    await assertFails(getDoc(ref(client)));
    await assertFails(getDocs(collection(client, 'users/alice/saved_debates')));
    await assertFails(setDoc(ref(client), { savedAt: serverTimestamp() }));
    await assertFails(deleteDoc(ref(client)));
  }
});
test('private battle can be saved only by an authorized participant', async () => {
  await assertSucceeds(setDoc(ref(db('alice'), 'alice', 'private'), { savedAt: serverTimestamp() }));
  await assertFails(setDoc(ref(db('viewer'), 'viewer', 'private'), { savedAt: serverTimestamp() }));
});
test('a bookmark never grants access after participant rights are revoked', async () => {
  const client = db('bob');
  await setDoc(ref(client, 'bob', 'private'), { savedAt: serverTimestamp() });
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'debates/private'),
    { status: 'finished', visibilityMode: 'private', fighter1: 'alice', fighter2: 'other' }));
  await assertSucceeds(getDoc(ref(client, 'bob', 'private')));
  await assertFails(getDoc(doc(client, 'debates/private')));
  await assertFails(setDoc(ref(client, 'bob', 'private'), { savedAt: serverTimestamp() }));
  await assertSucceeds(deleteDoc(ref(client, 'bob', 'private')));
});
test('request-only bookmark does not unlock protected messages', async () => {
  const client = db('viewer');
  await assertSucceeds(setDoc(ref(client, 'viewer', 'request_only'), { savedAt: serverTimestamp() }));
  await assertFails(getDoc(doc(client, 'debates/request_only/messages/secret')));
});
test('missing or unfinished battles and copied metadata are rejected', async () => {
  const client = db('alice');
  await assertFails(setDoc(ref(client, 'alice', 'missing'), { savedAt: serverTimestamp() }));
  await assertFails(setDoc(ref(client), { savedAt: serverTimestamp(), topic: 'Leaked title' }));
  await assertFails(setDoc(ref(client), { savedAt: Timestamp.fromMillis(1) }));
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'debates/public'), { status: 'active', visibilityMode: 'public' }));
  await assertFails(setDoc(ref(client), { savedAt: serverTimestamp() }));
});
test('banned users may remove old bookmarks but cannot create or update them', async () => {
  const client = db('alice');
  await setDoc(ref(client), { savedAt: serverTimestamp() });
  await env.withSecurityRulesDisabled((ctx) => setDoc(doc(ctx.firestore(), 'users/alice'), { isBanned: true }));
  await assertFails(setDoc(ref(client), { savedAt: serverTimestamp() }));
  await assertSucceeds(deleteDoc(ref(client)));
});
