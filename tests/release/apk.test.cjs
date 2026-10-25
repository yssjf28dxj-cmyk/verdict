'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { assessApk, verifyApk } = require('../../scripts/verify-test-apk.cjs');
const certificate = 'Signer #1 certificate SHA-256 digest: a0f0813a621fdf1f65e2780f3ef8ace1421f849b3aa2e0ce61571c02b2c45378\n';
const badging = (version = '4005', pkg = 'com.example.verdict.test') =>
  `package: name='${pkg}' versionCode='${version}' versionName='1.0.0' platformBuildVersionName='16'\n`;
test('accepts a newer test version with original certificate', () => assert.equal(assessApk(badging(), certificate).ok, true));
test('rejects installed or older version', () => {
  for (const version of ['4004', '4003']) assert.equal(assessApk(badging(version), certificate).ok, false);
});
test('rejects production package', () => assert.equal(assessApk(badging('4005', 'com.example.verdict'), certificate).ok, false));
test('rejects changed or absent certificate', () => {
  for (const cert of ['', certificate.replace('a0f081', '000000')]) assert.equal(assessApk(badging(), cert).ok, false);
});
test('rejects additional signers', () => assert.equal(assessApk(badging(), certificate + certificate.replace('#1', '#2')).ok, false));
test('rejects malformed metadata and unsafe version integers', () => {
  for (const value of ['', badging('999999999999999999999')]) assert.equal(assessApk(value, certificate).ok, false);
});
test('SDK verification failure stops before metadata inspection', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'verdict-apk-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const apk = path.join(dir, 'file ; no-shell.apk');
  fs.writeFileSync(apk, 'fixture');
  let calls = 0;
  assert.throws(() => verifyApk(apk, dir, (exe, args) => {
    calls++;
    assert.equal(path.basename(exe), 'apksigner');
    assert.equal(args.at(-1), apk);
    throw new Error('invalid signature');
  }), /invalid signature/);
  assert.equal(calls, 1);
});
test('records content hash and rejects a file changed during inspection', t => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'verdict-apk-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const apk = path.join(dir, 'fixture.apk');
  fs.writeFileSync(apk, 'fixture');
  const run = exe => path.basename(exe) === 'apksigner' ? certificate : badging();
  assert.equal(verifyApk(apk, dir, run).ok, true);
  const changed = verifyApk(apk, dir, (exe, args) => {
    if (path.basename(exe) === 'aapt') fs.writeFileSync(apk, 'replacement');
    return run(exe, args);
  });
  assert.equal(changed.ok, false);
  assert.match(changed.failures.join(' '), /changed during/);
});
