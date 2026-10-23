import { createRequire } from 'node:module';
import assert from 'node:assert/strict';
import { before, after, beforeEach, test } from 'node:test';
const require = createRequire(new URL('../../functions/package.json', import.meta.url));
const { initializeApp, deleteApp } = require('firebase-admin/app');
const { getFirestore } = require('firebase-admin/firestore');
const { createPrivateDataMigrationController } = require('./lib/private_data_migration');
let app, db;
const valid = { winnerId: 'alice', winnerKey: 'fighter1', scoreA: 80, scoreB: 20, reasoning: 'Evidence supports Alice.' };
const debate = () => db.collection('debates').doc('migration-debate');
const privateResult = () => debate().collection('private_state').doc('judgement');
before(() => {
  if (!/^(127\.0\.0\.1|localhost):\d+$/.test(process.env.FIRESTORE_EMULATOR_HOST || '')) throw new Error('Only a loopback Firestore emulator is allowed');
  app = initializeApp({ projectId: 'demo-verdict-rules' }); db = getFirestore(app);
});
after(async () => deleteApp(app));
beforeEach(async () => {
  for (const collection of ['users', 'debates', 'admin_private_data_archive']) await db.recursiveDelete(db.collection(collection));
  await db.doc('users/alice').set({ name: 'Alice', email: 'private@example.test', wins: 7 });
  await debate().set({ fighter1: 'alice', fighter2: 'bob', status: 'finished', aiResult: valid });
});
test('dry run reports fields without changing data or creating an archive', async () => {
  const report = await createPrivateDataMigrationController(db, { pageSize: 1 }).run();
  assert.equal(report.emailsFound, 1); assert.equal(report.aiResultsFound, 1); assert.equal(report.applied, 0);
  assert.equal((await db.collection('admin_private_data_archive').get()).size, 0);
  assert.equal((await db.doc('users/alice').get()).get('email'), 'private@example.test');
  assert.deepEqual((await debate().get()).get('aiResult'), valid);
});
test('apply archives original fields, preserves unrelated stats and protects AI', async () => {
  const report = await createPrivateDataMigrationController(db).run({ apply: true });
  assert.equal(report.applied, 2); assert.equal((await db.doc('users/alice').get()).get('email'), undefined);
  assert.equal((await db.doc('users/alice').get()).get('wins'), 7);
  assert.equal((await debate().get()).get('aiResult'), undefined);
  assert.deepEqual((await privateResult().get()).get('aiResult'), { ...valid, status: 'ready' });
  const records = (await db.doc(report.archivePath).collection('records').get()).docs.map((doc) => doc.data());
  assert.equal(records.length, 2); assert.equal(records.find((r) => r.field === 'email').originalValue, 'private@example.test');
  assert.deepEqual(records.find((r) => r.field === 'aiResult').originalValue, valid);
  assert.equal((await db.doc(report.archivePath).get()).get('status'), 'completed');
});
test('newer protected judgement is never overwritten', async () => {
  const newer = { status: 'unavailable', reason: 'not_configured', error: true };
  await privateResult().set({ aiResult: newer }); await createPrivateDataMigrationController(db).run({ apply: true });
  assert.deepEqual((await privateResult().get()).get('aiResult'), newer);
});
test('old no-content fake draw becomes an explicit insufficient-content state', async () => {
  await debate().update({ aiResult: { ...valid, winnerId: 'draw', winnerKey: 'draw', scoreA: 50, scoreB: 50,
    reasoning: 'Текстовых аргументов не обнаружено — вердикт не может быть вынесен.' } });
  await createPrivateDataMigrationController(db).run({ apply: true });
  assert.deepEqual((await privateResult().get()).get('aiResult'), { status: 'insufficient_content', reason: 'no_content', error: true });
});
test('provider errors are redacted for readers and exact original is archived', async () => {
  const raw = { ...valid, error: true, reason: 'Provider request included PRIVATE_TEST_VALUE' };
  await debate().update({ aiResult: raw }); const report = await createPrivateDataMigrationController(db).run({ apply: true });
  assert.deepEqual((await privateResult().get()).get('aiResult'), { status: 'error', reason: 'unavailable', error: true });
  const records = await db.doc(report.archivePath).collection('records').where('field', '==', 'aiResult').get();
  assert.deepEqual(records.docs[0].get('originalValue'), raw);
});
test('second migration cannot duplicate moved fields', async () => {
  await createPrivateDataMigrationController(db).run({ apply: true });
  const report = await createPrivateDataMigrationController(db).run({ apply: true });
  assert.equal(report.applied, 0); assert.equal(report.emailsFound, 0); assert.equal(report.aiResultsFound, 0);
  assert.equal((await db.doc(report.archivePath).collection('records').get()).size, 0);
});
test('concurrent migrations archive each field exactly once', async () => {
  const reports = await Promise.all([createPrivateDataMigrationController(db).run({ apply: true }), createPrivateDataMigrationController(db).run({ apply: true })]);
  assert.equal(reports.reduce((sum, report) => sum + report.applied, 0), 2);
  assert.equal((await db.collectionGroup('records').get()).size, 2);
});
test('archive transaction failure preserves public data and records a failed run', async () => {
  const original = db.runTransaction.bind(db), controller = createPrivateDataMigrationController(db);
  db.runTransaction = (callback, options) => original(async (tx) => {
    await callback(tx); throw new Error('Injected archive transaction failure');
  }, options);
  try { await assert.rejects(controller.run({ apply: true }), /Injected archive transaction failure/); }
  finally { db.runTransaction = original; }
  assert.equal((await db.doc('users/alice').get()).get('email'), 'private@example.test');
  assert.equal((await db.doc(controller.archivePath).get()).get('status'), 'failed');
  assert.equal((await db.doc(controller.archivePath).collection('records').get()).size, 0);
  assert.equal(controller.getStats().applied, 0);
});
test('even the profile owner cannot read archived contact or provider error data', async () => {
  const { initializeTestEnvironment, assertFails } = await import('@firebase/rules-unit-testing');
  const { doc, getDoc } = await import('firebase/firestore');
  const [host, port] = process.env.FIRESTORE_EMULATOR_HOST.split(':');
  const environment = await initializeTestEnvironment({ projectId: 'demo-verdict-rules', firestore: { host, port: Number(port) } });
  try {
    const report = await createPrivateDataMigrationController(db).run({ apply: true });
    const record = (await db.doc(report.archivePath).collection('records').get()).docs[0];
    const client = environment.authenticatedContext('alice').firestore();
    await assertFails(getDoc(doc(client, report.archivePath)));
    await assertFails(getDoc(doc(client, record.ref.path)));
  } finally { await environment.cleanup(); }
});

const conflicts = [
  ['empty document', {}],
  ['missing aiResult', { revision: 1 }],
  ['null result', { aiResult: null }],
  ['array result', { aiResult: [] }],
  ['string result', { aiResult: 'PRIVATE_SYNTHETIC_PAYLOAD' }],
  ['missing ready fields', { aiResult: { status: 'ready' } }],
  ['wrong score type', { aiResult: { ...valid, scoreA: '80' } }],
  ['inconsistent winner', { aiResult: { ...valid, winnerKey: 'fighter2' } }],
  ['wrong reasoning type', { aiResult: { ...valid, reasoning: 123 } }],
  ['wrong error type', { aiResult: { ...valid, error: 'false' } }],
  ['wrong timestamp type', { aiResult: { ...valid, judgedAt: 'yesterday' } }],
  ['unknown status', { aiResult: { ...valid, status: 'pending' } }],
  ['terminal missing reason', { aiResult: { status: 'error', error: true } }],
  ['terminal missing error', { aiResult: { status: 'unavailable', reason: 'not_configured' } }],
  ['terminal wrong reason', { aiResult: { status: 'insufficient_content', reason: 'anything', error: true } }],
];
for (const [label, bad] of conflicts) {
  test(`guard refuses ${label} without changing source/private/field archive; retry remains safe`, async () => {
    // Isolate the conflicting document; run metadata is expected to change.
    await db.doc('users/alice').update({ email: require('firebase-admin/firestore').FieldValue.delete() });
    await privateResult().set(bad);
    const original = (await debate().get()).data();
    for (let attempt = 0; attempt < 2; attempt++) {
      const controller = createPrivateDataMigrationController(db);
      await assert.rejects(controller.run({ apply: true }), error => {
        assert.equal(error.message, 'PRIVATE_JUDGEMENT_CONFLICT: migration stopped; existing private judgement requires review');
        return true;
      });
      assert.deepEqual((await debate().get()).data(), original);
      assert.deepEqual((await privateResult().get()).data(), bad);
      assert.equal(controller.getStats().applied, 0);
      assert.equal((await db.doc(controller.archivePath).get()).get('status'), 'failed');
      assert.equal((await db.doc(controller.archivePath).collection('records').get()).size, 0);
    }
  });
}
const accepted = [
  ['historical ready without status', valid],
  ['ready', { ...valid, status: 'ready', error: false }],
  ['insufficient content', { status: 'insufficient_content', reason: 'no_content', error: true }],
  ['provider unavailable', { status: 'unavailable', reason: 'not_configured', error: true }],
  ['provider error', { status: 'error', reason: 'unavailable', error: true }],
];
for (const [label, existing] of accepted) {
  test(`guard preserves valid ${label}, metadata and exact archived root even when different`, async () => {
    const { Timestamp } = require('firebase-admin/firestore');
    const protectedData = { aiResult: { ...existing, judgedAt: Timestamp.fromMillis(123456) }, revision: 7 };
    const differentRoot = { ...valid, winnerId: 'bob', winnerKey: 'fighter2', scoreA: 20, scoreB: 80 };
    await debate().update({ aiResult: differentRoot });
    await privateResult().set(protectedData);
    const report = await createPrivateDataMigrationController(db).run({ apply: true });
    assert.deepEqual((await privateResult().get()).data(), protectedData);
    assert.equal((await debate().get()).get('aiResult'), undefined);
    const records = await db.doc(report.archivePath).collection('records').where('field', '==', 'aiResult').get();
    assert.equal(records.size, 1);
    assert.deepEqual(records.docs[0].get('originalValue'), differentRoot);
  });
}
test('guard fails after earlier commit; concurrent retries preserve conflict and do not duplicate archive', async () => {
  await privateResult().set({});
  const first = createPrivateDataMigrationController(db, { pageSize: 1 });
  await assert.rejects(first.run({ apply: true }), /PRIVATE_JUDGEMENT_CONFLICT/);
  assert.equal(first.getStats().applied, 1);
  assert.equal((await db.doc('users/alice').get()).get('email'), undefined);
  const attempts = [createPrivateDataMigrationController(db), createPrivateDataMigrationController(db)];
  const results = await Promise.allSettled(attempts.map(c => c.run({ apply: true })));
  assert.ok(results.every(r => r.status === 'rejected' && /PRIVATE_JUDGEMENT_CONFLICT/.test(r.reason.message)));
  assert.deepEqual((await debate().get()).get('aiResult'), valid);
  assert.deepEqual((await privateResult().get()).data(), {});
  assert.equal((await db.collectionGroup('records').get()).size, 1);
  // Resolution is synthetic and explicit; the migration itself never chooses it.
  await privateResult().delete();
  const resumed = await createPrivateDataMigrationController(db).run({ apply: true });
  assert.equal(resumed.applied, 1);
  assert.deepEqual((await privateResult().get()).get('aiResult'), { ...valid, status: 'ready' });
  assert.equal((await db.collectionGroup('records').get()).size, 2);
});
test('guard sees concurrent private creation before its protected read', async () => {
  const originalRun = db.runTransaction.bind(db);
  let changed = false;
  await db.doc('users/alice').update({ email: require('firebase-admin/firestore').FieldValue.delete() });
  db.runTransaction = (callback, options) => originalRun(async tx => {
    const originalGet = tx.get.bind(tx);
    tx.get = async ref => {
      // Real committed write before this document is read/locked by migration.
      if (!changed && ref.path === privateResult().path) {
        changed = true;
        await privateResult().set({});
      }
      return originalGet(ref);
    };
    return callback(tx);
  }, options);
  try {
    const controller = createPrivateDataMigrationController(db);
    await assert.rejects(controller.run({ apply: true }), /PRIVATE_JUDGEMENT_CONFLICT/);
    assert.equal((await db.doc(controller.archivePath).collection('records').get()).size, 0);
  } finally { db.runTransaction = originalRun; }
  assert.equal(changed, true);
  assert.deepEqual((await privateResult().get()).data(), {});
  assert.deepEqual((await debate().get()).get('aiResult'), valid);
});
