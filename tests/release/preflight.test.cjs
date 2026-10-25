const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { checkTestRelease } = require('../../scripts/check-test-release.cjs');
const root = path.resolve(__dirname, '../..');
const files = ['android/app/src/staging/google-services.json', 'firebase.staging.json', 'firebase.foundation.staging.json',
  'firestore.rules', 'storage.rules', 'firestore.staging.indexes.json', 'firebase.invites.staging.json',
  'web/invitations/.well-known/assetlinks.json', 'functions/src/index.ts',
  'scripts/deploy-test-foundation.sh', 'scripts/deploy-test-deadlines.sh'];
function fixture(t) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'verdict-release-check-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  for (const file of files) { const target = path.join(dir, file); fs.mkdirSync(path.dirname(target), { recursive: true }); fs.copyFileSync(path.join(root, file), target); }
  return dir;
}
function change(dir, file, mutate) {
  const target = path.join(dir, file), data = JSON.parse(fs.readFileSync(target)); mutate(data); fs.writeFileSync(target, JSON.stringify(data));
}
test('current source configuration passes without claiming cloud or certificate verification', () => {
  const result = checkTestRelease(root); assert.equal(result.ok, true, result.failures.join('\n'));
  assert.ok(result.unchecked.includes('Actual APK certificate and version'));
});
for (const [label, file, mutate] of [
  ['production project', 'android/app/src/staging/google-services.json', data => { data.project_info.project_id = 'verdict-final'; }],
  ['wrong database', 'firebase.foundation.staging.json', data => { data.firestore.database = '(default)'; }],
  ['production Hosting', 'firebase.invites.staging.json', data => { data.hosting.site = 'verdict-final'; }],
  ['changed certificate', 'web/invitations/.well-known/assetlinks.json', data => { data[0].target.sha256_cert_fingerprints = ['00']; }],
  ['missing rules', 'firebase.foundation.staging.json', data => { data.firestore.rules = '../outside.rules'; }],
  ['wrong runtime', 'firebase.staging.json', data => { data.functions[0].runtime = 'nodejs20'; }],
]) test(`preflight blocks ${label}`, t => {
  const dir = fixture(t); change(dir, file, mutate); assert.equal(checkTestRelease(dir).ok, false);
});
test('preflight blocks a deploy selector without an exported function', t => {
  const dir = fixture(t), filename = path.join(dir, 'scripts/deploy-test-foundation.sh');
  fs.appendFileSync(filename, '\n# functions:typoFunction\n');
  assert.equal(checkTestRelease(dir).ok, false);
});
test('preflight blocks omitted notification delivery before changing cloud resources', t => {
  const dir = fixture(t), filename = path.join(dir, 'scripts/deploy-test-foundation.sh');
  fs.writeFileSync(filename, fs.readFileSync(filename, 'utf8').replace('functions:deliverDebateNotification,', ''));
  assert.equal(checkTestRelease(dir).ok, false);
});
