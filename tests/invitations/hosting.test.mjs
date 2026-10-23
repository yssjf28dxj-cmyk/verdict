import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { invitationId, appIntent } from '../../web/invitations/invite.mjs';

test('web fallback builds only the known test app intent', () => {
  assert.equal(appIntent('/invite/abc_123-ABC'),
    'intent://app/invite/abc_123-ABC#Intent;scheme=verdicttest;package=com.example.verdict.test;end');
});
test('malformed paths cannot inject another package, redirect or script', () => {
  for (const path of [null, '/invite/', '/invite/a/b', '/invite/../profile', '/invite/%2Fprofile',
    '/invite/a#Intent;package=evil;end', '/invite/a?redirect=https://evil.test',
    '/invite/<script>', `/invite/${'a'.repeat(129)}`]) {
    assert.equal(invitationId(path), null);
    assert.equal(appIntent(path), null);
  }
});
test('Hosting is isolated to the test site and uploads Android association data', async () => {
  const config = JSON.parse(await readFile(new URL('../../firebase.invites.staging.json', import.meta.url)));
  assert.deepEqual(Object.keys(config), ['hosting']);
  assert.equal(config.hosting.site, 'verdict-test-1471f');
  assert.equal(config.hosting.public, 'web/invitations');
  const require = createRequire(new URL('../firestore/package.json', import.meta.url));
  const { listFiles } = require('firebase-tools/lib/listFiles');
  const files = listFiles(fileURLToPath(new URL('../../web/invitations', import.meta.url)), config.hosting.ignore);
  assert.ok(files.includes('.well-known/assetlinks.json'), 'Hidden-file ignores must not strip App Links association');
  assert.deepEqual(files.sort(), ['.well-known/assetlinks.json', 'index.html', 'invite.mjs', 'style.css'].sort());
  const headers = config.hosting.headers[0].headers;
  assert.ok(headers.some((h) => h.key === 'Referrer-Policy' && h.value === 'no-referrer'));
  assert.ok(headers.some((h) => h.key === 'Content-Security-Policy' && h.value.includes("default-src 'none'")));
});
test('Android association binds only the test package and matches its manifest host', async () => {
  const associations = JSON.parse(await readFile(new URL('../../web/invitations/.well-known/assetlinks.json', import.meta.url)));
  assert.equal(associations.length, 1);
  assert.equal(associations[0].target.package_name, 'com.example.verdict.test');
  assert.equal(associations[0].relation[0], 'delegate_permission/common.handle_all_urls');
  assert.match(associations[0].target.sha256_cert_fingerprints[0], /^([A-F0-9]{2}:){31}[A-F0-9]{2}$/);
  const manifest = await readFile(new URL('../../android/app/src/staging/AndroidManifest.xml', import.meta.url), 'utf8');
  assert.ok(manifest.includes('android:host="verdict-test-1471f.web.app"'));
  assert.ok(manifest.includes('android:pathPrefix="/invite/"'));
  const main = await readFile(new URL('../../android/app/src/main/AndroidManifest.xml', import.meta.url), 'utf8');
  assert.equal(main.includes('verdict-test-1471f.web.app'), false);
});
