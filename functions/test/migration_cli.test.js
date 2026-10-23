const test = require('node:test');
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { resolve } = require('node:path');
const script = resolve(__dirname, '../../scripts/migrate-test-private-data.cjs');
const run = (args, extra = {}) => spawnSync(process.execPath, [script, ...args], {
  encoding: 'utf8', timeout: 5000, env: { ...process.env, ...extra },
});
test('migration CLI refuses unknown or repeated apply arguments before opening a database', () => {
  for (const args of [['--project=verdict-final'], ['--apply', '--apply'], ['--force']]) {
    const result = run(args); assert.equal(result.status, 1); assert.match(result.stderr, /Only a single --apply/);
  }
});
test('migration CLI refuses a selected production project before loading credentials', () => {
  const result = run(['--apply'], { FIRESTORE_EMULATOR_HOST: '', GCLOUD_PROJECT: 'verdict-final' });
  assert.equal(result.status, 1); assert.match(result.stderr, /Refusing another selected project/);
});
test('cloud migration wrapper cannot silently run against an emulator', () => {
  const result = run([], { FIRESTORE_EMULATOR_HOST: '127.0.0.1:8085' });
  assert.equal(result.status, 1); assert.match(result.stderr, /separate emulator tests/);
});
